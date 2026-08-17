package dev.wndavenz.music.replaygain

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteOrder

/**
 * Offline PCM decode loop (MediaExtractor + MediaCodec), decoupled from any
 * loudness math. This replaces the decode loop that used to live inline in
 * the old `ReplayGainScanner.scan()` — the K-weighting/gating math it used
 * to do in Kotlin has been removed; PCM is now streamed straight into a
 * libebur128-backed [EburTrackSession] via [feed].
 */
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
    fun decode(
        path: String,
        onFormat: (TrackFormat) -> Unit,
        feed: (buf: ShortArray, frameCount: Int) -> Boolean,
        onProgress: (Float) -> Unit,
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

        val info = MediaCodec.BufferInfo()
        var eos = false
        var aborted = false
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
                            val frameCount = remaining / channels
                            if (frameCount > 0 && !feed(chunk, frameCount)) {
                                aborted = true
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
