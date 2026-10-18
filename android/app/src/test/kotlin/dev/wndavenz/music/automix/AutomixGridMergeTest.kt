package dev.wndavenz.music.automix

import dev.wndavenz.music.effects.AutomixLiveBeatState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomixGridMergeTest {
    private val beatGate = 0.30f
    private val downbeatGate = 0.30f

    private fun live(
        bpm: Float = 120f,
        phaseMs: Double = 250.0,
        confidence: Float = 0.9f,
        downbeatMs: Double = 1800.0,
        downbeatConfidence: Float = 0.6f,
    ) = AutomixLiveBeatState(
        bpm = bpm,
        phaseElapsedMs = phaseMs,
        confidence = confidence,
        downbeatElapsedMs = downbeatMs,
        downbeatConfidence = downbeatConfidence,
    )

    private fun merge(
        live: AutomixLiveBeatState?,
        offlineBpm: Float? = null,
        offlinePositionMs: Double? = null,
        offlineBeatOffsetMs: Double? = null,
        offlineDownbeatOffsetMs: Double? = null,
    ) = AutomixGridMerge.mergeDeck(
        live = live,
        liveBeatMinConfidence = beatGate,
        liveDownbeatMinConfidence = downbeatGate,
        offlineBpm = offlineBpm,
        offlinePositionMs = offlinePositionMs,
        offlineBeatOffsetMs = offlineBeatOffsetMs,
        offlineDownbeatOffsetMs = offlineDownbeatOffsetMs,
    )

    @Test
    fun `offline grid passes through when the live estimate is weak`() {
        val grid = merge(
            live = live(confidence = 0.2f),
            offlineBpm = 128f,
            offlinePositionMs = 10_000.0,
            offlineBeatOffsetMs = 500.0,
            offlineDownbeatOffsetMs = 0.0,
        )!!
        assertEquals(128.0, grid.bpm, 1e-9)
        assertEquals(10_000.0, grid.beatPositionMs, 1e-9)
        assertEquals(500.0, grid.beatOffsetMs, 1e-9)
        assertEquals(10_000.0, grid.downbeatPositionMs!!, 1e-9)
        assertEquals(0.0, grid.downbeatOffsetMs, 1e-9)
        assertFalse(grid.live)
    }

    @Test
    fun `live grid is used alone when the analyzer has no beat grid`() {
        val grid = merge(live = live())!!
        assertEquals(120.0, grid.bpm, 1e-9)
        assertEquals(250.0, grid.beatPositionMs, 1e-9)
        assertEquals(0.0, grid.beatOffsetMs, 1e-9)
        assertEquals(1800.0, grid.downbeatPositionMs!!, 1e-9)
        assertEquals(0.0, grid.downbeatOffsetMs, 1e-9)
        assertTrue(grid.live)
    }

    @Test
    fun `no usable source yields no grid`() {
        assertNull(merge(live = null))
        assertNull(merge(live = live(confidence = 0.1f), offlineBpm = 0f))
        assertNull(
            merge(
                live = null,
                offlineBpm = 128f,
                offlinePositionMs = null,
                offlineBeatOffsetMs = 0.0,
            ),
        )
    }

    @Test
    fun `agreeing tempos blend by weight and the live phase wins`() {
        // 120 vs 122 bpm: |ln| = 0.0165 < 0.04. Phases: live 260/500 = 0.52,
        // offline (10_280 - 0) mod 500 = 280 -> 0.56; distance 0.04.
        val grid = merge(
            live = live(phaseMs = 260.0, confidence = 0.9f),
            offlineBpm = 122f,
            offlinePositionMs = 10_280.0,
            offlineBeatOffsetMs = 0.0,
            offlineDownbeatOffsetMs = 0.0,
        )!!
        val expectedBpm = (120.0 * 0.9 + 122.0 * 0.8) / 1.7
        assertEquals(expectedBpm, grid.bpm, 1e-9)
        assertEquals(260.0, grid.beatPositionMs, 1e-9)
        assertEquals(0.0, grid.beatOffsetMs, 1e-9)
        assertTrue(grid.live)
    }

    @Test
    fun `octave-mismatched tempos never blend and move the phase with the winner`() {
        // Live 60 vs analyzer 120: ln ratio 0.69 is way over tolerance, so the
        // chosen tempo must keep its own phase space.
        val liveWins = merge(
            live = live(bpm = 60f, phaseMs = 100.0, confidence = 0.9f),
            offlineBpm = 120f,
            offlinePositionMs = 10_000.0,
            offlineBeatOffsetMs = 0.0,
        )!!
        assertEquals(60.0, liveWins.bpm, 1e-9)
        assertEquals(100.0, liveWins.beatPositionMs, 1e-9)
        assertEquals(0.0, liveWins.beatOffsetMs, 1e-9)
        assertTrue(liveWins.live)

        val offlineWins = merge(
            live = live(bpm = 60f, phaseMs = 100.0, confidence = 0.4f),
            offlineBpm = 120f,
            offlinePositionMs = 10_000.0,
            offlineBeatOffsetMs = 0.0,
        )!!
        assertEquals(120.0, offlineWins.bpm, 1e-9)
        assertEquals(10_000.0, offlineWins.beatPositionMs, 1e-9)
        assertFalse(offlineWins.live)
    }

    @Test
    fun `disagreeing phases resolve to the heavier source`() {
        // Both agree on tempo (120). Live phase 100/500 = 0.2 vs offline
        // 400/500 = 0.8: circular distance 0.4 > 0.25, so weights decide.
        val offlineWins = merge(
            live = live(phaseMs = 100.0, confidence = 0.5f),
            offlineBpm = 120f,
            offlinePositionMs = 10_400.0,
            offlineBeatOffsetMs = 0.0,
        )!!
        assertEquals(10_400.0, offlineWins.beatPositionMs, 1e-9)
        assertEquals(0.0, offlineWins.beatOffsetMs, 1e-9)
        assertFalse(offlineWins.live)

        val liveWins = merge(
            live = live(phaseMs = 100.0, confidence = 0.9f),
            offlineBpm = 120f,
            offlinePositionMs = 10_400.0,
            offlineBeatOffsetMs = 0.0,
        )!!
        assertEquals(100.0, liveWins.beatPositionMs, 1e-9)
        assertTrue(liveWins.live)
    }

    @Test
    fun `live downbeat needs confidence before it drives phrase lock`() {
        val fromLive = merge(
            live = live(downbeatMs = 1800.0, downbeatConfidence = 0.5f),
            offlineBpm = 120f,
            offlinePositionMs = 10_000.0,
            offlineBeatOffsetMs = 0.0,
            offlineDownbeatOffsetMs = 2_000.0,
        )!!
        assertEquals(1800.0, fromLive.downbeatPositionMs!!, 1e-9)
        assertEquals(0.0, fromLive.downbeatOffsetMs, 1e-9)

        val fromOffline = merge(
            live = live(downbeatMs = 1800.0, downbeatConfidence = 0.1f),
            offlineBpm = 120f,
            offlinePositionMs = 10_000.0,
            offlineBeatOffsetMs = 0.0,
            offlineDownbeatOffsetMs = 2_000.0,
        )!!
        assertEquals(10_000.0, fromOffline.downbeatPositionMs!!, 1e-9)
        assertEquals(2_000.0, fromOffline.downbeatOffsetMs, 1e-9)
    }

    @Test
    fun `a rejected live beat source drags its downbeat down with it`() {
        // Live beats disagree with the analyzer and lose the weight decision,
        // so the live downbeat is not allowed to drive phrase lock either.
        val grid = merge(
            live = live(phaseMs = 100.0, confidence = 0.5f, downbeatConfidence = 0.9f),
            offlineBpm = 120f,
            offlinePositionMs = 10_400.0,
            offlineBeatOffsetMs = 0.0,
            offlineDownbeatOffsetMs = 2_000.0,
        )!!
        assertEquals(10_000.0, grid.downbeatPositionMs!!, 1e-9)
        assertEquals(2_000.0, grid.downbeatOffsetMs, 1e-9)
    }

    @Test
    fun `downbeat stays absent when neither source is confident`() {
        val grid = merge(
            live = live(downbeatConfidence = 0.05f),
            offlineBpm = 120f,
            offlinePositionMs = 10_000.0,
            offlineBeatOffsetMs = 0.0,
        )!!
        assertNull(grid.downbeatPositionMs)
    }

    @Test
    fun `wrap-around phases still count as agreeing`() {
        // Live 490/500 = 0.98, offline 10/500 = 0.02: circular distance 0.04.
        val grid = merge(
            live = live(phaseMs = 490.0, confidence = 0.4f),
            offlineBpm = 120f,
            offlinePositionMs = 10_010.0,
            offlineBeatOffsetMs = 0.0,
        )!!
        assertEquals(490.0, grid.beatPositionMs, 1e-9)
        assertTrue(grid.live)
    }
}
