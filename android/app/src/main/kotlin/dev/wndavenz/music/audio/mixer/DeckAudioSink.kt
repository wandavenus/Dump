package dev.wndavenz.music.audio.mixer

import android.media.AudioDeviceInfo
import androidx.media3.common.AudioAttributes
import androidx.media3.common.AuxEffectInfo
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioOffloadSupport
import androidx.media3.exoplayer.audio.AudioSink
import java.nio.ByteBuffer
import java.util.ArrayDeque

/**
 * Virtual `AudioSink` for one ExoPlayer deck.
 *
 * It implements the full Media3 1.11 `AudioSink` contract — configure,
 * handleBuffer backpressure, flush, play/pause, EOS, position, volume — but
 * **never creates an AudioTrack**. Decoded PCM runs through the deck's own
 * processor chain in [DeckAudioPipeline] and is appended to the deck ring owned
 * by [SingleAudioTrackEngine]. Only the engine writes to hardware.
 *
 * Per-deck operations are isolated: `flush()`/`reset()` replace this deck's
 * stream generation and leave the other deck and the shared sink untouched.
 *
 * `getCurrentPositionUs` is derived from frames the shared output actually
 * played (minus frames still in flight), not from decoder or ring progress.
 */
@UnstableApi
class DeckAudioSink(
    private val engine: SingleAudioTrackEngine,
    private val output: Media3SharedAudioOutput,
    private val slot: Int,
    processors: List<AudioProcessor>,
    private val log: (String) -> Unit = {},
) : AudioSink {

    private class PendingBlock(
        val pcm: FloatArray,
        var offsetFrames: Int,
        var frames: Int,
        var sourceStartUs: Long,
        var sourceDurationUs: Long,
    ) {
        val isEmpty: Boolean get() = frames <= 0

        fun advance(accepted: Int) {
            if (accepted <= 0) return
            val consumedUs = if (frames > 0) {
                sourceDurationUs * accepted / frames
            } else {
                0L
            }
            offsetFrames += accepted
            frames -= accepted
            sourceStartUs += consumedUs
            sourceDurationUs -= consumedUs
        }
    }

    private val pipeline = DeckAudioPipeline(
        processors = processors,
        busSampleRate = engine.busSampleRate,
        log = log,
    )
    private val pending = ArrayDeque<PendingBlock>()

    private var listener: AudioSink.Listener? = null
    private var configuredFormat: Format? = null
    private var generation: Long = 0L

    private var playbackParameters: PlaybackParameters = PlaybackParameters.DEFAULT
    private var skipSilenceEnabled: Boolean = false
    private var audioAttributes: AudioAttributes = AudioAttributes.DEFAULT

    private var retryBuffer: ByteBuffer? = null
    private var retryPosition: Int = 0
    private var retryLimit: Int = 0

    /** Bytes of an incomplete PCM frame carried into the next buffer. */
    private var leftover = ByteArray(0)
    private var pendingTail: ByteArray? = null
    private var inputScratch = ByteArray(0)

    private val busListener = object : SharedAudioOutput.Listener {
        override fun onUnderrun(
            bufferSizeBytes: Int,
            bufferSizeMs: Long,
            elapsedSinceLastFeedMs: Long,
        ) {
            listener?.onUnderrun(bufferSizeBytes, bufferSizeMs, elapsedSinceLastFeedMs)
        }

        override fun onPositionDiscontinuity() {
            listener?.onPositionDiscontinuity()
        }

        override fun onAudioSessionIdChanged(audioSessionId: Int) {
            listener?.onAudioSessionIdChanged(audioSessionId)
        }

        override fun onAudioTrackInitialized(
            encoding: Int,
            sampleRate: Int,
            channelConfig: Int,
            bufferSize: Int,
        ) {
            listener?.onAudioTrackInitialized(
                AudioSink.AudioTrackConfig(
                    encoding,
                    sampleRate,
                    channelConfig,
                    /* tunneling= */ false,
                    /* offload= */ false,
                    bufferSize,
                ),
            )
        }

        override fun onAudioTrackReleased(
            encoding: Int,
            sampleRate: Int,
            channelConfig: Int,
        ) {
            listener?.onAudioTrackReleased(
                AudioSink.AudioTrackConfig(
                    encoding,
                    sampleRate,
                    channelConfig,
                    /* tunneling= */ false,
                    /* offload= */ false,
                    /* bufferSize= */ 0,
                ),
            )
        }

        override fun onSinkError(message: String) {
            listener?.onAudioSinkError(IllegalStateException(message))
        }

        override fun onError(message: String) {
            listener?.onAudioSinkError(IllegalStateException(message))
        }
    }

    init {
        generation = engine.addDeck(slot)
        engine.addBusListener(busListener)
    }

    // ── Capabilities / configuration ─────────────────────────────────────────

    override fun setListener(listener: AudioSink.Listener) {
        this.listener = listener
    }

    override fun supportsFormat(format: Format): Boolean {
        if (format.sampleMimeType != MimeTypes.AUDIO_RAW) return false
        if (format.channelCount <= 0) return false
        return DeckAudioPipeline.isSupportedEncoding(format.pcmEncoding)
    }

    override fun getFormatSupport(format: Format): Int {
        if (format.sampleMimeType != MimeTypes.AUDIO_RAW) {
            // Non-PCM formats must be decoded by Media3 before reaching a deck.
            return AudioSink.SINK_FORMAT_UNSUPPORTED
        }
        return if (supportsFormat(format)) {
            AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY
        } else {
            AudioSink.SINK_FORMAT_UNSUPPORTED
        }
    }

    override fun getFormatOffloadSupport(format: Format): AudioOffloadSupport =
        AudioOffloadSupport.DEFAULT_UNSUPPORTED

    override fun configure(audioSinkConfig: AudioSink.AudioSinkConfig) {
        val format = audioSinkConfig.format
        if (!supportsFormat(format)) {
            throw AudioSink.ConfigurationException(
                "DeckAudioSink accepts linear PCM only: " +
                    "mime=${format.sampleMimeType} encoding=${format.pcmEncoding}",
                format,
            )
        }
        if (!engine.configureOutput()) {
            throw AudioSink.ConfigurationException(
                "Shared mix bus could not be configured",
                format,
            )
        }
        try {
            pipeline.configure(format)
        } catch (error: Exception) {
            throw AudioSink.ConfigurationException(error, format)
        }
        configuredFormat = format
        generation = engine.resetDeck(slot)
        clearPending()
        engine.executeOnOutputThread { output.setAudioAttributes(audioAttributes) }
        log(
            "Deck $slot configured: ${format.sampleRate}Hz/${format.channelCount}ch " +
                "encoding=${format.pcmEncoding} generation=$generation",
        )
    }

    // ── Buffer flow ──────────────────────────────────────────────────────────

    override fun play() {
        engine.setDeckPlaying(slot, true)
    }

    override fun pause() {
        engine.setDeckPlaying(slot, false)
    }

    override fun handleBuffer(
        buffer: ByteBuffer,
        presentationTimeUs: Long,
        encodedAccessUnitCount: Int,
    ): Boolean {
        val format = configuredFormat
        if (format == null) return false
        if (engine.hasOutputFailed()) {
            throw AudioSink.WriteException(WRITE_ERROR, format, false)
        }

        // A previous block could not be enqueued because the deck ring was
        // full. The renderer is required to retry with the same buffer.
        if (pending.isNotEmpty()) {
            if (!drainPending()) return false
            if (retryBuffer === buffer && buffer.position() == retryPosition) {
                commitPendingTail()
                buffer.position(retryLimit)
                retryBuffer = null
                return true
            }
            commitPendingTail()
            retryBuffer = null
        }

        val position = buffer.position()
        val limit = buffer.limit()
        val remaining = limit - position
        if (remaining <= 0) return true

        val frameSize = pipeline.frameSizeBytes
        if (frameSize <= 0) return false

        val totalBytes = leftover.size + remaining
        ensureInputScratch(totalBytes)
        System.arraycopy(leftover, 0, inputScratch, 0, leftover.size)
        buffer.duplicate().get(inputScratch, leftover.size, remaining)

        val alignedBytes = (totalBytes / frameSize) * frameSize
        val tailLength = totalBytes - alignedBytes
        val tail = if (tailLength > 0) {
            inputScratch.copyOfRange(alignedBytes, totalBytes)
        } else {
            ByteArray(0)
        }

        if (alignedBytes == 0) {
            leftover = tail
            buffer.position(limit)
            return true
        }

        val blocks = pipeline.process(
            inputScratch,
            0,
            alignedBytes,
            presentationTimeUs,
        )
        for (block in blocks) {
            pending.addLast(
                PendingBlock(
                    pcm = block.pcm,
                    offsetFrames = 0,
                    frames = block.frames,
                    sourceStartUs = block.sourceStartUs,
                    sourceDurationUs = block.sourceDurationUs,
                ),
            )
        }

        if (pending.isEmpty() || drainPending()) {
            leftover = tail
            buffer.position(limit)
            return true
        }

        // Report backpressure without advancing the caller's buffer. The
        // processed output (and this buffer's incomplete frame tail) is kept
        // for the retry.
        retryBuffer = buffer
        retryPosition = position
        retryLimit = limit
        pendingTail = tail
        return false
    }

    override fun playToEndOfStream() {
        val format = configuredFormat ?: return
        val tail = try {
            pipeline.finish()
        } catch (error: Exception) {
            log("Deck $slot EOS drain failed: ${error.message}")
            emptyList()
        }
        for (block in tail) {
            pending.addLast(
                PendingBlock(
                    pcm = block.pcm,
                    offsetFrames = 0,
                    frames = block.frames,
                    sourceStartUs = block.sourceStartUs,
                    sourceDurationUs = block.sourceDurationUs,
                ),
            )
        }
        if (!drainPending(DRAIN_EOS_TIMEOUT_MS)) {
            log("Deck $slot EOS drain timed out; dropping ${pending.size} pending blocks")
            pending.clear()
        }
        engine.finishStream(slot, generation)
        log("Deck $slot EOS drained: generation=$generation format=${format.sampleRate}Hz")
    }

    override fun isEnded(): Boolean =
        configuredFormat != null && pending.isEmpty() && engine.deckIsEnded(slot)

    override fun hasPendingData(): Boolean =
        pending.isNotEmpty() || engine.deckHasPendingData(slot)

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long {
        val positionUs = engine.deckPositionUs(slot, sourceEnded)
        return if (positionUs < 0L) AudioSink.CURRENT_POSITION_NOT_SET else positionUs
    }

    override fun handleDiscontinuity() {
        // The next buffer's timestamp jumps; re-anchor the source timeline but
        // keep already-processed audio (a full processor flush here would cut
        // the tail at a gapless period boundary).
        pipeline.discontinuity()
        listener?.onPositionDiscontinuity()
    }

    // ── Transport / parameters ───────────────────────────────────────────────

    override fun setPlaybackParameters(playbackParameters: PlaybackParameters) {
        // Speed/pitch are applied per deck by Signalsmith inside the pipeline.
        // The shared bus itself never runs Sonic, so these are bookkeeping only.
        this.playbackParameters = playbackParameters
    }

    override fun getPlaybackParameters(): PlaybackParameters = playbackParameters

    override fun setSkipSilenceEnabled(skipSilenceEnabled: Boolean) {
        this.skipSilenceEnabled = skipSilenceEnabled
    }

    override fun getSkipSilenceEnabled(): Boolean = skipSilenceEnabled

    override fun setAudioAttributes(audioAttributes: AudioAttributes) {
        this.audioAttributes = audioAttributes
        engine.executeOnOutputThread { output.setAudioAttributes(audioAttributes) }
    }

    override fun getAudioAttributes(): AudioAttributes = audioAttributes

    override fun getAudioCapabilities(): AudioCapabilities? = output.audioCapabilities()

    override fun setAudioSessionId(audioSessionId: Int) {
        engine.executeOnOutputThread { output.setSessionId(audioSessionId) }
    }

    override fun setAuxEffectInfo(auxEffectInfo: AuxEffectInfo) {
        engine.executeOnOutputThread { output.setAuxEffectInfo(auxEffectInfo) }
    }

    override fun setPreferredDevice(audioDeviceInfo: AudioDeviceInfo?) {
        engine.executeOnOutputThread { output.setPreferredDevice(audioDeviceInfo) }
    }

    override fun getAudioTrackBufferSizeUs(): Long = output.bufferSizeUs()

    override fun enableTunnelingV21() {
        // Tunneling/passthrough cannot go through the software mix bus.
    }

    override fun disableTunneling() {
        // No-op: tunneling is never enabled on a deck.
    }

    override fun setVolume(volume: Float) {
        engine.setDeckVolume(slot, volume)
    }

    override fun flush() {
        clearPending()
        pipeline.flush()
        generation = engine.resetDeck(slot)
        // Cut the hardware buffer too, but only when this deck is alone; the
        // engine skips the flush if the other deck is still playing.
        engine.flushBusForSeek(slot)
    }

    override fun reset() {
        engine.setDeckPlaying(slot, false)
        clearPending()
        pipeline.reset()
        generation = engine.resetDeck(slot)
        engine.flushBusForSeek(slot)
        configuredFormat = null
    }

    override fun release() {
        engine.setDeckPlaying(slot, false)
        engine.removeBusListener(busListener)
        clearPending()
        pipeline.reset()
        engine.releaseDeck(slot)
        configuredFormat = null
        listener = null
    }

    // ── Pending-output plumbing ──────────────────────────────────────────────

    private fun drainPending(timeoutMs: Long = DRAIN_TIMEOUT_MS): Boolean {
        val deadline = System.nanoTime() + timeoutMs * 1_000_000L
        while (pending.isNotEmpty()) {
            val block = pending.peekFirst() ?: break
            if (block.isEmpty) {
                pending.pollFirst()
                continue
            }
            val accepted = engine.appendFrames(
                slot = slot,
                generation = generation,
                pcm = block.pcm,
                offsetFrames = block.offsetFrames,
                frames = block.frames,
                sourceStartUs = block.sourceStartUs,
                sourceDurationUs = block.sourceDurationUs,
            )
            if (accepted > 0) {
                block.advance(accepted)
                if (block.isEmpty) pending.pollFirst()
                continue
            }
            if (System.nanoTime() >= deadline) return false
            try {
                Thread.sleep(1L)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return false
            }
        }
        return true
    }

    private fun clearPending() {
        pending.clear()
        retryBuffer = null
        pendingTail = null
        leftover = ByteArray(0)
    }

    private fun commitPendingTail() {
        pendingTail?.let { leftover = it }
        pendingTail = null
    }

    private fun ensureInputScratch(size: Int) {
        if (inputScratch.size < size) {
            inputScratch = ByteArray(maxOf(size, 8 * 1024))
        }
    }

    companion object {
        private const val DRAIN_TIMEOUT_MS = 250L
        private const val DRAIN_EOS_TIMEOUT_MS = 2_000L
        private const val WRITE_ERROR = -1
    }
}
