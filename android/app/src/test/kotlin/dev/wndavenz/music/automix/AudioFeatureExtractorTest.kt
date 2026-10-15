package dev.wndavenz.music.automix

import kotlin.math.PI
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioFeatureExtractorTest {

    @Test
    fun tempoDetectorAcceptsOnsetFramesRatherThanComparingThemToSampleRate() {
        val workingRate = 22_050
        // About ten seconds at 120 BPM: roughly 430 onset frames, not 22,050
        // samples. The old guard incorrectly rejected every ordinary track.
        val onsetEnvelope = FloatArray(430)
        for (i in onsetEnvelope.indices step 22) {
            onsetEnvelope[i] = 1f
        }

        val tempo = AudioFeatureExtractor.estimateTempo(onsetEnvelope, workingRate)
        assertNotNull("A periodic onset envelope should yield a tempo", tempo)
        assertTrue("Expected a result near 120 BPM, got ${tempo!!.bpm}", tempo.bpm in 110.0..125.0)
    }

    @Test
    fun keyProfileRotationMapsEachTonicToItsPitchClass() {
        val profiles = listOf(
            AudioFeatureExtractor.KS_MAJOR to true,
            AudioFeatureExtractor.KS_MINOR to false,
        )

        for ((profile, isMajor) in profiles) {
            for (tonic in 0 until 12) {
                // Rotate a tonic-relative profile into absolute pitch-class space.
                val chroma = FloatArray(12) { pc ->
                    profile[(pc - tonic + 12) % 12].toFloat()
                }
                val estimate = AudioFeatureExtractor.estimateKey(chroma)
                assertNotNull("Key estimate missing for tonic $tonic", estimate)
                assertEquals("Wrong tonic for pitch class $tonic", tonic, estimate!!.first)
                assertEquals("Wrong mode for pitch class $tonic", isMajor, estimate.second)
                assertTrue("Synthetic profile should have positive confidence", estimate.third > 0.0)
            }
        }
    }

    @Test
    fun rmsDbIsMeasuredFromPcmSamples() {
        val sampleRate = 22_050
        val amplitude = 0.5
        val pcm = FloatArray(sampleRate * 2) { i ->
            (amplitude * sin(2.0 * PI * 440.0 * i / sampleRate)).toFloat()
        }

        val result = AudioFeatureExtractor.analyze(pcm, sampleRate)
        assertNotNull("Non-silent PCM should be analyzable", result)
        assertNotNull("Non-silent PCM should have an RMS value", result!!.rmsDb)
        // A 0.5-peak sine has RMS 0.3536, or about -9.03 dBFS.
        assertEquals(-9.03, result.rmsDb!!, 1.0)
    }
}
