package dev.wndavenz.music.automix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AutomixTransitionPolicyTest {
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
}
