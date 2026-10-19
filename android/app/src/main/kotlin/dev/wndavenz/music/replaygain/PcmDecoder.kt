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

object PcmDecoder {

    /** Format info needed to size an [EburTrackSession] before decoding starts. */
    data class TrackFormat(val sampleRate: Int, val channels: Int, val durationUs: Long)

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
    ): Boolean {
        val file = File(path)
        if (!file.exists()) return false

        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
        } catch (_: Exception) {
            extractor.release()
            return false
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
            extractor.release()
            return false
        }

        val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
        // A permanent ReplayGain result must never be based on guessed format
        // metadata: a wrong sample rate changes K-weighting and a wrong channel
        // count changes the interleaved PCM frame interpretation.
        val sampleRate = runCatching {
            format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        }.getOrNull()?.takeIf { it in 8_000..384_000 } ?: run {
            extractor.release()
            return false
        }
        val channels = runCatching {
            format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        }.getOrNull()?.takeIf { it in 1..8 } ?: run {
            extractor.release()
            return false
        }
        val durationUs = runCatching { format.getLong(MediaFormat.KEY_DURATION) }.getOrDefault(-1L)
        onFormat(TrackFormat(sampleRate, channels, durationUs))

        extractor.selectTrack(trackIndex)

        val codec = try {
            MediaCodec.createDecoderByType(mime).also {
                it.configure(format, null, null, 0)
                it.start()
            }
        } catch (_: Exception) {
            extractor.release()
            return false
        }

        if (startUs > 0L) {
            // SEEK_TO_PREVIOUS_SYNC lands on a decoder-sync point; the window
            // start reported back to Dart is the request, and the few frames of
            // lead-in only help the extractor ramp up cleanly.
            try {
                extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            } catch (_: Exception) {
                // Keep decoding from the beginning rather than failing the scan.
            }
        }

        val info = MediaCodec.BufferInfo()
        var eos = false
        var aborted = false
        var pendingTrimBeforeUs = trimBeforeUs
        // N-3: reuse one grow-only ShortArray for all output buffers instead
        // of allocating a fresh one per chunk. MediaCodec output-buffer sizes
        // are essentially constant for a given track/codec, so after the
        // first chunk this allocates nothing for the rest of the decode.
        var chunk = ShortArray(0)

        try {
            while (!eos && !aborted) {
                val inIdx = codec.dequeueInputBuffer(8_000L)
                if (inIdx >= 0) {
                    val inBuf = codec.getInputBuffer(inIdx)
                    if (inBuf != null) {
                        val n = extractor.readSampleData(inBuf, 0)
                        if (n <= 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            eos = true
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
                }
                if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
            }
        } finally {
            runCatching { codec.stop() }
            runCatching { codec.release() }
            runCatching { extractor.release() }
        }

        onProgress(1.0f)
        return !aborted
    }
}
