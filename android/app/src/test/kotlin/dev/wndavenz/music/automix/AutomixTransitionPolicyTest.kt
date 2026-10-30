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
        assertFalse(AutomixTransitionPolicy.isValidEarlyHandover(120_000L, 180_000L, 0L))
    }

    @Test
    fun `relative early handover resolves against the actual Media3 duration`() {
        // Dart analyzed 180 s and selected 135 s, a 45 s lead. Media3 reports
        // 210 s, so the accepted start must move to 165 s instead of reusing
        // the stale absolute position (which would be 75 s before EOF).
        val resolved = AutomixTransitionPolicy.resolveEarlyHandoverStartMs(
            transitionLeadMs = 45_000L,
            fallbackTransitionStartMs = 135_000L,
            outgoingDurationMs = 210_000L,
        )
        assertEquals(165_000L, resolved)
        assertFalse(
            AutomixTransitionPolicy.isValidEarlyHandover(135_000L, 210_000L, 3_800L),
        )
        assertTrue(
            AutomixTransitionPolicy.isValidEarlyHandover(resolved, 210_000L, 3_800L),
        )
        assertEquals(
            125_000L,
            AutomixTransitionPolicy.resolveEarlyHandoverStartMs(
                transitionLeadMs = 45_000L,
                fallbackTransitionStartMs = 135_000L,
                outgoingDurationMs = 170_000L,
            ),
        )
        assertNull(
            AutomixTransitionPolicy.resolveEarlyHandoverStartMs(
                transitionLeadMs = 66_000L,
                fallbackTransitionStartMs = 135_000L,
                outgoingDurationMs = 210_000L,
            ),
        )
    }

    @Test
    fun `bounded fade lead keeps phrase snapping from stretching the fade`() {
        // 3 s planned fade, start snapped 1.5 s early at 60 BPM (1 s beat):
        // allow half a beat of tolerance, not the remaining 3.5 s to EOF.
        assertEquals(
            3_500L,
            AutomixTransitionPolicy.boundedFadeLeadMs(
                fadeStartMs = 116_500L,
                outgoingDurationMs = 120_000L,
                plannedFadeMs = 3_000L,
                beatMs = 1_000.0,
            ),
        )
        // A snap close to EOF can still never extend past the track end.
        assertEquals(
            2_000L,
            AutomixTransitionPolicy.boundedFadeLeadMs(118_000L, 120_000L, 3_000L, 1_000.0),
        )
        // Without a trustworthy grid there is no tolerance to add.
        assertEquals(
            3_000L,
            AutomixTransitionPolicy.boundedFadeLeadMs(100_000L, 120_000L, 3_000L, null),
        )
    }

    @Test
    fun `beat phase lock requires two planner-approved tempo grids`() {
        assertTrue(AutomixTransitionPolicy.isBeatMatchedPair(120f, 124f))
        assertFalse(AutomixTransitionPolicy.isBeatMatchedPair(null, 124f))
        assertFalse(AutomixTransitionPolicy.isBeatMatchedPair(120f, null))
        assertFalse(AutomixTransitionPolicy.isBeatMatchedPair(49f, 124f))
        assertFalse(AutomixTransitionPolicy.isBeatMatchedPair(120f, Float.NaN))
        // Octave-folded pairs may use a regular fade, but raw-period phase
        // correction is unsafe unless the measured grids are comparable.
        assertFalse(AutomixTransitionPolicy.isBeatMatchedPair(60f, 120f))
        assertFalse(AutomixTransitionPolicy.isBeatMatchedPair(120f, 60f))
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
    fun `fade start snaps to the largest phrase boundary within tolerance`() {
        // 120 BPM: beat 500 ms, 64/32/16/4-beat grids = 32/16/8/2 s.
        assertEquals(
            32_000L,
            AutomixTransitionPolicy.phraseAlignedStartMs(32_050L, 500.0, 0.0, 0.0),
        )
        assertEquals(
            16_000L,
            AutomixTransitionPolicy.phraseAlignedStartMs(16_300L, 500.0, 0.0, 0.0),
        )
        assertEquals(
            8_000L,
            AutomixTransitionPolicy.phraseAlignedStartMs(8_150L, 500.0, 0.0, 0.0),
        )
        assertEquals(
            2_000L,
            AutomixTransitionPolicy.phraseAlignedStartMs(2_100L, 500.0, 0.0, 0.0),
        )
    }

    @Test
    fun `phrase snap honours the analyzed phrase phase`() {
        // Downbeat phase 800 ms shifts every grid boundary by 800 ms.
        assertEquals(
            16_800L,
            AutomixTransitionPolicy.phraseAlignedStartMs(16_900L, 500.0, 800.0, 800.0),
        )
        // No boundary at/before the ideal start (grid starts at 800 ms) falls
        // through without inventing a negative start.
        assertEquals(
            100L,
            AutomixTransitionPolicy.phraseAlignedStartMs(100L, 500.0, null, 800.0),
        )
    }

    @Test
    fun `phrase snap falls back to the legacy beat snap without a phrase phase`() {
        assertEquals(
            10_200L,
            AutomixTransitionPolicy.phraseAlignedStartMs(10_350L, 500.0, 200.0, null),
        )
        assertEquals(
            10_350L,
            AutomixTransitionPolicy.phraseAlignedStartMs(10_350L, 500.0, null, null),
        )
        assertEquals(
            10_350L,
            AutomixTransitionPolicy.phraseAlignedStartMs(10_350L, Double.NaN, 0.0, 0.0),
        )
        assertEquals(
            10_350L,
            AutomixTransitionPolicy.phraseAlignedStartMs(10_350L, 0.0, 0.0, 0.0),
        )
    }

    @Test
    fun `phrase snap uses the analyzed metre instead of a fixed four-beat bar`() {
        // 120 BPM, 3/4: bar = 1500 ms, four bars = 6 s, two bars = 3 s.
        assertEquals(
            6_000L,
            AutomixTransitionPolicy.phraseAlignedStartMs(
                6_100L, 500.0, 0.0, 0.0, meter = 3,
            ),
        )
        assertEquals(
            3_000L,
            AutomixTransitionPolicy.phraseAlignedStartMs(
                3_200L, 500.0, 0.0, 0.0, meter = 3,
            ),
        )
        // A 4/4 grid would have snapped this to 8 s, which is not a boundary
        // of a 3-beat bar and drifts by one beat per bar.
        assertEquals(
            6_000L,
            AutomixTransitionPolicy.phraseAlignedStartMs(
                7_900L, 500.0, 0.0, 0.0, meter = 3,
            ),
        )
        // Compound 6/8 heard at a dotted-quarter pulse publishes metre 2: bar
        // = 1 s at 120 BPM, four bars = 4 s, two bars = 2 s.
        assertEquals(
            4_000L,
            AutomixTransitionPolicy.phraseAlignedStartMs(
                4_100L, 500.0, 0.0, 0.0, meter = 2,
            ),
        )
        assertEquals(
            2_000L,
            AutomixTransitionPolicy.phraseAlignedStartMs(
                2_300L, 500.0, 0.0, 0.0, meter = 2,
            ),
        )
        // Out-of-contract metre falls back to the 4/4 prior.
        assertEquals(
            10_000L,
            AutomixTransitionPolicy.phraseAlignedStartMs(
                10_100L, 500.0, 0.0, 0.0, meter = 5,
            ),
        )
    }

    @Test
    fun `target metre parses only supported bar lengths`() {
        assertEquals(4, ParsedAutomixTransitionTarget.fromMap(mapOf("id" to 1.0))!!.meter)
        assertEquals(
            3,
            ParsedAutomixTransitionTarget.fromMap(
                mapOf("id" to 1.0, "meter" to 3.0),
            )!!.meter,
        )
        assertEquals(
            6,
            ParsedAutomixTransitionTarget.fromMap(
                mapOf("id" to 1.0, "meter" to 6.0),
            )!!.meter,
        )
        assertEquals(
            2,
            ParsedAutomixTransitionTarget.fromMap(
                mapOf("id" to 1.0, "meter" to 2.0),
            )!!.meter,
        )
        for (raw in listOf(5.0, 7.0, 4.5, Double.NaN)) {
            assertEquals(
                4,
                ParsedAutomixTransitionTarget.fromMap(
                    mapOf("id" to 1.0, "meter" to raw),
                )!!.meter,
                "meter=$raw",
            )
        }
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
        assertEquals(45000L, target.transitionLeadMs)
        // Strategy SHORT_HANDOVER enforces its production minimum curve.
        assertEquals(1.20f, target.curveGamma!!, 0.001f)
        assertEquals(0.8f, target.outgoingTrim!!, 0.001f)
        assertEquals(0.9f, target.incomingTrim!!, 0.001f)
        assertEquals(-1f, target.outgoingPitchSemitones, 0.001f)
    }

    @Test
    fun `malformed target identifiers are rejected`() {
        assertNull(ParsedAutomixTransitionTarget.fromMap(mapOf("bpm" to 120.0)))
    }

    @Test
    fun `outgoing pitch shift defaults to zero and is clamped to one semitone`() {
        val missing = ParsedAutomixTransitionTarget.fromMap(mapOf("id" to 1.0))!!
        assertEquals(0f, missing.outgoingPitchSemitones, 0.001f)
        val clamped = ParsedAutomixTransitionTarget.fromMap(
            mapOf("id" to 1.0, "pitchSemitonesOutgoing" to 5.0),
        )!!
        assertEquals(1f, clamped.outgoingPitchSemitones, 0.001f)
        val nan = ParsedAutomixTransitionTarget.fromMap(
            mapOf("id" to 1.0, "pitchSemitonesOutgoing" to Double.NaN),
        )!!
        assertEquals(0f, nan.outgoingPitchSemitones, 0.001f)
    }
}
