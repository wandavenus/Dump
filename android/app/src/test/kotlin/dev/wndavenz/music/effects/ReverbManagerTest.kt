package dev.wndavenz.music.effects

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ReverbManagerTest {

    @Test
    fun `setReverb clamps finite intensity to supported range`() {
        val manager = ReverbManager()

        manager.setReverb(enabled = true, intensity = 2f)

        assertEquals(1f, manager.reverbIntensity)
    }

    @Test
    fun `setReverb rejects non-finite intensity before it reaches DSP`() {
        val manager = ReverbManager()

        manager.setReverb(enabled = true, intensity = Float.NaN)

        assertFalse(manager.reverbIntensity.isNaN())
        assertEquals(0f, manager.reverbIntensity)
    }
}
