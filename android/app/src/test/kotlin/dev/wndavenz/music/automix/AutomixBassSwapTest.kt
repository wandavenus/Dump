package dev.wndavenz.music.automix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomixBassSwapTest {
    @Test
    fun `swap starts on the first beat boundary after the soft floor`() {
        val window = AutomixBassSwap.window(
            fadeStartPositionMs = 100_000.0,
            fadeDurationMs = 8_000.0,
            beatMs = 500.0,
            beatOffsetMs = 0.0,
        )!!

        // 35 % of an 8 s fade is 102 800 ms; the next 120 BPM beat is 103 000 ms.
        assertEquals(103_000.0, window.startMs, 0.001)
        assertEquals(500.0, window.durationMs, 0.001)
    }

    @Test
    fun `swap honours the analyzed beat phase`() {
        val window = AutomixBassSwap.window(
            fadeStartPositionMs = 100_000.0,
            fadeDurationMs = 8_000.0,
            beatMs = 500.0,
            beatOffsetMs = 200.0,
        )!!

        assertEquals(103_200.0, window.startMs, 0.001)
    }

    @Test
    fun `swap transfer is capped at one beat and at the fade fraction`() {
        val oneBeat = AutomixBassSwap.window(
            fadeStartPositionMs = 0.0,
            fadeDurationMs = 8_000.0,
            beatMs = 2_000.0,
            beatOffsetMs = 0.0,
        )!!
        // A 2 s beat is shorter than 35 % of the fade, so the transfer is one beat.
        assertEquals(2_000.0, oneBeat.durationMs, 0.001)

        val shortFade = AutomixBassSwap.window(
            fadeStartPositionMs = 0.0,
            fadeDurationMs = 2_000.0,
            beatMs = 1_000.0,
            beatOffsetMs = 0.0,
        )!!
        // 35 % of a 2 s fade (700 ms) is shorter than the 1 s beat.
        assertEquals(700.0, shortFade.durationMs, 0.001)
    }

    @Test
    fun `missing grid keeps a bounded fallback window`() {
        val window = AutomixBassSwap.window(
            fadeStartPositionMs = 5_000.0,
            fadeDurationMs = 10_000.0,
            beatMs = null,
            beatOffsetMs = null,
        )!!
        // 35 % into the fade; fallback transfer is 20 % of the fade.
        assertEquals(8_500.0, window.startMs, 0.001)
        assertEquals(2_000.0, window.durationMs, 0.001)
    }

    @Test
    fun `invalid geometry is rejected`() {
        assertNull(AutomixBassSwap.window(-1.0, 8_000.0, 500.0, 0.0))
        assertNull(AutomixBassSwap.window(0.0, 0.0, 500.0, 0.0))
        assertNull(AutomixBassSwap.window(Double.NaN, 8_000.0, 500.0, 0.0))
        assertNull(AutomixBassSwap.window(0.0, Double.POSITIVE_INFINITY, 500.0, 0.0))
    }

    @Test
    fun `gains cross over smoothly and never sum above one`() {
        val start = AutomixBassSwap.gains(0f)
        assertEquals(1f, start.outgoing, 0.0001f)
        assertEquals(0f, start.incoming, 0.0001f)

        val middle = AutomixBassSwap.gains(0.5f)
        assertEquals(0.5f, middle.outgoing, 0.0001f)
        assertEquals(0.5f, middle.incoming, 0.0001f)
        assertEquals(1f, middle.outgoing + middle.incoming, 0.0001f)

        val end = AutomixBassSwap.gains(1f)
        assertEquals(0f, end.outgoing, 0.0001f)
        assertEquals(1f, end.incoming, 0.0001f)

        // Clamped outside [0, 1] instead of overshooting.
        assertEquals(1f, AutomixBassSwap.gains(-1f).outgoing, 0.0001f)
        assertEquals(1f, AutomixBassSwap.gains(2f).incoming, 0.0001f)
        assertEquals(1f, AutomixBassSwap.gains(Float.NaN).outgoing, 0.0001f)
    }

    @Test
    fun `progress is derived from the outgoing source timeline`() {
        val window = AutomixBassSwap.Window(startMs = 10_000.0, durationMs = 500.0)
        assertEquals(0f, AutomixBassSwap.progress(window, 9_000.0), 0.0001f)
        assertEquals(0f, AutomixBassSwap.progress(window, 10_000.0), 0.0001f)
        assertEquals(0.5f, AutomixBassSwap.progress(window, 10_250.0), 0.0001f)
        assertEquals(1f, AutomixBassSwap.progress(window, 11_000.0), 0.0001f)
        assertEquals(0f, AutomixBassSwap.progress(window, Double.NaN), 0.0001f)
    }

    @Test
    fun `window stays inside the fade when the beat grid is coarse`() {
        val window = AutomixBassSwap.window(
            fadeStartPositionMs = 0.0,
            fadeDurationMs = 4_000.0,
            beatMs = 4_000.0,
            beatOffsetMs = 0.0,
        )!!
        // 35 % of 4 s is 1 400 ms; a 4 s beat would put the boundary at 4 000 ms,
        // which leaves no room for the transfer, so the soft floor is used.
        assertEquals(1_400.0, window.startMs, 0.001)
        assertEquals(1_400.0, window.durationMs, 0.001)
        assertTrue(window.endMs <= 4_000.0)
    }
}
