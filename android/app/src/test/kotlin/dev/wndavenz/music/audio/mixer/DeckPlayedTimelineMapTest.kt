package dev.wndavenz.music.audio.mixer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeckPlayedTimelineMapTest {

    @Test
    fun `maps output bus frames to the source timeline`() {
        val map = DeckPlayedTimelineMap()
        map.append(busStartFrame = 1_000L, frames = 480, sourceStartUs = 2_000_000L, sourceDurationUs = 10_000L)

        assertEquals(null, map.positionAt(999L))
        assertEquals(2_000_000L, map.positionAt(1_000L))
        assertEquals(2_005_000L, map.positionAt(1_240L))
        assertEquals(2_010_000L, map.positionAt(1_480L))
        assertTrue(map.hasPendingData(1_479L))
        assertFalse(map.hasPendingData(1_480L))
    }

    @Test
    fun `keeps last audible anchor after trimming old frames`() {
        val map = DeckPlayedTimelineMap()
        map.append(0L, 480, 1_000_000L, 10_000L)
        map.append(480L, 480, 1_010_000L, 10_000L)

        map.trimBefore(480L)
        assertEquals(1, map.segmentCount())
        assertEquals(1_010_000L, map.positionAt(480L))
        assertEquals(1_015_000L, map.positionAt(720L))
    }

    @Test
    fun `supports a deck that starts after the shared bus`() {
        val map = DeckPlayedTimelineMap()
        map.append(2_000L, 480, 500_000L, 10_000L)

        assertEquals(null, map.positionAt(1_500L))
        assertEquals(500_000L, map.positionAt(2_000L))
    }
}
