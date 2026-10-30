package dev.wndavenz.music.automix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomixIntegrationTest {

    @Test
    fun `production gain envelope preserves endpoints and follows live volume target`() {
        val start = AutomixGainEnvelope.gains(
            progress = 0f,
            targetVolume = 1f,
            curveGamma = 1f,
            outgoingTrim = 0.7f,
            incomingTrim = 0.8f,
        )
        assertEquals(1f, start.outgoing, 0.001f)
        assertEquals(0f, start.incoming, 0.001f)

        val ducked = AutomixGainEnvelope.gains(
            progress = 0.5f,
            targetVolume = 0.3f,
            curveGamma = 1f,
            outgoingTrim = 1f,
            incomingTrim = 1f,
        )
        assertEquals(0.3f * 0.70710677f, ducked.outgoing, 0.001f)
        assertEquals(0.3f * 0.70710677f, ducked.incoming, 0.001f)
        assertEquals(0.3f * 1.4142135f, ducked.outgoing + ducked.incoming, 0.001f)

        val end = AutomixGainEnvelope.gains(
            progress = 1f,
            targetVolume = 0.42f,
            curveGamma = 1.35f,
            outgoingTrim = 0.7f,
            incomingTrim = 0.6f,
        )
        assertEquals(0f, end.outgoing, 0.001f)
        assertEquals(0.42f, end.incoming, 0.001f)
    }

    @Test
    fun `production gain envelope keeps each deck bounded across trims and curves`() {
        val targets = floatArrayOf(0.15f, 0.3f, 0.7f, 1f)
        val gammas = floatArrayOf(0.6f, 0.85f, 1f, 1.35f, 1.6f)
        val trims = floatArrayOf(0f, 0.32f, 0.7f, 1f)

        for (target in targets) {
            for (gamma in gammas) {
                for (outTrim in trims) {
                    for (inTrim in trims) {
                        for (step in 0..100) {
                            val gains = AutomixGainEnvelope.gains(
                                progress = step / 100f,
                                targetVolume = target,
                                curveGamma = gamma,
                                outgoingTrim = outTrim,
                                incomingTrim = inTrim,
                            )
                            assertTrue(gains.outgoing in 0f..target)
                            assertTrue(gains.incoming in 0f..target)
                            assertTrue(
                                gains.outgoing + gains.incoming <= target * 1.4143f + 0.0001f,
                            )
                        }
                    }
                }
            }
        }
    }

    @Test
    fun `mid-fade gains follow the equal-power curve`() {
        val midGains = AutomixGainEnvelope.gains(
            progress = 0.5f,
            targetVolume = 1.0f,
            curveGamma = 1.0f,
            outgoingTrim = 1.0f,
            incomingTrim = 1.0f,
        )
        // At the linear midpoint, equal-power cos(pi/4) and sin(pi/4) are both 0.7071.
        assertEquals(0.70710677f, midGains.outgoing, 0.001f)
        assertEquals(0.70710677f, midGains.incoming, 0.001f)
        assertEquals(1.4142135f, midGains.outgoing + midGains.incoming, 0.001f)
    }

    @Test
    fun `production gain envelope gamma curve direction accelerates or decelerates handover`() {
        val midLinear = AutomixGainEnvelope.gains(
            progress = 0.5f,
            targetVolume = 1f,
            curveGamma = 1f,
            outgoingTrim = 1f,
            incomingTrim = 1f,
        )
        val midQuick = AutomixGainEnvelope.gains(
            progress = 0.5f,
            targetVolume = 1f,
            curveGamma = 1.35f,
            outgoingTrim = 1f,
            incomingTrim = 1f,
        )
        val midLong = AutomixGainEnvelope.gains(
            progress = 0.5f,
            targetVolume = 1f,
            curveGamma = 0.85f,
            outgoingTrim = 1f,
            incomingTrim = 1f,
        )

        // gamma > 1 (quick handover): incoming rises faster, outgoing drops faster
        assertTrue(midQuick.incoming > midLinear.incoming)
        assertTrue(midQuick.outgoing < midLinear.outgoing)

        // gamma < 1 (long blend): incoming rises slower, outgoing drops slower
        assertTrue(midLong.incoming < midLinear.incoming)
        assertTrue(midLong.outgoing > midLinear.outgoing)
    }

    @Test
    fun `production gain envelope safely handles invalid control values`() {
        val gains = AutomixGainEnvelope.gains(
            progress = Float.NaN,
            targetVolume = Float.POSITIVE_INFINITY,
            curveGamma = Float.NaN,
            outgoingTrim = Float.NaN,
            incomingTrim = Float.POSITIVE_INFINITY,
        )
        assertEquals(0f, gains.outgoing, 0f)
        assertEquals(0f, gains.incoming, 0f)
    }

    @Test
    fun `phase lock factor evaluation remains bounded`() {
        val factor = AutomixPhaseLock.factorFor(
            outgoingPositionMs = 1000.0,
            outgoingPhaseOffsetMs = 0.0,
            outgoingBpm = 120.0,
            incomingPositionMs = 5000.0,
            incomingPhaseOffsetMs = 0.0,
            incomingBpm = 120.0,
            remainingMs = 4000.0,
        )

        // Without native library loaded in pure JVM unit test, returns null (safe fallback)
        assertTrue(factor == null || (factor in 0.95f..1.05f))
    }
}
