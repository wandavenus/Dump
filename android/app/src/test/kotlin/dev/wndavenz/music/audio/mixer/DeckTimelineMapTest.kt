package dev.wndavenz.music.audio.mixer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DeckTimelineMapTest {

    @Test
    fun `maps output frames back to the source span that produced them`() {
        val map = DeckTimelineMap(capacitySegments = 8)
        map.append(localFrameStart = 0, frames = 100, sourceStartUs = 1_000_000, sourceDurationUs = 50_000)
        map.append(localFrameStart = 100, frames = 200, sourceStartUs = 1_050_000, sourceDurationUs = 100_000)

        assertEquals(1_000_000L, map.positionAt(0))
        assertEquals(1_025_000L, map.positionAt(50))
        assertEquals(1_050_000L, map.positionAt(100))
        assertEquals(1_100_000L, map.positionAt(200))
    }

    @Test
    fun `stretch ratio is reflected in per-segment interpolation`() {
        val map = DeckTimelineMap(capacitySegments = 8)
        // 20 ms of source stretched into 200 output frames.
        map.append(0, 200, 5_000_000, 20_000)

        assertEquals(5_010_000L, map.positionAt(100))
        assertEquals(5_020_000L, map.positionAt(200))
    }

    @Test
    fun `position clamps to the first and last known source positions`() {
        val map = DeckTimelineMap(capacitySegments = 8)
        map.append(50, 10, 2_000_000, 10_000)

        assertEquals(2_000_000L, map.positionAt(0))
        assertEquals(2_010_000L, map.positionAt(999))
        assertEquals(2_010_000L, map.endPositionUs())
    }

    @Test
    fun `trim keeps the segment covering the playhead`() {
        val map = DeckTimelineMap(capacitySegments = 8)
        map.append(0, 100, 0, 100_000)
        map.append(100, 100, 100_000, 100_000)
        map.append(200, 100, 200_000, 100_000)

        map.trimBefore(150)
        assertEquals(150_000L, map.positionAt(150))
        assertEquals(200_000L, map.positionAt(200))

        map.trimBefore(250)
        assertEquals(250_000L, map.positionAt(250))
        assertEquals(300_000L, map.endPositionUs())
    }

    @Test
    fun `empty map reports no position`() {
        val map = DeckTimelineMap(capacitySegments = 4)
        assertNull(map.positionAt(0))
        assertNull(map.endPositionUs())
        assertEquals(0, map.segmentCount())
    }

    @Test
    fun `fixed segment ring keeps the newest spans when full`() {
        val map = DeckTimelineMap(capacitySegments = 2)
        map.append(0, 10, 0, 10_000)
        map.append(10, 10, 10_000, 10_000)
        map.append(20, 10, 20_000, 10_000)

        assertEquals(2, map.segmentCount())
        assertEquals(25_000L, map.positionAt(25))
        assertEquals(30_000L, map.endPositionUs())
    }
}
