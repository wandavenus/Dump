package dev.wndavenz.music.automix

import kotlin.math.abs
import kotlin.math.exp
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
 * It also accumulates center/side power so the native vocal proxy can use
 * center-channel dominance as evidence without a second stereo downsample.
 */
internal class AutomixPcmDownsampler(
    private val sourceRateHz: Int,
    private val channels: Int,
    targetRateHz: Int = 22_050,
) {
    private val factor: Int
    val outputRateHz: Int
    private val lowPass: ButterworthLowPass
    // Smoothed channel energy avoids switching the fallback channel on individual PCM frames.
    private val channelPower = DoubleArray(channels)
    private val channelSamples = DoubleArray(channels)
    private val channelPowerSmoothing =
        1.0 - exp(-1.0 / (sourceRateHz.coerceAtLeast(1) * 0.020))
    private var sum = 0.0
    private var count = 0
    private var centerPower = 0.0
    private var sidePower = 0.0

    /**
     * Center-channel power divided by center-plus-side power for stereo input.
     * NAN for mono/multichannel sources or silent windows.
     */
    val centerChannelRatio: Double
        get() {
            val total = centerPower + sidePower
            return if (channels == 2 && total > 1e-12) {
                centerPower / total
            } else {
                Double.NaN
            }
        }

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

        val mono = when (channels) {
            1 -> interleavedPcm16[base] / 32768.0
            2 -> {
                val left = interleavedPcm16[base] / 32768.0
                val right = interleavedPcm16[base + 1] / 32768.0
                val mid = (left + right) * 0.5
                val side = (left - right) * 0.5
                centerPower += mid * mid
                sidePower += side * side
                val strongest = if (abs(left) >= abs(right)) left else right
                if (abs(mid) < 0.25 * max(abs(left), abs(right))) strongest else mid
            }
            else -> {
                var maxPower = 0.0
                var maxAbs = 0.0
                var dominantSample = 0.0
                for (ch in 0 until channels) {
                    val sample = interleavedPcm16[base + ch] / 32768.0
                    channelSamples[ch] = sample
                    val absSample = abs(sample)
                    if (absSample > maxAbs) maxAbs = absSample

                    val power = sample * sample
                    channelPower[ch] += channelPowerSmoothing * (power - channelPower[ch])
                    if (channelPower[ch] > maxPower) {
                        maxPower = channelPower[ch]
                        dominantSample = sample
                    }
                }

                val maxRms = sqrt(maxPower)
                if (maxRms <= 1e-9) {
                    0.0
                } else {
                    // Ignore near-silent channels, then normalize by the remaining weight.
                    // That preserves L/R-only material inside a 5.1 stream without letting
                    // silent channels automatically attenuate it by 1/N.
                    var weightedSum = 0.0
                    var totalWeight = 0.0
                    for (ch in 0 until channels) {
                        val relativeRms = sqrt(channelPower[ch]) / maxRms
                        val weight = ((relativeRms - 0.05) / 0.10).coerceIn(0.0, 1.0)
                        if (weight > 0.0) {
                            weightedSum += channelSamples[ch] * weight
                            totalWeight += weight
                        }
                    }
                    val average = if (totalWeight > 0.0) weightedSum / totalWeight else 0.0
                    // For anti-phase material, fall back to the channel with strongest smoothed
                    // energy rather than whichever individual sample happens to peak this frame.
                    if (abs(average) < 0.25 * maxAbs) dominantSample else average
                }
            }
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
