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
 * Stereo averages normally, but selects a stable channel when smoothed mid
 * energy is very small relative to side energy. A fourth-order Butterworth
 * low-pass protects the decimated signal from aliasing.
 * It also accumulates center/side power so the native vocal proxy can use
 * center-channel dominance as evidence without a second stereo downsample.
 */
internal class AutomixPcmDownsampler(
    private val sourceRateHz: Int,
    private val channels: Int,
    targetRateHz: Int = 22_050,
    channelMask: Int = 0,
) {
    private companion object {
        // Android AudioFormat.CHANNEL_OUT_LOW_FREQUENCY. Kept local so the
        // pure-JVM unit tests do not depend on Android framework constants.
        const val LOW_FREQUENCY_MASK = 0x20
    }

    private val factor: Int
    val outputRateHz: Int
    private val lowPass: ButterworthLowPass
    private val lfeChannels = BooleanArray(channels)
    // Smoothed channel energy avoids switching the fallback channel on individual PCM frames.
    private val channelPower = DoubleArray(channels)
    private val channelSamples = DoubleArray(channels)
    private val channelPowerSmoothing =
        1.0 - exp(-1.0 / (sourceRateHz.coerceAtLeast(1) * 0.020))
    private var sum = 0.0
    private var count = 0
    private var stereoMidPower = 0.0
    private var stereoSidePower = 0.0
    private var stereoFallbackChannel = 0
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
            cutoffHz = outputRateHz * 0.40,
        )
        // Channel order follows the set bits of the Android channel mask.
        // Leave lfeChannels all-false when the container omits a mask.
        if (channels > 2 && channelMask != 0) {
            var channelIndex = 0
            var bit = 1
            while (bit != 0 && channelIndex < channels) {
                if (channelMask and bit != 0) {
                    if (bit == LOW_FREQUENCY_MASK) {
                        lfeChannels[channelIndex] = true
                    }
                    channelIndex++
                }
                bit = bit shl 1
            }
        }
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
                stereoMidPower += channelPowerSmoothing * (mid * mid - stereoMidPower)
                stereoSidePower += channelPowerSmoothing * (side * side - stereoSidePower)
                channelPower[0] += channelPowerSmoothing * (left * left - channelPower[0])
                channelPower[1] += channelPowerSmoothing * (right * right - channelPower[1])

                // The 20 ms energy estimates prevent momentary zero crossings from
                // changing the downmix. Hysteresis keeps nearly equal anti-phase
                // channels from swapping polarity as their instantaneous peaks vary.
                val otherChannel = 1 - stereoFallbackChannel
                if (channelPower[otherChannel] > channelPower[stereoFallbackChannel] * 1.25) {
                    stereoFallbackChannel = otherChannel
                }
                val fallback = if (stereoFallbackChannel == 0) left else right
                if (stereoMidPower < stereoSidePower * 0.0625) fallback else mid
            }
            else -> {
                var maxPower = 0.0
                var maxAbs = 0.0
                var dominantSample = 0.0
                for (ch in 0 until channels) {
                    // LFE carries sub-bass effects, not musical tempo/key
                    // information; including it would let a loud sub channel
                    // dominate BPM/onset/key analysis. Exclude it when the
                    // container's channel mask identifies it.
                    if (lfeChannels[ch]) {
                        channelSamples[ch] = 0.0
                        channelPower[ch] = 0.0
                        continue
                    }
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
        private val lowQSection: Biquad
        private val highQSection: Biquad

        init {
            val cutoff = cutoffHz.coerceIn(1.0, sampleRateHz * 0.49)
            // The two pole pairs of a fourth-order Butterworth have these Qs.
            lowQSection = Biquad(sampleRateHz, cutoff, 0.541196100146197)
            highQSection = Biquad(sampleRateHz, cutoff, 1.306562964876377)
        }

        fun process(input: Double): Double = highQSection.process(lowQSection.process(input))
    }

    private class Biquad(sampleRateHz: Double, cutoffHz: Double, q: Double) {
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
            val omega = 2.0 * Math.PI * cutoffHz / sampleRateHz
            val c = cos(omega)
            val alpha = sin(omega) / (2.0 * q)
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
