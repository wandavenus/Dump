package dev.wndavenz.music.automix

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The phase resync runs inside the 16 ms fade tick, so its math has to be exact
 * and boring: these tests pin the sign convention (incoming ahead → slow it
 * down), the dead zone, the clamp, and the refusal cases.
 */
class AutomixPhaseLockTest {

    /** One beat at 120 BPM. */
    private val beat120 = 60_000.0 / 120.0

    @Test
    fun lockedDecksReportZeroPhaseError() {
        val error = AutomixPhaseLock.phaseErrorMs(
            outgoingPositionMs = 1_000.0,
            outgoingPhaseOffsetMs = 0.0,
            outgoingBeatMs = beat120,
            incomingPositionMs = 5_000.0,
            incomingPhaseOffsetMs = 0.0,
            incomingBeatMs = beat120,
        )
        assertNotNull(error)
        assertEquals(0.0, error!!, 0.0001)
    }

    @Test
    fun incomingAheadNeedsANegativeNudge() {
        // Outgoing sits exactly on its beat; the incoming deck is a quarter beat
        // (125 ms at 120 BPM) past its own.
        val error = AutomixPhaseLock.phaseErrorMs(
            outgoingPositionMs = 1_000.0,
            outgoingPhaseOffsetMs = 0.0,
            outgoingBeatMs = beat120,
            incomingPositionMs = 5_125.0,
            incomingPhaseOffsetMs = 0.0,
            incomingBeatMs = beat120,
        )
        assertNotNull(error)
        assertEquals(125.0, error!!, 0.001)

        // Closing 125 ms over 5 s would need -2.5 %, far beyond the clamp, so the
        // correction saturates at MAX_NUDGE and stays negative.
        val nudge = AutomixPhaseLock.nudgeFor(errorMs = 125.0, remainingMs = 5_000.0)
        assertEquals(-AutomixPhaseLock.MAX_NUDGE, nudge, 0.0001f)
    }

    @Test
    fun aSmallErrorClosesOverTheRemainingFadeInaudibly() {
        val nudge = AutomixPhaseLock.nudgeFor(errorMs = 10.0, remainingMs = 4_000.0)
        // -10 ms over 4 s = -0.25 %, well inside the clamp.
        assertEquals(-0.0025f, nudge, 0.0001f)
        assertTrue(abs(nudge) <= AutomixPhaseLock.MAX_NUDGE)
    }

    @Test
    fun incomingBehindIsSpedUp() {
        val nudge = AutomixPhaseLock.nudgeFor(errorMs = -10.0, remainingMs = 4_000.0)
        assertEquals(0.0025f, nudge, 0.0001f)
    }

    @Test
    fun measurementNoiseAndANearlyFinishedFadeAreLeftAlone() {
        // Inside the dead zone: no correction at all.
        assertEquals(0f, AutomixPhaseLock.nudgeFor(errorMs = 3.0, remainingMs = 4_000.0), 0f)
        assertEquals(0f, AutomixPhaseLock.nudgeFor(errorMs = -5.9, remainingMs = 4_000.0), 0f)
        // Too little fade left to work with.
        assertEquals(0f, AutomixPhaseLock.nudgeFor(errorMs = 200.0, remainingMs = 250.0), 0f)
        // Nonsense input never produces a correction.
        assertEquals(
            0f,
            AutomixPhaseLock.nudgeFor(errorMs = Double.NaN, remainingMs = 4_000.0),
            0f,
        )
        assertEquals(
            0f,
            AutomixPhaseLock.nudgeFor(errorMs = 50.0, remainingMs = Double.NaN),
            0f,
        )
        assertEquals(
            0f,
            AutomixPhaseLock.nudgeFor(errorMs = 50.0, remainingMs = 4_000.0, maxNudge = 0f),
            0f,
        )
    }

    @Test
    fun theCorrectionNeverExceedsTheClamp() {
        val faster = AutomixPhaseLock.nudgeFor(errorMs = -500.0, remainingMs = 1_000.0)
        val slower = AutomixPhaseLock.nudgeFor(errorMs = 500.0, remainingMs = 1_000.0)
        assertTrue(faster <= AutomixPhaseLock.MAX_NUDGE)
        assertTrue(slower >= -AutomixPhaseLock.MAX_NUDGE)
    }

    @Test
    fun halfTimePairsCompareLikeForLike() {
        // Outgoing 60 BPM (1000 ms beats), incoming 120 BPM (500 ms beats): an
        // incoming deck exactly a half beat past its grid is also a quarter of the
        // outgoing beat past its own, so the error is 250 ms in the incoming
        // timeline rather than a nearly-full-beat mismatch.
        val error = AutomixPhaseLock.phaseErrorMs(
            outgoingPositionMs = 0.0,
            outgoingPhaseOffsetMs = 0.0,
            outgoingBeatMs = 1_000.0,
            incomingPositionMs = 250.0,
            incomingPhaseOffsetMs = 0.0,
            incomingBeatMs = 500.0,
        )
        assertNotNull(error)
        assertEquals(250.0, error!!, 0.001)
    }

    @Test
    fun aWrapAroundErrorIsMeasuredTheShortWay() {
        // Incoming is 10 ms BEHIND its grid (one beat minus 10 ms), which must
        // read as -10 ms instead of a nearly-full beat ahead.
        val error = AutomixPhaseLock.phaseErrorMs(
            outgoingPositionMs = 0.0,
            outgoingPhaseOffsetMs = 0.0,
            outgoingBeatMs = beat120,
            incomingPositionMs = 490.0,
            incomingPhaseOffsetMs = 0.0,
            incomingBeatMs = beat120,
        )
        assertNotNull(error)
        assertEquals(-10.0, error!!, 0.001)
    }

    @Test
    fun unusableGridsAreRefusedInsteadOfGuessed() {
        assertNull(
            AutomixPhaseLock.phaseErrorMs(
                outgoingPositionMs = Double.NaN,
                outgoingPhaseOffsetMs = 0.0,
                outgoingBeatMs = beat120,
                incomingPositionMs = 0.0,
                incomingPhaseOffsetMs = 0.0,
                incomingBeatMs = beat120,
            ),
        )
        assertNull(
            AutomixPhaseLock.phaseErrorMs(
                outgoingPositionMs = 0.0,
                outgoingPhaseOffsetMs = 0.0,
                // No grid at all on the outgoing deck.
                outgoingBeatMs = 0.0,
                incomingPositionMs = 0.0,
                incomingPhaseOffsetMs = 0.0,
                incomingBeatMs = beat120,
            ),
        )
        // Beats shorter than 240 ms mean a tempo above 250 BPM: never trusted.
        assertNull(
            AutomixPhaseLock.phaseErrorMs(
                outgoingPositionMs = 0.0,
                outgoingPhaseOffsetMs = 0.0,
                outgoingBeatMs = beat120,
                incomingPositionMs = 0.0,
                incomingPhaseOffsetMs = 0.0,
                incomingBeatMs = 100.0,
            ),
        )
    }
}
