package dev.wndavenz.music.audio.mixer

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.AudioProcessingPipeline
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import com.google.common.collect.ImmutableList
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * One block of post-DSP audio for a deck, tagged with the source-media span it
 * represents.
 *
 * [pcm] is interleaved stereo float at [SingleAudioTrackEngine.BUS_SAMPLE_RATE].
 */
class PcmBlock(
    val pcm: FloatArray,
    val frames: Int,
    val sourceStartUs: Long,
    val sourceDurationUs: Long,
)

/**
 * Per-deck processor pipeline.
 *
 * The legacy path injected the custom processors into `DefaultAudioSink`'s
 * chain, which meant each ExoPlayer wrote straight to its own AudioTrack. Here
 * the same processors (float conversion, native DSP, stereo width, reverb,
 * Signalsmith Stretch, AutoMix tone/limiter) run in a standalone
 * [AudioProcessingPipeline] owned by the deck. Its float output is normalised
 * to stereo, resampled to the shared bus rate, and handed to the engine with
 * the exact source timeline it came from.
 *
 * The final float→PCM16 conversion intentionally does **not** happen here: the
 * shared output sink performs it after summing, which preserves headroom and
 * avoids clipping each deck twice.
 */
@UnstableApi
class DeckAudioPipeline(
    processors: List<AudioProcessor>,
    private val busSampleRate: Int = SingleAudioTrackEngine.BUS_SAMPLE_RATE,
    private val log: (String) -> Unit = {},
) {

    private val pipeline = AudioProcessingPipeline(ImmutableList.copyOf(processors))

    private var inputSampleRate = 0
    private var inputChannelCount = 0
    private var inputFrameSize = 0
    private var inputSampleFormat: PcmSampleFormat = PcmSampleFormat.SIGNED_16
    private var inputBigEndian = false

    private var outputChannelCount = 0
    private var outputFrameSize = 0
    private var outputSampleFormat: PcmSampleFormat = PcmSampleFormat.FLOAT_32
    private var outputBigEndian = false

    private var resampler: SincResampler? = null
    private var directInputBuffer: ByteBuffer =
        ByteBuffer.allocateDirect(0).order(ByteOrder.nativeOrder())
    private var operational = false
    private var configured = false

    /**
     * C++/NEON converter for the sample-domain path. Zero means the native
     * library is unavailable (or rejected this configuration) and the Kotlin
     * reference converter below is used instead.
     */
    private var nativeConverter = 0L
    private var nativeChannels = 0
    private var nativeSampleFormat: PcmSampleFormat = PcmSampleFormat.SIGNED_16
    private var nativeBigEndian = false

    /**
     * Reused native output staging area. Each returned chunk is still copied to
     * a right-sized array because it may stay queued for backpressure/EOS, but
     * the staging buffer itself never allocates after warm-up.
     */
    private var nativeOutputScratch = FloatArray(0)

    /** Source µs buffered in the filter that has not produced output yet. */
    private var carriedSourceUs = 0L

    /** End of the most recently supplied source span, in µs. */
    private var lastSourceEndUs = 0L

    val inputFramesPerSecond: Int get() = inputSampleRate
    val frameSizeBytes: Int get() = inputFrameSize

    /**
     * Configures the deck for [format] (always linear PCM; see
     * `DeckAudioSink.supportsFormat`).
     */
    fun configure(format: Format) {
        releaseNativeConverter()
        // If configuration fails part-way through, the previous native handle
        // is already gone; mark the pipeline unusable rather than leaving a
        // stale `configured` flag that would call into a mismatched pipeline.
        configured = false
        val encoding = format.pcmEncoding
        val mapped = mapEncoding(encoding)
            ?: throw IllegalArgumentException(
                "Unsupported PCM encoding 0x${encoding.toString(16)}",
            )

        inputSampleRate = format.sampleRate
        inputChannelCount = format.channelCount
        inputFrameSize = Util.getPcmFrameSize(encoding, inputChannelCount)
        inputSampleFormat = mapped.first
        inputBigEndian = mapped.second
        require(inputSampleRate > 0 && inputChannelCount > 0 && inputFrameSize > 0) {
            "Invalid PCM format: ${format.sampleRate}Hz/${format.channelCount}ch"
        }

        val audioFormat = AudioProcessor.AudioFormat(format)
        val processed = try {
            pipeline.configure(audioFormat)
            pipeline.flush(AudioProcessor.StreamMetadata.DEFAULT)
            pipeline
        } catch (error: AudioProcessor.UnhandledAudioFormatException) {
            throw IllegalArgumentException("Deck pipeline rejected $audioFormat", error)
        }

        operational = processed.isOperational
        if (operational) {
            val output = processed.outputAudioFormat
            outputChannelCount = output.channelCount
            outputFrameSize = output.bytesPerFrame
            val outputMapping = mapEncoding(output.encoding)
                ?: throw IllegalArgumentException(
                    "Deck pipeline produced unsupported encoding 0x${output.encoding.toString(16)}",
                )
            outputSampleFormat = outputMapping.first
            outputBigEndian = outputMapping.second
        } else {
            outputChannelCount = inputChannelCount
            outputFrameSize = inputFrameSize
            outputSampleFormat = inputSampleFormat
            outputBigEndian = inputBigEndian
        }

        val processingSampleRate = if (operational) {
            pipeline.outputAudioFormat.sampleRate
        } else {
            inputSampleRate
        }
        resampler = SincResampler(processingSampleRate, busSampleRate)
        if (operational) {
            nativeConverter = NativePcmBridge.createDeckConverter(
                inputRate = processingSampleRate,
                outputRate = busSampleRate,
            )
            nativeChannels = outputChannelCount
            nativeSampleFormat = outputSampleFormat
            nativeBigEndian = outputBigEndian
        } else {
            nativeConverter = NativePcmBridge.createDeckConverter(
                inputRate = inputSampleRate,
                outputRate = busSampleRate,
            )
            nativeChannels = inputChannelCount
            nativeSampleFormat = inputSampleFormat
            nativeBigEndian = inputBigEndian
        }
        carriedSourceUs = 0L
        lastSourceEndUs = 0L
        configured = true

        log(
            "Deck pipeline configured: in=${inputSampleRate}Hz/${inputChannelCount}ch " +
                "fmt=$inputSampleFormat bus=${busSampleRate}Hz operational=$operational " +
                "native=${nativeConverter != 0L}",
        )
    }

    /**
     * Queues one decoder buffer and returns every bus block it produced.
     *
     * [bytes] is the frame-aligned payload; [presentationTimeUs] is the
     * buffer's media timestamp. A processor that buffers latency may return no
     * output for this call; its source span is carried into the next block so
     * the timeline stays contiguous.
     */
    fun process(
        bytes: ByteArray,
        offsetBytes: Int,
        byteCount: Int,
        presentationTimeUs: Long,
    ): List<PcmBlock> {
        check(configured) { "pipeline not configured" }
        val frameCount = byteCount / inputFrameSize
        if (frameCount <= 0) return emptyList()

        val mediaDurationUs = frameCount * 1_000_000L / inputSampleRate
        lastSourceEndUs = presentationTimeUs + mediaDurationUs

        val chunks = ArrayList<FloatArray>(2)
        if (operational) {
            val inputBytes = frameCount * inputFrameSize
            if (directInputBuffer.capacity() < inputBytes) {
                directInputBuffer = ByteBuffer.allocateDirect(maxOf(inputBytes, 8 * 1024))
                    .order(ByteOrder.nativeOrder())
            }
            directInputBuffer.clear()
            directInputBuffer.put(bytes, offsetBytes, inputBytes)
            directInputBuffer.flip()
            // JNI-backed processors such as Signalsmith Stretch require direct
            // buffers for GetDirectBufferAddress(). ByteBuffer.wrap(ByteArray)
            // is heap-backed and can silently force the processor into bypass.
            pipeline.queueInput(directInputBuffer)
            drainOutput(chunks)
        } else {
            val native = convertNative(
                source = null,
                sourceBytes = bytes,
                sourceOffsetBytes = offsetBytes,
                inputFrames = frameCount,
                channels = inputChannelCount,
                format = inputSampleFormat,
                bigEndian = inputBigEndian,
            )
            if (native != null) {
                chunks.add(native)
            } else {
                val floats = PcmConversions.readFloats(
                    bytes,
                    offsetBytes,
                    frameCount,
                    inputChannelCount,
                    inputSampleFormat,
                    inputBigEndian,
                )
                val stereo = PcmConversions.toStereo(floats, frameCount, inputChannelCount)
                chunks.add(resampleToBus(stereo))
            }
        }

        return buildBlocks(chunks, presentationTimeUs, mediaDurationUs)
    }

    /**
     * Drains the processor tail after EOS. Must be called exactly once per
     * stream, after the last [process].
     */
    fun finish(): List<PcmBlock> {
        if (!configured || !operational) return emptyList()
        val chunks = ArrayList<FloatArray>(2)
        pipeline.queueEndOfStream()
        var guard = 0
        // A processor may need several getOutput() calls to release its tail,
        // so keep pumping until the pipeline reports EOS (bounded for safety).
        while (!pipeline.isEnded() && guard++ < MAX_FINISH_ITERATIONS) {
            drainOutput(chunks)
        }
        val tailStartUs = (lastSourceEndUs - carriedSourceUs).coerceAtLeast(0L)
        return buildBlocks(chunks, tailStartUs, carriedSourceUs)
    }

    /**
     * Re-anchors the source timeline without discarding decoded/processed
     * audio. Called for `AudioSink.handleDiscontinuity()` (seek / period
     * boundary), where the next buffer's timestamp jumps.
     */
    fun discontinuity() {
        carriedSourceUs = 0L
        lastSourceEndUs = 0L
    }

    fun flush() {
        if (!configured) return
        try {
            pipeline.flush(AudioProcessor.StreamMetadata.DEFAULT)
        } catch (_: Exception) {
            // A processor that was never configured can throw here; the next
            // configure() rebuilds the pipeline anyway.
        }
        resampler?.reset()
        NativePcmBridge.resetDeckConverter(nativeConverter)
        carriedSourceUs = 0L
        lastSourceEndUs = 0L
    }

    fun reset() {
        try {
            pipeline.reset()
        } catch (_: Exception) {
            // Already reset / never configured.
        }
        resampler?.reset()
        releaseNativeConverter()
        carriedSourceUs = 0L
        lastSourceEndUs = 0L
        operational = false
        configured = false
    }

    private fun drainOutput(chunks: MutableList<FloatArray>) {
        var guard = 0
        while (guard++ < MAX_DRAIN_ITERATIONS) {
            val output = pipeline.getOutput()
            if (!output.hasRemaining()) return
            val frames = output.remaining() / outputFrameSize
            if (frames <= 0) {
                output.position(output.limit())
                return
            }
            val native = convertNative(
                source = output,
                sourceBytes = null,
                sourceOffsetBytes = output.position(),
                inputFrames = frames,
                channels = outputChannelCount,
                format = outputSampleFormat,
                bigEndian = outputBigEndian,
            )
            if (native != null) {
                // The pipeline requires callers to consume the buffer before
                // it can produce more.
                output.position(output.limit())
                chunks.add(native)
                continue
            }
            val floats = PcmConversions.readFloats(
                output,
                0,
                frames,
                outputChannelCount,
                outputSampleFormat,
                outputBigEndian,
            )
            output.position(output.limit())
            val stereo = PcmConversions.toStereo(floats, frames, outputChannelCount)
            chunks.add(resampleToBus(stereo))
        }
    }

    private fun resampleToBus(stereo: FloatArray): FloatArray {
        val resampler = resampler ?: return stereo
        val inputFrames = stereo.size / PcmRingBuffer.CHANNELS
        if (resampler.isBypass) return stereo
        val upper = resampler.outputFramesUpperBound(inputFrames)
        val out = FloatArray(upper * PcmRingBuffer.CHANNELS)
        val produced = resampler.resample(stereo, inputFrames, out)
        return if (produced * PcmRingBuffer.CHANNELS == out.size) {
            out
        } else {
            out.copyOf(produced * PcmRingBuffer.CHANNELS)
        }
    }

    /**
     * Runs the C++/NEON converter when it is available and configured for the
     * exact format currently being drained. Returns null on any mismatch or
     * native failure so the caller can use the Kotlin reference path.
     */
    private fun convertNative(
        source: ByteBuffer?,
        sourceBytes: ByteArray?,
        sourceOffsetBytes: Int,
        inputFrames: Int,
        channels: Int,
        format: PcmSampleFormat,
        bigEndian: Boolean,
    ): FloatArray? {
        val converter = nativeConverter
        if (converter == 0L || inputFrames <= 0) return null
        if (channels !in 1..MAX_NATIVE_CHANNELS) return null
        if (channels != nativeChannels ||
            format != nativeSampleFormat ||
            bigEndian != nativeBigEndian
        ) {
            return null
        }

        val upperBound = NativePcmBridge.deckOutputFramesUpperBound(converter, inputFrames)
        if (upperBound <= 0 || upperBound > Int.MAX_VALUE / PcmRingBuffer.CHANNELS) {
            return null
        }
        val outputFloats = upperBound * PcmRingBuffer.CHANNELS
        if (nativeOutputScratch.size < outputFloats) {
            nativeOutputScratch = FloatArray(outputFloats)
        }
        val output = nativeOutputScratch

        val directSource: ByteBuffer
        val directOffset: Int
        if (source != null && source.isDirect) {
            directSource = source
            directOffset = sourceOffsetBytes
        } else {
            val sampleBytes = format.bytesPerSample.toLong() * channels
            val byteCountLong = inputFrames.toLong() * sampleBytes
            if (sourceBytes == null ||
                sourceOffsetBytes < 0 ||
                sampleBytes <= 0L ||
                byteCountLong <= 0L ||
                byteCountLong > Int.MAX_VALUE
            ) {
                return null
            }
            val byteCount = byteCountLong.toInt()
            if (sourceOffsetBytes.toLong() + byteCount > sourceBytes.size) return null
            val buffer = ensureDirectInputBuffer(byteCount)
            buffer.clear()
            buffer.put(sourceBytes, sourceOffsetBytes, byteCount)
            buffer.flip()
            directSource = buffer
            directOffset = 0
        }

        val produced = NativePcmBridge.processDeck(
            handle = converter,
            input = directSource,
            offsetBytes = directOffset,
            inputFrames = inputFrames,
            channels = channels,
            format = format,
            bigEndian = bigEndian,
            output = output,
        )
        if (produced < 0 || produced > upperBound) {
            log("Native PCM converter disabled after status=$produced")
            releaseNativeConverter()
            return null
        }
        if (produced == 0) return FloatArray(0)
        // The output can stay queued on ring backpressure, so it must not alias
        // the next block's staging buffer.
        return output.copyOf(produced * PcmRingBuffer.CHANNELS)
    }

    private fun ensureDirectInputBuffer(bytes: Int): ByteBuffer {
        if (directInputBuffer.capacity() < bytes) {
            directInputBuffer = ByteBuffer.allocateDirect(maxOf(bytes, 8 * 1024))
                .order(ByteOrder.nativeOrder())
        }
        directInputBuffer.order(ByteOrder.nativeOrder())
        return directInputBuffer
    }

    private fun releaseNativeConverter() {
        val converter = nativeConverter
        nativeConverter = 0L
        nativeChannels = 0
        if (converter != 0L) NativePcmBridge.destroyDeckConverter(converter)
    }

    private fun buildBlocks(
        chunks: List<FloatArray>,
        presentationTimeUs: Long,
        mediaDurationUs: Long,
    ): List<PcmBlock> {
        var totalFrames = 0
        for (chunk in chunks) totalFrames += chunk.size / PcmRingBuffer.CHANNELS
        if (totalFrames <= 0) {
            carriedSourceUs += mediaDurationUs
            return emptyList()
        }

        val totalSourceUs = carriedSourceUs + mediaDurationUs
        val startUs = (presentationTimeUs - carriedSourceUs).coerceAtLeast(0L)
        carriedSourceUs = 0L

        val blocks = ArrayList<PcmBlock>(chunks.size)
        var consumedSourceUs = 0L
        for (index in chunks.indices) {
            val chunk = chunks[index]
            val frames = chunk.size / PcmRingBuffer.CHANNELS
            val duration = if (index == chunks.lastIndex) {
                (totalSourceUs - consumedSourceUs).coerceAtLeast(0L)
            } else {
                totalSourceUs * frames / totalFrames
            }
            blocks.add(
                PcmBlock(
                    pcm = chunk,
                    frames = frames,
                    sourceStartUs = startUs + consumedSourceUs,
                    sourceDurationUs = duration,
                ),
            )
            consumedSourceUs += duration
        }
        return blocks
    }

    companion object {
        private const val MAX_DRAIN_ITERATIONS = 512
        private const val MAX_FINISH_ITERATIONS = 64

        /** Keep in sync with kMaxChannels in pcm_native.cpp. */
        private const val MAX_NATIVE_CHANNELS = 8

        /** Maps a Media3 PCM encoding onto the converter's layout. */
        fun mapEncoding(encoding: Int): Pair<PcmSampleFormat, Boolean>? = when (encoding) {
            C.ENCODING_PCM_8BIT -> PcmSampleFormat.UNSIGNED_8 to false
            C.ENCODING_PCM_16BIT -> PcmSampleFormat.SIGNED_16 to false
            C.ENCODING_PCM_16BIT_BIG_ENDIAN -> PcmSampleFormat.SIGNED_16 to true
            C.ENCODING_PCM_24BIT -> PcmSampleFormat.SIGNED_24 to false
            C.ENCODING_PCM_24BIT_BIG_ENDIAN -> PcmSampleFormat.SIGNED_24 to true
            C.ENCODING_PCM_32BIT -> PcmSampleFormat.SIGNED_32 to false
            C.ENCODING_PCM_32BIT_BIG_ENDIAN -> PcmSampleFormat.SIGNED_32 to true
            C.ENCODING_PCM_FLOAT -> PcmSampleFormat.FLOAT_32 to false
            C.ENCODING_PCM_FLOAT_BIG_ENDIAN -> PcmSampleFormat.FLOAT_32 to true
            C.ENCODING_PCM_DOUBLE -> PcmSampleFormat.FLOAT_64 to false
            C.ENCODING_PCM_DOUBLE_BIG_ENDIAN -> PcmSampleFormat.FLOAT_64 to true
            else -> null
        }

        /** Encodings the deck sink can accept. */
        fun isSupportedEncoding(encoding: Int): Boolean = mapEncoding(encoding) != null
    }
}
