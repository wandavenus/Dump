package dev.wndavenz.music.audio.mixer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class BusLimiterTest {

    @Test
    fun `quiet signal passes through unchanged`() {
        val limiter = BusLimiter()
        val buffer = floatArrayOf(0.1f, -0.1f, 0.2f, -0.2f)
        limiter.process(buffer, 2)
        assertEquals(0.1f, buffer[0], 1e-6f)
        assertEquals(-0.2f, buffer[3], 1e-6f)
    }

    @Test
    fun `summed peak is clamped to the ceiling`() {
        val limiter = BusLimiter(ceiling = 0.9f)
        val buffer = floatArrayOf(1.4f, -1.4f, 0.1f, 0.1f)
        limiter.process(buffer, 2)

        assertTrue(abs(buffer[0]) <= 0.9f + 1e-6f)
        assertTrue(abs(buffer[1]) <= 0.9f + 1e-6f)
        assertEquals(0.9f, buffer[0], 1e-6f)
        assertEquals(-0.9f, buffer[1], 1e-6f)
    }

    @Test
    fun `non-finite samples become silence`() {
        val limiter = BusLimiter()
        val buffer = floatArrayOf(Float.NaN, Float.POSITIVE_INFINITY, 0.5f, 0f)
        limiter.process(buffer, 2)
        assertEquals(0f, buffer[0], 0f)
        assertEquals(0f, buffer[1], 0f)
        assertEquals(0.5f, buffer[2], 1e-6f)
    }

    @Test
    fun `gain recovers after a transient`() {
        val limiter = BusLimiter(ceiling = 0.9f, releaseMs = 2f)
        val transient = floatArrayOf(2f, 2f)
        limiter.process(transient, 1)
        assertTrue(transient[0] <= 0.9f)

        val block = floatArrayOf(0.2f, 0.2f)
        repeat(500) {
            block[0] = 0.2f
            block[1] = 0.2f
            limiter.process(block, 1)
        }
        assertEquals(0.2f, block[0], 1e-3f)
    }

    @Test
    fun `reset restores unity gain`() {
        val limiter = BusLimiter(ceiling = 0.5f)
        val loud = floatArrayOf(1f, 1f)
        limiter.process(loud, 1)
        assertEquals(0.5f, loud[0], 1e-6f)

        limiter.reset()
        val quiet = floatArrayOf(0.1f, 0.1f)
        limiter.process(quiet, 1)
        assertEquals(0.1f, quiet[0], 1e-6f)
    }
}
