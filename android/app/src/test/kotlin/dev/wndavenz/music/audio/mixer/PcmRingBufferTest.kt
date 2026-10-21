package dev.wndavenz.music.audio.mixer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PcmRingBufferTest {

    @Test
    fun `writes and reads interleaved stereo frames in order`() {
        val ring = PcmRingBuffer(8)
        val source = FloatArray(8) { it.toFloat() }

        assertEquals(4, ring.write(source, 0, 4))
        assertEquals(4, ring.availableToRead)
        assertEquals(4, ring.availableToWrite)

        val out = FloatArray(8)
        assertEquals(4, ring.read(out, 0, 4))
        assertArrayEquals(source.copyOfRange(0, 8), out, 0f)
    }

    @Test
    fun `wraps around the backing array without reordering`() {
        val ring = PcmRingBuffer(4)
        val first = FloatArray(6) { it.toFloat() }
        val second = FloatArray(6) { (it + 100).toFloat() }

        assertEquals(3, ring.write(first, 0, 3))
        val out = FloatArray(6)
        assertEquals(3, ring.read(out, 0, 3))
        assertArrayEquals(first.copyOfRange(0, 6), out, 0f)

        assertEquals(3, ring.write(second, 0, 3))
        assertEquals(3, ring.read(out, 0, 3))
        assertArrayEquals(second.copyOfRange(0, 6), out, 0f)
    }

    @Test
    fun `reports backpressure instead of dropping frames`() {
        val ring = PcmRingBuffer(4)
        val source = FloatArray(10) { it.toFloat() }

        assertEquals(4, ring.write(source, 0, 5))
        assertEquals(0, ring.write(source, 0, 1))
        assertEquals(4, ring.availableToRead)

        val out = FloatArray(8)
        assertEquals(4, ring.read(out, 0, 4))
        assertArrayEquals(source.copyOfRange(0, 8), out, 0f)
        assertEquals(4, ring.availableToWrite)
    }

    @Test
    fun `partial reads preserve the remaining frames`() {
        val ring = PcmRingBuffer(8)
        val source = FloatArray(8) { (it * 2).toFloat() }
        assertEquals(4, ring.write(source, 0, 4))

        val out = FloatArray(4)
        assertEquals(2, ring.read(out, 0, 2))
        assertArrayEquals(source.copyOfRange(0, 4), out, 0f)
        assertEquals(2, ring.availableToRead)

        assertEquals(2, ring.read(out, 0, 2))
        assertArrayEquals(source.copyOfRange(4, 8), out, 0f)
        assertEquals(0, ring.availableToRead)
    }

    @Test
    fun `read honours the destination offset`() {
        val ring = PcmRingBuffer(4)
        val source = floatArrayOf(1f, 2f, 3f, 4f)
        ring.write(source, 0, 2)

        val out = FloatArray(8)
        assertEquals(2, ring.read(out, 2, 2))
        assertArrayEquals(floatArrayOf(0f, 0f, 0f, 0f, 1f, 2f, 3f, 4f), out, 0f)
    }

    @Test
    fun `total frames written tracks absolute progress`() {
        val ring = PcmRingBuffer(4)
        val source = FloatArray(8)
        ring.write(source, 0, 2)
        assertTrue(ring.totalFramesWritten == 2L)
        ring.read(FloatArray(4), 0, 2)
        ring.write(source, 0, 2)
        assertEquals(4L, ring.totalFramesWritten)
    }
}
