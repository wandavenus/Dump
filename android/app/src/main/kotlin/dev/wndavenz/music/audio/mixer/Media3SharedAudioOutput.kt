package dev.wndavenz.music.audio.mixer

import android.content.Context
import android.media.AudioDeviceInfo
import androidx.media3.common.AudioAttributes
import androidx.media3.common.AuxEffectInfo
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink.DefaultAudioProcessorChain
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Media3 implementation of the engine's single shared output.
 *
 * This is the **only** object in the new path that creates an `AudioTrack`.
 * It is configured once at 48 kHz stereo float; Media3's own internal chain
 * performs the final float→PCM16 conversion (float output is disabled, matching
 * the legacy sink's precision policy) and hands the samples to one AudioTrack.
 *
 * All stateful methods are expected to be called from the engine's output
 * thread. The deck-facing helpers at the bottom of this class are also routed
 * through [SingleAudioTrackEngine.executeOnOutputThread].
 */
@UnstableApi
class Media3SharedAudioOutput(
    context: Context,
    private val lifecycleLog: (String) -> Unit = {},
) : SharedAudioOutput {

    private val lifecycleOwnerLabel =
        "shared-output@\${Integer.toHexString(System.identityHashCode(this))}"

    private val sink: DefaultAudioSink = DefaultAudioSink.Builder(context)
        // The bus is float; let the sink do the final PCM16 conversion.
        .setEnableFloatOutput(false)
        // Playback speed/pitch are handled by Signalsmith inside each deck.
        .setEnableAudioOutputPlaybackParameters(false)
        .setAudioProcessorChain(DefaultAudioProcessorChain())
        .build()

    override var listener: SharedAudioOutput.Listener? = null

    private var scratch: ByteBuffer? = null
    private var configured = false
    private var released = false
    private var sessionId = 0
    private var attributes: AudioAttributes = AudioAttributes.DEFAULT
    private var auxEffectInfo: AuxEffectInfo? = null
    private var preferredDevice: AudioDeviceInfo? = null

    init {
        sink.setListener(object : AudioSink.Listener {
            override fun onPositionDiscontinuity() {
                listener?.onPositionDiscontinuity()
            }

            override fun onUnderrun(
                bufferSize: Int,
                bufferSizeMs: Long,
                elapsedSinceLastFeedMs: Long,
            ) {
                listener?.onUnderrun(bufferSize, bufferSizeMs, elapsedSinceLastFeedMs)
            }

            override fun onSkipSilenceEnabledChanged(skipSilenceEnabled: Boolean) {
                // The bus never enables silence skipping.
            }

            override fun onAudioSessionIdChanged(audioSessionId: Int) {
                sessionId = audioSessionId
                listener?.onAudioSessionIdChanged(audioSessionId)
            }

            override fun onAudioTrackInitialized(audioTrackConfig: AudioSink.AudioTrackConfig) {
                lifecycleLog(
                    AudioTrackLifecycleRegistry.onInitialized(
                        owner = this@Media3SharedAudioOutput,
                        ownerLabel = lifecycleOwnerLabel,
                        encoding = audioTrackConfig.encoding,
                        sampleRate = audioTrackConfig.sampleRate,
                        channelConfig = audioTrackConfig.channelConfig,
                        bufferSize = audioTrackConfig.bufferSize,
                    ),
                )
                listener?.onAudioTrackInitialized(
                    audioTrackConfig.encoding,
                    audioTrackConfig.sampleRate,
                    audioTrackConfig.channelConfig,
                    audioTrackConfig.bufferSize,
                )
            }

            override fun onAudioTrackReleased(audioTrackConfig: AudioSink.AudioTrackConfig) {
                lifecycleLog(
                    AudioTrackLifecycleRegistry.onReleased(
                        owner = this@Media3SharedAudioOutput,
                        ownerLabel = lifecycleOwnerLabel,
                    ),
                )
                listener?.onAudioTrackReleased(
                    audioTrackConfig.encoding,
                    audioTrackConfig.sampleRate,
                    audioTrackConfig.channelConfig,
                )
            }

            override fun onAudioSinkError(audioSinkError: Exception) {
                // Media3 may recover from these; report but do not fail the bus.
                listener?.onSinkError(
                    "${audioSinkError.javaClass.simpleName}: ${audioSinkError.message}",
                )
            }
        })
    }

    override fun configure(sampleRate: Int, channelCount: Int): Boolean {
        if (released) return false
        return try {
            val format = Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_FLOAT)
                .setSampleRate(sampleRate)
                .setChannelCount(channelCount)
                .build()
            // Attributes must be in place before the AudioTrack is created;
            // setting them after configure() would force a redundant flush.
            sink.setAudioAttributes(attributes)
            sink.configure(AudioSink.AudioSinkConfig.Builder(format).build())
            if (sessionId > 0) sink.setAudioSessionId(sessionId)
            auxEffectInfo?.let { sink.setAuxEffectInfo(it) }
            preferredDevice?.let { sink.setPreferredDevice(it) }
            configured = true
            true
        } catch (error: Exception) {
            listener?.onError(
                "bus configure failed: ${error.javaClass.simpleName}: ${error.message}",
            )
            configured = false
            false
        }
    }

    override fun isConfigured(): Boolean = configured

    override fun play() {
        if (!released && configured) sink.play()
    }

    override fun pause() {
        if (!released) sink.pause()
    }

    override fun handleBuffer(
        pcm: FloatArray,
        frameCount: Int,
        presentationTimeUs: Long,
    ): Boolean {
        if (released || !configured || frameCount <= 0) return false
        val byteCount = frameCount * PcmRingBuffer.CHANNELS * Float.SIZE_BYTES
        var buffer = scratch
        if (buffer == null || buffer.capacity() < byteCount) {
            buffer = ByteBuffer.allocateDirect(maxOf(byteCount, 64 * 1024))
                .order(ByteOrder.nativeOrder())
            scratch = buffer
        }
        buffer.clear()
        buffer.order(ByteOrder.nativeOrder())
        buffer.asFloatBuffer().put(pcm, 0, frameCount * PcmRingBuffer.CHANNELS)
        buffer.position(0)
        buffer.limit(byteCount)

        return try {
            // DefaultAudioSink may accept only part of the block while its
            // AudioTrack buffer is full; the sink requires the same buffer to
            // be offered again until the remainder is accepted.
            var guard = 0
            while (buffer.hasRemaining()) {
                val accepted = sink.handleBuffer(buffer, presentationTimeUs, 1)
                if (accepted) {
                    if (buffer.hasRemaining()) {
                        listener?.onError(
                            "DefaultAudioSink accepted a block with ${buffer.remaining()} bytes unconsumed",
                        )
                        return false
                    }
                    break
                }
                Thread.sleep(1L)
                guard++
                if (guard > HANDLE_BUFFER_RETRY_LIMIT) {
                    listener?.onError("bus handleBuffer stalled after $guard retries")
                    return false
                }
            }
            !buffer.hasRemaining()
        } catch (error: Exception) {
            listener?.onError(
                "bus write failed: ${error.javaClass.simpleName}: ${error.message}",
            )
            false
        }
    }

    override fun currentPositionUs(): Long {
        if (released || !configured) return -1L
        return try {
            sink.getCurrentPositionUs(false)
        } catch (_: Exception) {
            -1L
        }
    }

    override fun hasPendingData(): Boolean {
        if (released || !configured) return false
        return try {
            sink.hasPendingData()
        } catch (_: Exception) {
            false
        }
    }

    override fun bufferSizeUs(): Long {
        if (released || !configured) return 0L
        return try {
            sink.audioTrackBufferSizeUs
        } catch (_: Exception) {
            0L
        }
    }

    override fun audioSessionId(): Int = sessionId

    override fun flush() {
        if (!released) sink.flush()
    }

    override fun reset() {
        if (released) return
        try {
            // Release the current AudioTrack but keep the sink reusable when
            // normal dual-player playback resumes after an exclusive mode.
            sink.reset()
        } finally {
            configured = false
            scratch = null
            sessionId = 0
        }
    }

    override fun release() {
        if (released) return
        released = true
        configured = false
        scratch = null
        try {
            sink.release()
        } catch (_: Exception) {
            // Sink already released by a duplicate teardown path.
        }
    }

    // ── Media3-only controls, always invoked on the engine output thread ─────

    fun setAudioAttributes(audioAttributes: AudioAttributes) {
        if (released) return
        attributes = audioAttributes
        if (configured) sink.setAudioAttributes(audioAttributes)
    }

    fun setSessionId(id: Int) {
        if (released || id <= 0 || id == sessionId) return
        sessionId = id
        if (configured) {
            try {
                sink.setAudioSessionId(id)
            } catch (_: Exception) {
                // AudioTrack not initialised yet; configure() applies it later.
            }
        }
    }

    fun setAuxEffectInfo(info: AuxEffectInfo) {
        if (released) return
        auxEffectInfo = info
        if (configured) sink.setAuxEffectInfo(info)
    }

    fun setPreferredDevice(device: AudioDeviceInfo?) {
        if (released) return
        preferredDevice = device
        if (configured) sink.setPreferredDevice(device)
    }

    fun audioCapabilities(): AudioCapabilities? = sink.audioCapabilities

    companion object {
        private const val HANDLE_BUFFER_RETRY_LIMIT = 2_000
    }
}
