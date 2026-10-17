package dev.wndavenz.music.automix

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt

class AutomixPcmDownsamplerTest {
    private fun analyzeSineRms(
        frequencyHz: Double,
        stereoAntiPhase: Boolean = false,
    ): Double {
        val sampleRate = 48_000
        val frames = sampleRate
        val pcm = ShortArray(frames * if (stereoAntiPhase) 2 else 1)
        for (i in 0 until frames) {
            val value = (sin(2.0 * PI * frequencyHz * i / sampleRate) * 12_000.0).toInt()
                .toShort()
            if (stereoAntiPhase) {
                pcm[i * 2] = value
                pcm[i * 2 + 1] = (-value.toInt()).toShort()
            } else {
                pcm[i] = value
            }
        }

        val downsampler = AutomixPcmDownsampler(
            sourceRateHz = sampleRate,
            channels = if (stereoAntiPhase) 2 else 1,
        )
        val output = ArrayList<Float>()
        for (frame in 0 until frames) {
            downsampler.processFrame(pcm, frame)?.let(output::add)
        }
        val stable = output.drop(1_000)
        return sqrt(stable.sumOf { it.toDouble() * it.toDouble() } / stable.size)
    }

    @Test
    fun antiAliasFilterSuppressesFrequenciesAbovePostDecimationNyquist() {
        val passbandRms = analyzeSineRms(1_000.0)
        // 18 kHz aliases to 6 kHz after decimation by two without anti-aliasing.
        val aliasedRms = analyzeSineRms(18_000.0)

        assertTrue("1 kHz passband was unexpectedly attenuated: $passbandRms", passbandRms > 0.20)
        assertTrue(
            "18 kHz content was not sufficiently attenuated before decimation: $aliasedRms",
            aliasedRms < passbandRms * 0.20,
        )
    }

    @Test
    fun antiPhaseStereoDoesNotCollapseToSilence() {
        val rms = analyzeSineRms(1_000.0, stereoAntiPhase = true)
        assertTrue("anti-phase stereo was incorrectly cancelled: rms=$rms", rms > 0.20)
    }
}
