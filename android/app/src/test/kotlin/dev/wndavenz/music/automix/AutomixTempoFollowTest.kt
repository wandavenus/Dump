package dev.wndavenz.music.automix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomixTempoFollowTest {
    @Test
    fun `confident live pair refines the static multiplier`() {
        // Planner matched 128 -> 126 (multiplier ~1.016), but the decks really
        // run at 128.2 and 126.0: the incoming deck must speed up slightly.
        val factor = AutomixTempoFollow.relativeFactor(
            outgoingLiveBpm = 128.2f,
            outgoingLiveConfidence = 0.8f,
            incomingLiveBpm = 126.0f,
            incomingLiveConfidence = 0.8f,
            outgoingOfflineBpm = 128f,
            incomingOfflineBpm = 126f,
            baseMultiplier = 128f / 126f,
        )!!
        assertTrue(factor > 1f)
        assertEquals(1f + 0.2f / 128f, factor, 0.001f)
    }

    @Test
    fun `low confidence keeps the planner match`() {
        assertNull(
            AutomixTempoFollow.relativeFactor(
                outgoingLiveBpm = 128.2f,
                outgoingLiveConfidence = 0.2f,
                incomingLiveBpm = 126.0f,
                incomingLiveConfidence = 0.8f,
                outgoingOfflineBpm = 128f,
                incomingOfflineBpm = 126f,
                baseMultiplier = 128f / 126f,
            ),
        )
        assertNull(
            AutomixTempoFollow.relativeFactor(
                outgoingLiveBpm = 128.2f,
                outgoingLiveConfidence = 0.8f,
                incomingLiveBpm = 126.0f,
                incomingLiveConfidence = 0.49f,
                outgoingOfflineBpm = 128f,
                incomingOfflineBpm = 126f,
                baseMultiplier = 128f / 126f,
            ),
        )
    }

    @Test
    fun `missing offline grid disables tempo follow`() {
        assertNull(
            AutomixTempoFollow.relativeFactor(
                outgoingLiveBpm = 128f,
                outgoingLiveConfidence = 0.9f,
                incomingLiveBpm = 126f,
                incomingLiveConfidence = 0.9f,
                outgoingOfflineBpm = null,
                incomingOfflineBpm = 126f,
                baseMultiplier = 1f,
            ),
        )
    }

    @Test
    fun `half time live readings fold onto the planner octave`() {
        // Live reports the outgoing deck at half time (64) and the incoming at
        // its real tempo (126); the folded ratio matches the offline pair.
        val factor = AutomixTempoFollow.relativeFactor(
            outgoingLiveBpm = 64f,
            outgoingLiveConfidence = 0.9f,
            incomingLiveBpm = 126f,
            incomingLiveConfidence = 0.9f,
            outgoingOfflineBpm = 128f,
            incomingOfflineBpm = 126f,
            baseMultiplier = 128f / 126f,
        )
        assertNull("identical folded ratios need no correction", factor)
    }

    @Test
    fun `correction is capped and stays inside the stretch range`() {
        val factor = AutomixTempoFollow.relativeFactor(
            outgoingLiveBpm = 140f,
            outgoingLiveConfidence = 0.9f,
            incomingLiveBpm = 120f,
            incomingLiveConfidence = 0.9f,
            outgoingOfflineBpm = 120f,
            incomingOfflineBpm = 120f,
            baseMultiplier = 1.07f,
        )!!
        assertTrue(factor <= 1.02f + 0.0001f)
        assertTrue(factor >= 0.98f - 0.0001f)
        assertTrue(1.07f * factor <= 1.08f + 0.0001f)

        val clampLow = AutomixTempoFollow.relativeFactor(
            outgoingLiveBpm = 100f,
            outgoingLiveConfidence = 0.9f,
            incomingLiveBpm = 140f,
            incomingLiveConfidence = 0.9f,
            outgoingOfflineBpm = 120f,
            incomingOfflineBpm = 120f,
            baseMultiplier = 0.93f,
        )!!
        assertTrue(0.93f * clampLow >= 0.92f - 0.0001f)
    }

    @Test
    fun `infinite and non positive tempos are rejected`() {
        assertNull(
            AutomixTempoFollow.relativeFactor(
                outgoingLiveBpm = Float.POSITIVE_INFINITY,
                outgoingLiveConfidence = 1f,
                incomingLiveBpm = 126f,
                incomingLiveConfidence = 1f,
                outgoingOfflineBpm = 128f,
                incomingOfflineBpm = 126f,
                baseMultiplier = 1f,
            ),
        )
        assertNull(
            AutomixTempoFollow.relativeFactor(
                outgoingLiveBpm = 128f,
                outgoingLiveConfidence = 1f,
                incomingLiveBpm = 0f,
                incomingLiveConfidence = 1f,
                outgoingOfflineBpm = 128f,
                incomingOfflineBpm = 126f,
                baseMultiplier = 1f,
            ),
        )
    }

    @Test
    fun `ramp starts neutral and reaches the target after the ramp window`() {
        assertEquals(1f, AutomixTempoFollow.ramp(1.02f, 0f), 0.0001f)
        assertEquals(1.01f, AutomixTempoFollow.ramp(1.02f, 0.125f), 0.0001f)
        assertEquals(1.02f, AutomixTempoFollow.ramp(1.02f, 0.25f), 0.0001f)
        assertEquals(1.02f, AutomixTempoFollow.ramp(1.02f, 1f), 0.0001f)
        assertEquals(1f, AutomixTempoFollow.ramp(null, 0.5f), 0.0001f)
        assertEquals(1f, AutomixTempoFollow.ramp(1.02f, Float.NaN), 0.0001f)
    }

    @Test
    fun `tiny corrections are ignored to avoid churn`() {
        val factor = AutomixTempoFollow.relativeFactor(
            outgoingLiveBpm = 126.0001f,
            outgoingLiveConfidence = 0.9f,
            incomingLiveBpm = 126f,
            incomingLiveConfidence = 0.9f,
            outgoingOfflineBpm = 126f,
            incomingOfflineBpm = 126f,
            baseMultiplier = 1f,
        )
        assertNull(factor)
    }
}
