package dev.wndavenz.music.automix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Properties

class AutomixTransitionPolicyTest {
    @Test
    fun `early handover validation rejects cues the scheduler cannot honor`() {
        assertTrue(
            AutomixTransitionPolicy.isValidEarlyHandover(120_000L, 180_000L, 6_000L),
        )
        assertFalse(AutomixTransitionPolicy.isValidEarlyHandover(null, 180_000L, 6_000L))
        assertFalse(AutomixTransitionPolicy.isValidEarlyHandover(10_000L, 180_000L, 6_000L))
        assertFalse(AutomixTransitionPolicy.isValidEarlyHandover(151_000L, 180_000L, 6_000L))
        assertFalse(AutomixTransitionPolicy.isValidEarlyHandover(120_000L, 0L, 6_000L))
        assertFalse(AutomixTransitionPolicy.isValidEarlyHandover(120_000L, 180_000L, 60_000L))
    }

    @Test
    fun `beat phase lock requires two planner-approved tempo grids`() {
        assertTrue(AutomixTransitionPolicy.isBeatMatchedPair(120f, 124f))
        assertFalse(AutomixTransitionPolicy.isBeatMatchedPair(null, 124f))
        assertFalse(AutomixTransitionPolicy.isBeatMatchedPair(120f, null))
        assertFalse(AutomixTransitionPolicy.isBeatMatchedPair(49f, 124f))
        assertFalse(AutomixTransitionPolicy.isBeatMatchedPair(120f, Float.NaN))
    }

    @Test
    fun `fade progress follows elapsed source-media time at the applied speed`() {
        val elapsedAtTwoTimes = AutomixTransitionPolicy.advanceMediaTimeline(0.0, 2_000L, 2f)
        assertEquals(4_000.0, elapsedAtTwoTimes, 0.0)
        assertEquals(0.5f, AutomixTransitionPolicy.mediaTimelineProgress(elapsedAtTwoTimes, 8_000L), 0.0001f)

        val elapsedAtHalfSpeed =
            AutomixTransitionPolicy.advanceMediaTimeline(elapsedAtTwoTimes, 2_000L, 0.5f)
        assertEquals(5_000.0, elapsedAtHalfSpeed, 0.0)
        assertEquals(0f, AutomixTransitionPolicy.mediaTimelineProgress(-1.0, 8_000L), 0f)
        assertEquals(1f, AutomixTransitionPolicy.mediaTimelineProgress(5.0, 0L), 0f)
        assertEquals(
            4_000.0,
            AutomixTransitionPolicy.advanceMediaTimeline(4_000.0, -100L, 2f),
            0.0,
        )
    }

    @Test
    fun `phase lock sample gate uses monotonic elapsed time safely`() {
        assertFalse(AutomixTransitionPolicy.shouldSamplePhaseLock(1_063L, 1_000L, 64L))
        assertTrue(AutomixTransitionPolicy.shouldSamplePhaseLock(1_064L, 1_000L, 64L))
        assertFalse(AutomixTransitionPolicy.shouldSamplePhaseLock(999L, 1_000L, 64L))
        assertFalse(AutomixTransitionPolicy.shouldSamplePhaseLock(1_100L, 1_000L, 0L))
    }

    @Test
    fun `invalid playback speeds use a safe default`() {
        assertEquals(1f, AutomixTransitionPolicy.normalizedPlaybackSpeed(Float.NaN), 0f)
        assertEquals(1f, AutomixTransitionPolicy.normalizedPlaybackSpeed(0f), 0f)
        assertEquals(2f, AutomixTransitionPolicy.normalizedPlaybackSpeed(2f), 0f)
    }

    @Test
    fun `crossfade and structure aligned preserve cue values`() {
        assertEquals(8f, AutomixTransitionPolicy.fadeSeconds(AutomixTransitionPolicy.CROSSFADE, 8f)!!, 0.001f)
        assertEquals(1f, AutomixTransitionPolicy.curveGamma(AutomixTransitionPolicy.CROSSFADE, 1f)!!, 0.001f)
        assertEquals(6f, AutomixTransitionPolicy.fadeSeconds(AutomixTransitionPolicy.STRUCTURE_ALIGNED, 6f)!!, 0.001f)
        assertEquals(0.9f, AutomixTransitionPolicy.curveGamma(AutomixTransitionPolicy.STRUCTURE_ALIGNED, 0.9f)!!, 0.001f)
    }

    @Test
    fun `short handover caps duration and raises curve`() {
        assertEquals(4f, AutomixTransitionPolicy.fadeSeconds(AutomixTransitionPolicy.SHORT_HANDOVER, 8f)!!, 0.001f)
        assertEquals(1.20f, AutomixTransitionPolicy.curveGamma(AutomixTransitionPolicy.SHORT_HANDOVER, 0.8f)!!, 0.001f)
        assertEquals(2f, AutomixTransitionPolicy.fadeSeconds(AutomixTransitionPolicy.SHORT_HANDOVER, 2f)!!, 0.001f)
    }

    @Test
    fun `long blend extends duration and keeps curve gentle`() {
        assertEquals(6f, AutomixTransitionPolicy.fadeSeconds(AutomixTransitionPolicy.LONG_BLEND, 4f)!!, 0.001f)
        assertEquals(0.95f, AutomixTransitionPolicy.curveGamma(AutomixTransitionPolicy.LONG_BLEND, 1.3f)!!, 0.001f)
        assertEquals(8f, AutomixTransitionPolicy.fadeSeconds(AutomixTransitionPolicy.LONG_BLEND, 8f)!!, 0.001f)
    }

    @Test
    fun `quick handover caps duration and raises curve`() {
        assertEquals(3f, AutomixTransitionPolicy.fadeSeconds(AutomixTransitionPolicy.QUICK_HANDOVER, 8f)!!, 0.001f)
        assertEquals(1.35f, AutomixTransitionPolicy.curveGamma(AutomixTransitionPolicy.QUICK_HANDOVER, 0.8f)!!, 0.001f)
    }

    @Test
    fun `duration and curve have hard bounds and reject nonfinite targets`() {
        assertEquals(1.5f, AutomixTransitionPolicy.fadeSeconds(AutomixTransitionPolicy.CROSSFADE, -2f)!!, 0.001f)
        assertEquals(12f, AutomixTransitionPolicy.fadeSeconds(AutomixTransitionPolicy.CROSSFADE, 99f)!!, 0.001f)
        assertEquals(0.6f, AutomixTransitionPolicy.curveGamma(AutomixTransitionPolicy.CROSSFADE, 0f)!!, 0.001f)
        assertEquals(1.6f, AutomixTransitionPolicy.curveGamma(AutomixTransitionPolicy.CROSSFADE, 9f)!!, 0.001f)
        assertNull(AutomixTransitionPolicy.fadeSeconds(AutomixTransitionPolicy.CROSSFADE, Float.NaN))
        assertNull(AutomixTransitionPolicy.curveGamma(AutomixTransitionPolicy.CROSSFADE, Float.POSITIVE_INFINITY))
    }

    @Test
    fun `Dart transition fixture is parsed into the exact Media3 cue fields`() {
        val properties = Properties()
        val stream = javaClass.classLoader!!
            .getResourceAsStream("automix_transition_target.properties")!!
        stream.use { properties.load(it) }
        val payload: Map<String, Any?> = properties.stringPropertyNames()
            .associateWith { properties.getProperty(it).toDouble() }

        val target = ParsedAutomixTransitionTarget.fromMap(payload)!!
        assertEquals(202, target.id)
        assertEquals(1.016f, target.multiplier, 0.001f)
        assertEquals(126f, target.bpm!!, 0.001f)
        assertEquals(500L, target.beatOffsetMs)
        assertEquals(800L, target.downbeatOffsetMs)
        assertEquals(60000L, target.dropCueMs)
        assertEquals(3.8f, target.fadeSeconds!!, 0.001f)
        assertEquals(135000L, target.transitionStartMs)
        // Strategy SHORT_HANDOVER enforces its production minimum curve.
        assertEquals(1.20f, target.curveGamma!!, 0.001f)
        assertEquals(0.8f, target.outgoingTrim!!, 0.001f)
        assertEquals(0.9f, target.incomingTrim!!, 0.001f)
    }

    @Test
    fun `malformed target identifiers are rejected`() {
        assertNull(ParsedAutomixTransitionTarget.fromMap(mapOf("bpm" to 120.0)))
    }

}
