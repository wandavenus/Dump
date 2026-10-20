package dev.wndavenz.music.automix

import org.junit.Assert.assertEquals
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

    private fun centerRatioForStereo(mode: Int, channels: Int = 2): Double {
        val sampleRate = 48_000
        val frames = 4_800
        val pcm = ShortArray(frames * channels)
        for (frame in 0 until frames) {
            val value = (sin(2.0 * PI * 1_000.0 * frame / sampleRate) * 12_000.0)
                .toInt().toShort()
            when (mode) {
                0 -> {
                    pcm[frame * channels] = value
                    pcm[frame * channels + 1] = value
                }
                1 -> {
                    pcm[frame * channels] = value
                    pcm[frame * channels + 1] = (-value.toInt()).toShort()
                }
                2 -> {
                    pcm[frame * channels] = value
                    pcm[frame * channels + 1] = 0
                }
                else -> pcm[frame * channels] = value
            }
        }
        val downsampler = AutomixPcmDownsampler(
            sourceRateHz = sampleRate,
            channels = channels,
        )
        for (frame in 0 until frames) {
            downsampler.processFrame(pcm, frame)
        }
        return downsampler.centerChannelRatio
    }

    @Test
    fun centerChannelRatioSeparatesCenteredAndWideStereo() {
        val centered = centerRatioForStereo(mode = 0)
        val antiPhase = centerRatioForStereo(mode = 1)
        val oneSided = centerRatioForStereo(mode = 2)
        val mono = centerRatioForStereo(mode = 3, channels = 1)

        assertTrue("centered stereo should be center-dominant: $centered", centered > 0.99)
        assertTrue("anti-phase stereo has no center: $antiPhase", antiPhase < 1e-6)
        assertEquals("one-sided stereo should be half center power", 0.5, oneSided, 1e-9)
        assertTrue("mono has no center/side split", mono.isNaN())
    }

    private fun analyzeMultichannelRms(
        activeChannels: Set<Int>,
        invertedChannels: Set<Int> = emptySet(),
        frequencyHz: Double = 1_000.0,
        lfeAmplitude: Int = 0,
        channelMask: Int = 0,
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
            if (lfeAmplitude > 0) {
                pcm[frame * channels + 3] = (
                    sin(2.0 * PI * 60.0 * frame / sampleRate) * lfeAmplitude
                    ).toInt().toShort()
            }
        }

        val downsampler = AutomixPcmDownsampler(
            sourceRateHz = sampleRate,
            channels = channels,
            channelMask = channelMask,
        )
        val output = ArrayList<Float>()
        for (frame in 0 until frames) {
            downsampler.processFrame(pcm, frame)?.let(output::add)
        }
        val stable = output.drop(1_000)
        return sqrt(stable.sumOf { it.toDouble() * it.toDouble() } / stable.size)
    }

    @Test
    fun lfeChannelIsExcludedWhenChannelMaskIdentifiesIt() {
        val stereoOnly = analyzeMultichannelRms(activeChannels = setOf(0, 1))
        val dominantLfe = analyzeMultichannelRms(
            activeChannels = setOf(0, 1),
            lfeAmplitude = 30_000,
            // 5.1: FL | FR | FC | LFE | BL | BR.
            channelMask = 0xFC,
        )

        assertEquals(
            "LFE must not dominate the analysis downmix",
            stereoOnly,
            dominantLfe,
            stereoOnly * 0.02,
        )
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
