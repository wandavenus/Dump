package dev.wndavenz.music.automix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
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
        assertTrue("1 kHz passband was unexpectedly attenuated: $passbandRms", passbandRms > 0.20)
        // These source tones are at/above the post-decimation Nyquist band and
        // would otherwise fold into frequencies used by chroma/onset analysis.
        for (frequencyHz in listOf(
            12_000.0,
            15_000.0,
            18_000.0,
            21_000.0,
            23_000.0,
            23_900.0,
        )) {
            val aliasedRms = analyzeSineRms(frequencyHz)
            assertTrue(
                "$frequencyHz Hz content was not sufficiently suppressed: " +
                    "rms=$aliasedRms, passband=$passbandRms",
                aliasedRms < passbandRms * 0.30,
            )
        }
    }

    @Test
    fun antiPhaseStereoDoesNotCollapseToSilence() {
        val rms = analyzeSineRms(1_000.0, stereoAntiPhase = true)
        assertTrue("anti-phase stereo was incorrectly cancelled: rms=$rms", rms > 0.20)
    }

    @Test
    fun antiPhaseFallbackDoesNotFollowRapidInstantaneousPeakSwaps() {
        val sampleRate = 48_000
        val frames = sampleRate
        val pcm = ShortArray(frames * 2)
        val leftOnly = ShortArray(frames)
        val blockFrames = sampleRate / 200 // 5 ms; faster than the 20 ms energy smoother.
        for (frame in 0 until frames) {
            val leftAmplitude = if ((frame / blockFrames) % 2 == 0) 15_000 else 14_000
            val rightAmplitude = if ((frame / blockFrames) % 2 == 0) 14_000 else 15_000
            val phase = sin(2.0 * PI * 1_000.0 * frame / sampleRate)
            val left = (phase * leftAmplitude).toInt().toShort()
            val right = (-phase * rightAmplitude).toInt().toShort()
            pcm[frame * 2] = left
            pcm[frame * 2 + 1] = right
            leftOnly[frame] = left
        }

        val stereoDownsampler = AutomixPcmDownsampler(sampleRate, channels = 2)
        val monoDownsampler = AutomixPcmDownsampler(sampleRate, channels = 1)
        val stereoOutput = ArrayList<Float>()
        val leftOutput = ArrayList<Float>()
        for (frame in 0 until frames) {
            stereoDownsampler.processFrame(pcm, frame)?.let(stereoOutput::add)
            monoDownsampler.processFrame(leftOnly, frame)?.let(leftOutput::add)
        }

        val stableStereo = stereoOutput.drop(1_000)
        val stableLeft = leftOutput.drop(1_000)
        val dot = stableStereo.indices.sumOf { stableStereo[it].toDouble() * stableLeft[it] }
        val stereoPower = stableStereo.sumOf { it.toDouble() * it }
        val leftPower = stableLeft.sumOf { it.toDouble() * it }
        val correlation = dot / sqrt(stereoPower * leftPower)
        assertTrue(
            "anti-phase fallback followed instantaneous peak swaps: correlation=$correlation",
            correlation > 0.95,
        )
    }

    @Test
    fun wideStereoPadPreservesItsStableCenterSignal() {
        val sampleRate = 48_000
        val frames = sampleRate
        val mono = ShortArray(frames)
        val stereo = ShortArray(frames * 2)
        for (frame in 0 until frames) {
            val center = (sin(2.0 * PI * 1_000.0 * frame / sampleRate) * 12_000.0)
                .toInt()
            val side = (sin(2.0 * PI * 3_000.0 * frame / sampleRate) * 3_000.0)
                .toInt()
            mono[frame] = center.toShort()
            stereo[frame * 2] = (center + side).toShort()
            stereo[frame * 2 + 1] = (center - side).toShort()
        }

        val monoDownsampler = AutomixPcmDownsampler(sampleRate, channels = 1)
        val stereoDownsampler = AutomixPcmDownsampler(sampleRate, channels = 2)
        val monoOutput = ArrayList<Float>()
        val stereoOutput = ArrayList<Float>()
        for (frame in 0 until frames) {
            monoDownsampler.processFrame(mono, frame)?.let(monoOutput::add)
            stereoDownsampler.processFrame(stereo, frame)?.let(stereoOutput::add)
        }

        assertEquals(monoOutput.size, stereoOutput.size)
        val maxDifference = monoOutput.indices.maxOf { abs(monoOutput[it] - stereoOutput[it]) }
        assertTrue("wide stereo pad changed the stable center signal: diff=$maxDifference", maxDifference < 1e-6)
    }

    @Test
    fun identicalStereoMatchesMonoAndKeepsOutputRate() {
        val sampleRate = 48_000
        val frames = sampleRate / 10
        val mono = ShortArray(frames)
        val stereo = ShortArray(frames * 2)
        for (frame in 0 until frames) {
            val sample = (sin(2.0 * PI * 440.0 * frame / sampleRate) * 10_000.0)
                .toInt().toShort()
            mono[frame] = sample
            stereo[frame * 2] = sample
            stereo[frame * 2 + 1] = sample
        }

        val monoDownsampler = AutomixPcmDownsampler(sampleRate, channels = 1)
        val stereoDownsampler = AutomixPcmDownsampler(sampleRate, channels = 2)
        val monoOutput = ArrayList<Float>()
        val stereoOutput = ArrayList<Float>()
        for (frame in 0 until frames) {
            monoDownsampler.processFrame(mono, frame)?.let(monoOutput::add)
            stereoDownsampler.processFrame(stereo, frame)?.let(stereoOutput::add)
        }

        assertEquals(24_000, stereoDownsampler.outputRateHz)
        assertEquals(monoOutput, stereoOutput)
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
