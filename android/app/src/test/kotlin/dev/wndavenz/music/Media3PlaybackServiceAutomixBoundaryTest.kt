package dev.wndavenz.music

import org.junit.Assert.assertEquals
import org.junit.Test

class Media3PlaybackServiceAutomixBoundaryTest {
    @Test
    fun onlyTheActiveDeckPairCrossesTheNativeBoundary() {
        val first = mapOf<String, Any?>("id" to 101L)
        val second = mapOf<String, Any?>("id" to 202L)
        val malformedThird = mapOf<String, Any?>("id" to 101L, "bpm" to 999.0)

        assertEquals(
            listOf(first, second),
            automixTargetsForActiveDecks(listOf(first, second, malformedThird)),
        )
    }
}
