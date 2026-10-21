package dev.wndavenz.music.audio.mixer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AudioTrackLifecycleRegistryTest {

    @Before
    fun resetRegistry() {
        AudioTrackLifecycleRegistry.resetForTests()
    }

    @Test
    fun `counts concurrent tracks across distinct physical sink owners`() {
        val primarySink = Any()
        val standbySink = Any()

        val createdPrimary = AudioTrackLifecycleRegistry.onInitialized(
            owner = primarySink,
            ownerLabel = "primary",
            encoding = 2,
            sampleRate = 48_000,
            channelConfig = 12,
            bufferSize = 96_000,
        )
        val createdStandby = AudioTrackLifecycleRegistry.onInitialized(
            owner = standbySink,
            ownerLabel = "standby",
            encoding = 2,
            sampleRate = 48_000,
            channelConfig = 12,
            bufferSize = 96_000,
        )

        val whileOverlapping = AudioTrackLifecycleRegistry.snapshot()
        assertTrue(createdPrimary.contains("HW_AUDIO_TRACK_CREATED"))
        assertTrue(createdStandby.contains("HW_AUDIO_TRACK_CREATED"))
        assertEquals(2, whileOverlapping.activeCount)
        assertEquals(2L, whileOverlapping.totalCreated)
        assertEquals(2, whileOverlapping.peakConcurrent)

        AudioTrackLifecycleRegistry.onReleased(primarySink, "primary")
        val oneLeft = AudioTrackLifecycleRegistry.snapshot()
        assertEquals(1, oneLeft.activeCount)
        assertEquals(1L, oneLeft.totalReleased)

        AudioTrackLifecycleRegistry.onReleased(standbySink, "standby")
        val finished = AudioTrackLifecycleRegistry.snapshot()
        assertEquals(0, finished.activeCount)
        assertEquals(2L, finished.totalReleased)
        assertEquals(2, finished.peakConcurrent)
        assertEquals(0L, finished.unmatchedReleaseCallbacks)
    }

    @Test
    fun `unmatched release is logged without making active count negative`() {
        val event = AudioTrackLifecycleRegistry.onReleased(Any(), "unknown")
        val snapshot = AudioTrackLifecycleRegistry.snapshot()

        assertTrue(event.contains("HW_AUDIO_TRACK_RELEASE_UNMATCHED"))
        assertEquals(0, snapshot.activeCount)
        assertEquals(0L, snapshot.totalReleased)
        assertEquals(1L, snapshot.unmatchedReleaseCallbacks)
    }
}
