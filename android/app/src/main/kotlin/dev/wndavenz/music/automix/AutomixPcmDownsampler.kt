package dev.wndavenz.music.automix

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Stateful PCM16-to-mono downsampler used by offline AutoMix analysis.
 * Filters at the source rate before decimation to suppress aliasing.
 * Stereo averages normally, but avoids near-total cancellation by selecting
 * the stronger channel when the mid signal is less than 25% of either side.
 */
internal class AutomixPcmDownsampler(
    private val sourceRateHz: Int,
    private val channels: Int,
    targetRateHz: Int = 22_050,
) {
    private val factor: Int
    val outputRateHz: Int
    private val lowPass: ButterworthLowPass
    private var sum = 0.0
    private var count = 0

    init {
        require(sourceRateHz > 0) { "sourceRateHz must be positive" }
        require(channels > 0) { "channels must be positive" }
        require(targetRateHz > 0) { "targetRateHz must be positive" }
        factor = max(1, (sourceRateHz.toDouble() / targetRateHz).roundToInt())
        outputRateHz = sourceRateHz / factor
        lowPass = ButterworthLowPass(
            sampleRateHz = sourceRateHz.toDouble(),
            cutoffHz = outputRateHz * 0.45,
        )
    }

    /** Returns a downsampled mono sample only when the decimation interval completes. */
    fun processFrame(interleavedPcm16: ShortArray, frameIndex: Int): Float? {
        require(frameIndex >= 0) { "frameIndex must not be negative" }
        val base = frameIndex * channels
        require(base + channels <= interleavedPcm16.size) {
            "frameIndex is outside the PCM buffer"
        }

        val mono = if (channels == 1) {
            interleavedPcm16[base] / 32768.0
        } else {
            val left = interleavedPcm16[base] / 32768.0
            val right = interleavedPcm16[base + 1] / 32768.0
            val mid = (left + right) * 0.5
            val strongest = if (abs(left) >= abs(right)) left else right
            if (abs(mid) < 0.25 * max(abs(left), abs(right))) strongest else mid
        }

        sum += lowPass.process(mono)
        count++
        if (count < factor) return null
        val output = (sum / count).toFloat()
        sum = 0.0
        count = 0
        return output
    }

    private class ButterworthLowPass(sampleRateHz: Double, cutoffHz: Double) {
        private val b0: Double
        private val b1: Double
        private val b2: Double
        private val a1: Double
        private val a2: Double
        private var x1 = 0.0
        private var x2 = 0.0
        private var y1 = 0.0
        private var y2 = 0.0

        init {
            val cutoff = cutoffHz.coerceIn(1.0, sampleRateHz * 0.49)
            val omega = 2.0 * Math.PI * cutoff / sampleRateHz
            val c = cos(omega)
            val alpha = sin(omega) / (2.0 * (1.0 / sqrt(2.0)))
            val a0 = 1.0 + alpha
            b0 = ((1.0 - c) * 0.5) / a0
            b1 = (1.0 - c) / a0
            b2 = ((1.0 - c) * 0.5) / a0
            a1 = (-2.0 * c) / a0
            a2 = (1.0 - alpha) / a0
        }

        fun process(input: Double): Double {
            val output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = input
            y2 = y1
            y1 = if (output.isFinite()) output else 0.0
            return y1
        }
    }
}
