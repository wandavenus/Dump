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

    private fun analyzeMultichannelRms(
        activeChannels: Set<Int>,
        invertedChannels: Set<Int> = emptySet(),
        frequencyHz: Double = 1_000.0,
    ): Double {
        val sampleRate = 48_000
        val frames = sampleRate
        val channels = 6 // 5.1: L, R, C, LFE, Ls, Rs
        val pcm = ShortArray(frames * channels)
        for (frame in 0 until frames) {
            val value = (sin(2.0 * PI * frequencyHz * frame / sampleRate) * 12_000.0).toInt()
            for (channel in activeChannels) {
                val sign = if (channel in invertedChannels) -1 else 1
                pcm[frame * channels + channel] = (value * sign).toShort()
            }
        }

        val downsampler = AutomixPcmDownsampler(sourceRateHz = sampleRate, channels = channels)
        val output = ArrayList<Float>()
        for (frame in 0 until frames) {
            downsampler.processFrame(pcm, frame)?.let(output::add)
        }
        val stable = output.drop(1_000)
        return sqrt(stable.sumOf { it.toDouble() * it.toDouble() } / stable.size)
    }

    @Test
    fun multichannelDownmixPreservesActiveChannelsWithoutDilution() {
        val monoRms = analyzeSineRms(1_000.0)
        val centerOnlyRms = analyzeMultichannelRms(activeChannels = setOf(2))
        val surroundOnlyRms = analyzeMultichannelRms(activeChannels = setOf(4))
        val stereoOnlyRms = analyzeMultichannelRms(activeChannels = setOf(0, 1))
        val antiPhaseRms = analyzeMultichannelRms(
            activeChannels = setOf(0, 1),
            invertedChannels = setOf(1),
        )

        assertTrue(
            "Center-only 5.1 content was attenuated: center=$centerOnlyRms mono=$monoRms",
            centerOnlyRms > monoRms * 0.80,
        )
        assertTrue(
            "Surround-only 5.1 content was ignored or attenuated: surround=$surroundOnlyRms mono=$monoRms",
            surroundOnlyRms > monoRms * 0.80,
        )
        assertTrue(
            "L/R-only 5.1 content was diluted by silent channels: stereo=$stereoOnlyRms mono=$monoRms",
            stereoOnlyRms > monoRms * 0.80,
        )
        assertTrue(
            "Anti-phase multichannel content collapsed to silence: rms=$antiPhaseRms",
            antiPhaseRms > monoRms * 0.80,
        )
    }
}
