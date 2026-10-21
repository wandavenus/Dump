package dev.wndavenz.music.audio.mixer

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin

/**
 * Streaming stereo sample-rate converter.
 *
 * The software mix bus runs at one negotiated rate (see
 * [SingleAudioTrackEngine.BUS_SAMPLE_RATE]); decks whose decoder rate differs
 * are converted here instead of being summed raw. A windowed-sinc kernel
 * (Blackman window, 24 taps by default) provides a proper anti-imaging /
 * anti-aliasing low-pass, unlike the linear interpolation a naive resampler
 * would apply.
 *
 * Filter state is per deck: a short history carries the last `taps - 1`
 * frames across calls so consecutive blocks join without a click. The
 * conversion is not bit-exact by design; Bit-Perfect Mode keeps its own
 * exclusive path.
 */
class SincResampler(
    private val inputRate: Int,
    private val outputRate: Int,
    private val taps: Int = DEFAULT_TAPS,
    private val phases: Int = DEFAULT_PHASES,
) {

    private val bypass =
        inputRate <= 0 || outputRate <= 0 || inputRate == outputRate

    private val half = taps / 2
    private val step = if (bypass) 1.0 else inputRate.toDouble() / outputRate

    private val cutoff = if (bypass) 1.0 else minOf(1.0, outputRate.toDouble() / inputRate)
    private val kernel: SincKernel? =
        if (bypass) null else SincKernel.get(taps, phases, cutoff)

    private val history = FloatArray((taps - 1) * PcmRingBuffer.CHANNELS)
    private val historyScratch = FloatArray((taps - 1) * PcmRingBuffer.CHANNELS)
    private var historyFrames = 0

    /** Absolute input-frame index of the first frame of the current block. */
    private var baseFrame = 0L

    /** Absolute input position of the next output frame. */
    private var position = 0.0

    private val coefficients = FloatArray(taps)

    val isBypass: Boolean get() = bypass

    /** Maximum number of output frames [resample] can produce for [frames]. */
    fun outputFramesUpperBound(frames: Int): Int {
        if (frames <= 0) return 0
        if (bypass) return frames
        return kotlin.math.ceil(frames * outputRate.toDouble() / inputRate).toInt() + 2
    }

    /**
     * Converts [frames] stereo frames from [src] into [dst] and returns the
     * number of frames written. [dst] must hold at least
     * [outputFramesUpperBound] frames.
     */
    fun resample(src: FloatArray, frames: Int, dst: FloatArray): Int {
        if (frames <= 0) return 0
        if (bypass) {
            val copied = minOf(frames, dst.size / PcmRingBuffer.CHANNELS)
            System.arraycopy(src, 0, dst, 0, copied * PcmRingBuffer.CHANNELS)
            baseFrame += frames
            return copied
        }

        val table = kernel ?: return 0
        val endExclusive = baseFrame + frames
        var outFrames = 0

        // Need samples up to floor(position) + half inside this block. The
        // remaining tail is carried into the next call.
        while (position < endExclusive - half) {
            if ((outFrames + 1) * PcmRingBuffer.CHANNELS > dst.size) break
            val index = floor(position).toLong()
            val fraction = (position - index).toFloat()
            table.fillCoefficients(fraction, coefficients)

            for (channel in 0 until PcmRingBuffer.CHANNELS) {
                var sum = 0f
                for (tap in 0 until taps) {
                    val absoluteFrame = index + tap - (half - 1)
                    sum += coefficients[tap] * sampleAt(absoluteFrame, src, channel)
                }
                dst[outFrames * PcmRingBuffer.CHANNELS + channel] = sum
            }

            outFrames++
            position += step
        }

        updateHistory(src, frames, endExclusive)
        return outFrames
    }

    /** Clears filter state; call on seek/flush. */
    fun reset() {
        historyFrames = 0
        baseFrame = 0L
        position = 0.0
    }

    private fun sampleAt(
        absoluteFrame: Long,
        src: FloatArray,
        channel: Int,
    ): Float {
        if (absoluteFrame < 0L) return 0f
        if (absoluteFrame >= baseFrame) {
            val index = (absoluteFrame - baseFrame).toInt()
            if (index * PcmRingBuffer.CHANNELS + channel >= src.size) return 0f
            return src[index * PcmRingBuffer.CHANNELS + channel]
        }
        val historyIndex = absoluteFrame - (baseFrame - historyFrames)
        if (historyIndex < 0L || historyIndex >= historyFrames) return 0f
        return history[historyIndex.toInt() * PcmRingBuffer.CHANNELS + channel]
    }

    private fun updateHistory(src: FloatArray, frames: Int, endExclusive: Long) {
        val historyStart = maxOf(0L, endExclusive - (taps - 1))
        val count = (endExclusive - historyStart).toInt()
        for (i in 0 until count) {
            val absoluteFrame = historyStart + i
            for (channel in 0 until PcmRingBuffer.CHANNELS) {
                historyScratch[i * PcmRingBuffer.CHANNELS + channel] =
                    sampleAt(absoluteFrame, src, channel)
            }
        }
        System.arraycopy(
            historyScratch,
            0,
            history,
            0,
            count * PcmRingBuffer.CHANNELS,
        )
        historyFrames = count
        baseFrame = endExclusive
    }

    private class SincKernel(
        private val taps: Int,
        private val phases: Int,
        private val cutoff: Double,
    ) {
        private val table = FloatArray(phases * taps)

        init {
            val half = taps / 2
            for (phase in 0 until phases) {
                val fraction = phase.toDouble() / phases
                var sum = 0.0
                for (tap in 0 until taps) {
                    val offset = (tap - (half - 1)) - fraction
                    val window = if (abs(offset) >= half) {
                        0.0
                    } else {
                        0.42 + 0.5 * cos(PI * offset / half) +
                            0.08 * cos(2.0 * PI * offset / half)
                    }
                    // For downsampling the cutoff moves to the output Nyquist
                    // so input content above it is filtered instead of aliasing.
                    val scaled = cutoff * offset
                    val sinc = if (abs(scaled) < 1e-9) {
                        1.0
                    } else {
                        sin(PI * scaled) / (PI * scaled)
                    }
                    val coefficient = cutoff * sinc * window
                    table[phase * taps + tap] = coefficient.toFloat()
                    sum += coefficient
                }
                if (abs(sum) > 1e-12) {
                    for (tap in 0 until taps) {
                        table[phase * taps + tap] =
                            (table[phase * taps + tap] / sum).toFloat()
                    }
                }
            }
        }

        fun fillCoefficients(fraction: Float, out: FloatArray) {
            val row = fraction.toDouble() * phases
            val row0 = minOf(floor(row).toInt(), phases - 1)
            val blend = (row - row0).toFloat()
            val row1 = (row0 + 1) % phases
            val base0 = row0 * taps
            val base1 = row1 * taps
            for (tap in 0 until taps) {
                out[tap] = table[base0 + tap] * (1f - blend) +
                    table[base1 + tap] * blend
            }
        }

        companion object {
            private data class KernelKey(
                val taps: Int,
                val phases: Int,
                val cutoffPermille: Int,
            )

            private val cache = HashMap<KernelKey, SincKernel>()

            @Synchronized
            fun get(taps: Int, phases: Int, cutoff: Double): SincKernel {
                val key = KernelKey(
                    taps = taps,
                    phases = phases,
                    cutoffPermille = (cutoff * 1_000.0).toInt(),
                )
                cache[key]?.let { return it }
                val kernel = SincKernel(taps, phases, cutoff)
                if (cache.size >= MAX_CACHED_KERNELS) cache.clear()
                cache[key] = kernel
                return kernel
            }

            private const val MAX_CACHED_KERNELS = 8
        }
    }

    companion object {
        const val DEFAULT_TAPS = 32
        const val DEFAULT_PHASES = 256
    }
}
