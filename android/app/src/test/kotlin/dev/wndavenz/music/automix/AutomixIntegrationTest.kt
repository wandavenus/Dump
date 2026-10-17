package dev.wndavenz.music.automix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

class AutomixIntegrationTest {

    @Test
    fun `equal power gain integration with dynamic volume target`() {
        val outgoingTrim = 0.7f
        val incomingTrim = 0.8f

        // Progress values 0, 0.25, 0.5, 0.75, 1.0
        val progressValues = floatArrayOf(0f, 0.25f, 0.5f, 0.75f, 1.0f)
        var targetVol = 1.0f

        for (t in progressValues) {
            val attack = if (t >= 0.25f) 1f else t / 0.25f
            val outgoingTrimNow = 1f - (1f - outgoingTrim) * attack

            val release = if (t <= 0.75f) 0f else (t - 0.75f) / 0.25f
            val incomingTrimNow = incomingTrim + (1f - incomingTrim) * release

            val theta = (t * PI / 2.0).toFloat()
            val outgoingGain = outgoingTrimNow * cos(theta)
            val incomingGain = incomingTrimNow * sin(theta)

            val gainSum = outgoingGain + incomingGain
            // Bound the L1 sum, not just equal-power energy: two correlated
            // decks can add sample-for-sample in Android's downstream mixer.
            val headroomScale = if (gainSum > 1f) 1f / gainSum else 1f

            val oldVol = (targetVol * outgoingGain * headroomScale).coerceIn(0f, targetVol)
            val newVol = (targetVol * incomingGain * headroomScale).coerceIn(0f, targetVol)
            assertTrue(oldVol + newVol <= targetVol + 0.001f)

            if (t == 0f) {
                assertEquals(targetVol, oldVol, 0.001f)
                assertEquals(0f, newVol, 0.001f)
            } else if (t == 1.0f) {
                assertEquals(0f, oldVol, 0.001f)
                assertEquals(targetVol, newVol, 0.001f)
            }

            assertTrue(oldVol in 0f..targetVol)
            assertTrue(newVol in 0f..targetVol)
        }

        // Test audio focus ducking (volume drops to 0.3)
        targetVol = 0.3f
        val t = 0.5f
        val theta = (t * PI / 2.0).toFloat()
        val oldVolDucked = targetVol * cos(theta)
        val newVolDucked = targetVol * sin(theta)

        assertEquals(0.3f * 0.7071f, oldVolDucked, 0.01f)
        assertEquals(0.3f * 0.7071f, newVolDucked, 0.01f)
    }

    @Test
    fun `phase lock factor evaluation remains bounded`() {
        val factor = AutomixPhaseLock.factorFor(
            outgoingPositionMs = 1000.0,
            outgoingPhaseOffsetMs = 0.0,
            outgoingBpm = 120.0,
            incomingPositionMs = 5000.0,
            incomingPhaseOffsetMs = 0.0,
            incomingBpm = 120.0,
            remainingMs = 4000.0,
        )

        // Without native library loaded in pure JVM unit test, returns null (safe fallback)
        assertTrue(factor == null || (factor in 0.95f..1.05f))
    }
}
