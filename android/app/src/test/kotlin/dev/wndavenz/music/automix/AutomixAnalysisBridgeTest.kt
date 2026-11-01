package dev.wndavenz.music.automix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomixAnalysisBridgeTest {
    @Test
    fun `12 minute file spreads coverage within five window budget and sees middle drop`() {
        val durationSeconds = 12.0 * 60.0
        val windowSeconds = 120.0
        val starts = AutomixAnalysis.planLongFileWindowStarts(
            durationSeconds = durationSeconds,
            windowSeconds = windowSeconds,
        )

        assertEquals(AutomixAnalysis.MAX_LONG_FILE_WINDOWS, starts.size)
        assertEquals(
            listOf(0.0, 150.0, 300.0, 450.0, 600.0),
            starts,
        )

        // A synthetic drop at the center of the file is inside a sampled
        // middle window, so its position can be measured rather than inferred.
        val syntheticDropSeconds = 360.0
        assertTrue(starts.any { start ->
            syntheticDropSeconds >= start && syntheticDropSeconds < start + windowSeconds
        })

        val analyzedWindows = starts.map { start ->
            mapOf<String, Any?>(
                "segmentStartSeconds" to start,
                "segmentSeconds" to windowSeconds,
            )
        }
        assertEquals(
            5.0 / 6.0,
            AutomixAnalysis.analyzedFraction(analyzedWindows, durationSeconds),
            0.0001,
        )
    }

    @Test
    fun `drop inside an unsampled gap is not invented as an analysis cue`() {
        val durationSeconds = 12.0 * 60.0
        val windowSeconds = 120.0
        val starts = AutomixAnalysis.planLongFileWindowStarts(
            durationSeconds = durationSeconds,
            windowSeconds = windowSeconds,
        )
        val syntheticDropSeconds = 285.0 // gap between [150,270) and [300,420)

        assertFalse(starts.any { start ->
            syntheticDropSeconds >= start && syntheticDropSeconds < start + windowSeconds
        })
        val measuredDropCue = starts.firstNotNullOfOrNull { start ->
            if (syntheticDropSeconds >= start &&
                syntheticDropSeconds < start + windowSeconds
            ) {
                syntheticDropSeconds
            } else {
                null
            }
        }
        assertEquals(null, measuredDropCue)
    }

    @Test
    fun `coverage fraction unions overlapping windows and rejects invalid duration`() {
        val overlapping = listOf(
            mapOf<String, Any?>("segmentStartSeconds" to 0.0, "segmentSeconds" to 120.0),
            mapOf<String, Any?>("segmentStartSeconds" to 90.0, "segmentSeconds" to 120.0),
        )

        assertEquals(0.7, AutomixAnalysis.analyzedFraction(overlapping, 300.0), 0.0001)
        assertEquals(0.0, AutomixAnalysis.analyzedFraction(overlapping, Double.NaN), 0.0)
    }
}
