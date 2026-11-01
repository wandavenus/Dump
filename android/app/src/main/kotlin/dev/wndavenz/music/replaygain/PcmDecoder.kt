package dev.wndavenz.music.replaygain

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteOrder
import kotlin.math.ceil

/**
 * Offline PCM decode loop (MediaExtractor + MediaCodec), decoupled from any
 * loudness math. This replaces the decode loop that used to live inline in
 * the old `ReplayGainScanner.scan()` — the K-weighting/gating math it used
 * to do in Kotlin has been removed; PCM is now streamed straight into a
 * libebur128-backed [EburTrackSession] via [feed].
 */
/**
 * Number of interleaved PCM frames that precede a requested media timestamp.
 * The result is clamped to the current decoded buffer; callers keep trimming
 * subsequent buffers until the requested timestamp is reached.
 */
internal fun pcmFramesToTrim(
    targetUs: Long,
    bufferStartUs: Long,
    sampleRate: Int,
    frameCount: Int,
): Int {
    if (sampleRate <= 0 || frameCount <= 0 || targetUs <= bufferStartUs) return 0
    val deltaUs = targetUs.toDouble() - bufferStartUs.toDouble()
    val frames = ceil(deltaUs * sampleRate / 1_000_000.0)
    if (!frames.isFinite() || frames >= frameCount.toDouble()) return frameCount
    return frames.toInt().coerceAtLeast(0)
}

/**
 * Tracks decoder input/output EOS independently. Queueing an EOS input buffer
 * only tells MediaCodec that no more compressed input is coming; delayed PCM
 * output may still need to be drained before the decode is complete.
 */
internal class PcmDecodeEosState {
    var inputEosQueued: Boolean = false
        private set

    var outputEosSeen: Boolean = false
        private set

    val isComplete: Boolean
        get() = outputEosSeen

    fun markInputEosQueued() {
        inputEosQueued = true
    }

    fun observeOutputFlags(flags: Int) {
        if ((flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
            outputEosSeen = true
        }
    }
}

/** Releases a codec created successfully if setup fails before decode ownership begins. */
internal fun <T : Any> createAndStartCodecOrReleaseOnFailure(
    create: () -> T,
    configure: (T) -> Unit,
    start: (T) -> Unit,
    release: (T) -> Unit,
): T? {
    var createdCodec: T? = null
    return try {
        val codec = create()
        createdCodec = codec
        configure(codec)
        start(codec)
        codec
    } catch (_: Exception) {
        createdCodec?.let { runCatching { release(it) } }
        null
    }
}

/** Keeps decoder-owned native resources released on returns and exceptions. */
internal inline fun <T : Any, R> withPcmResource(
    resource: T,
    release: (T) -> Unit,
    block: (T) -> R,
): R {
    try {
        return block(resource)
    } finally {
        runCatching { release(resource) }
    }
}

object PcmDecoder {

    /** Format info needed to size an [EburTrackSession] before decoding starts. */
    data class TrackFormat(
        val sampleRate: Int,
        val channels: Int,
        val durationUs: Long,
        /** Android channel mask, 0 when the container does not declare one. */
        val channelMask: Int = 0,
    )

    /**
     * Decodes [path] and calls [feed] with each chunk of interleaved 16-bit
     * PCM (frameCount = samples-per-channel in [buf]) as it becomes
     * available. [onProgress] receives 0f..1f. Returns false if the file
     * could not be opened/decoded at all (no audio track, codec creation
     * failure, etc.) — [feed] is never called in that case.
     *
     * [feed] must return true to continue decoding, or false to abort early
     * (e.g. libebur128 reported an internal error).
     */
    /**
     * [startUs] seeks the extractor before decoding, so a caller that only
     * needs one window of a long file (AutoMix samples head/middle/tail)
     * decodes just that window. Default 0 keeps every existing caller's
     * behaviour (decode from the beginning) unchanged.
     */
    fun decode(
        path: String,
        onFormat: (TrackFormat) -> Unit,
        feed: (buf: ShortArray, frameCount: Int) -> Boolean,
        onProgress: (Float) -> Unit,
        startUs: Long = 0L,
        trimBeforeUs: Long? = null,
        /** Invoked once when the extractor/codec reaches End-Of-Stream. */
        onEos: (() -> Unit)? = null,
    ): Boolean {
        val file = File(path)
        if (!file.exists()) return false

        val extractor = MediaExtractor()
        return withPcmResource(
            resource = extractor,
            release = { it.release() },
        ) { extractor ->
            try {
                extractor.setDataSource(path)
            } catch (_: Exception) {
                return@withPcmResource false
            }

            var trackIndex = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    trackIndex = i
                    format = f
                    break
                }
            }
            if (trackIndex < 0 || format == null) {
                return@withPcmResource false
            }

            val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
            // A permanent ReplayGain result must never be based on guessed format
            // metadata: a wrong sample rate changes K-weighting and a wrong channel
            // count changes the interleaved PCM frame interpretation.
            val sampleRate = runCatching {
                format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            }.getOrNull()?.takeIf { it in 8_000..384_000 } ?: run {
                return@withPcmResource false
            }
            val channels = runCatching {
                format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            }.getOrNull()?.takeIf { it in 1..8 } ?: run {
                return@withPcmResource false
            }
            val durationUs = runCatching {
                format.getLong(MediaFormat.KEY_DURATION)
            }.getOrDefault(-1L)
            val channelMask = runCatching {
                format.getInteger(MediaFormat.KEY_CHANNEL_MASK)
            }.getOrDefault(0)
            onFormat(TrackFormat(sampleRate, channels, durationUs, channelMask))

            extractor.selectTrack(trackIndex)

            val codec = createAndStartCodecOrReleaseOnFailure(
                create = { MediaCodec.createDecoderByType(mime) },
                configure = { it.configure(format, null, null, 0) },
                start = { it.start() },
                release = { it.release() },
            ) ?: return@withPcmResource false

            if (startUs > 0L) {
                // SEEK_TO_PREVIOUS_SYNC lands on a decoder-sync point; the window
                // start reported back to Dart is the request, and the few frames of
                // lead-in only help the extractor ramp up cleanly.
                try {
                    extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                } catch (_: Exception) {
                    // A bounded AutoMix window must not silently fall back to
                    // decoding from 0: trimming toward a late tail would otherwise
                    // force a whole-file decode and could attach incorrect timing.
                    if (trimBeforeUs != null) {
                        runCatching { codec.stop() }
                        runCatching { codec.release() }
                        return@withPcmResource false
                    }
                    // Legacy whole-file scans can still proceed from the beginning.
                }
            }

            val info = MediaCodec.BufferInfo()
            val eosState = PcmDecodeEosState()
            var aborted = false
            var pendingTrimBeforeUs = trimBeforeUs
            // N-3: reuse one grow-only ShortArray for all output buffers instead
            // of allocating a fresh one per chunk. MediaCodec output-buffer sizes
            // are essentially constant for a given track/codec, so after the
            // first chunk this allocates nothing for the rest of the decode.
            var chunk = ShortArray(0)

            try {
                while (!eosState.isComplete && !aborted) {
                    if (!eosState.inputEosQueued) {
                        val inIdx = codec.dequeueInputBuffer(8_000L)
                        if (inIdx >= 0) {
                            val inBuf = codec.getInputBuffer(inIdx)
                            if (inBuf != null) {
                                val n = extractor.readSampleData(inBuf, 0)
                                if (n <= 0) {
                                    codec.queueInputBuffer(
                                        inIdx,
                                        0,
                                        0,
                                        0,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                    )
                                    eosState.markInputEosQueued()
                                } else {
                                    val ts = extractor.sampleTime
                                    codec.queueInputBuffer(inIdx, 0, n, ts, 0)
                                    extractor.advance()
                                    if (durationUs > 0L) {
                                        onProgress((ts.toFloat() / durationUs).coerceIn(0f, 0.99f))
                                    }
                                }
                            }
                        }
                    }

                    val outIdx = codec.dequeueOutputBuffer(info, 8_000L)
                    if (outIdx >= 0) {
                        val outBuf = codec.getOutputBuffer(outIdx)
                        if (outBuf != null && info.size > 0) {
                            outBuf.position(info.offset)
                            outBuf.limit(info.offset + info.size)
                            outBuf.order(ByteOrder.LITTLE_ENDIAN)
                            val sb = outBuf.asShortBuffer()

                            val remaining = sb.remaining()
                            if (remaining > 0) {
                                if (chunk.size < remaining) chunk = ShortArray(remaining)
                                sb.get(chunk, 0, remaining)
                                var frameCount = remaining / channels
                                if (frameCount > 0) {
                                    val trimTargetUs = pendingTrimBeforeUs
                                    if (trimTargetUs != null) {
                                        val framesToTrim = pcmFramesToTrim(
                                            targetUs = trimTargetUs,
                                            bufferStartUs = info.presentationTimeUs,
                                            sampleRate = sampleRate,
                                            frameCount = frameCount,
                                        )
                                        if (framesToTrim >= frameCount) {
                                            val bufferEndUs = info.presentationTimeUs +
                                                frameCount.toLong() * 1_000_000L / sampleRate
                                            // A whole buffer before the requested timestamp
                                            // is discarded. Keep trimming until a decoded
                                            // sample at/after the target is reached.
                                            if (bufferEndUs > trimTargetUs) {
                                                pendingTrimBeforeUs = null
                                            }
                                            frameCount = 0
                                        } else if (framesToTrim > 0) {
                                            val keptFrames = frameCount - framesToTrim
                                            System.arraycopy(
                                                chunk,
                                                framesToTrim * channels,
                                                chunk,
                                                0,
                                                keptFrames * channels,
                                            )
                                            frameCount = keptFrames
                                            pendingTrimBeforeUs = null
                                        } else {
                                            // The decoder has reached or passed the target.
                                            pendingTrimBeforeUs = null
                                        }
                                    }
                                    if (frameCount > 0 && !feed(chunk, frameCount)) {
                                        aborted = true
                                    }
                                }
                            }
                        }
                        codec.releaseOutputBuffer(outIdx, false)
                        eosState.observeOutputFlags(info.flags)
                        if (eosState.outputEosSeen) {
                            break
                        }
                    }
                }
            } finally {
                runCatching { codec.stop() }
                runCatching { codec.release() }
            }

            if (eosState.outputEosSeen) {
                runCatching { onEos?.invoke() }
            }
            onProgress(1.0f)
            !aborted
        }
    }
}
