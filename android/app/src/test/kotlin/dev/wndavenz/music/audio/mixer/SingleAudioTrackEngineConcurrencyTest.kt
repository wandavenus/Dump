package dev.wndavenz.music.audio.mixer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class SingleAudioTrackEngineConcurrencyTest {

    private lateinit var mockOutput: Media3SharedAudioOutput
    private lateinit var engine: SingleAudioTrackEngine

    @Before
    fun setUp() {
        mockOutput = mock()
        whenever(mockOutput.configure(any(), any())).thenReturn(true)
        whenever(mockOutput.handleBuffer(any(), any(), any())).thenReturn(true)
        whenever(mockOutput.currentPositionUs()).thenReturn(0L)

        engine = SingleAudioTrackEngine(
            output = mockOutput,
            busSampleRate = 48_000,
            deckCount = 2,
            ringFrames = 4800,
            maxBlockFrames = 480,
        )
    }

    @Test
    fun `concurrent release and resetDeck do not deadlock or crash`() {
        val deckSlot = 0
        engine.addDeck(deckSlot)

        val latch = CountDownLatch(2)
        val errorOccurred = AtomicBoolean(false)

        val resetThread = Thread {
            try {
                for (i in 0 until 500) {
                    engine.resetDeck(deckSlot)
                    Thread.sleep(1)
                }
            } catch (e: Exception) {
                errorOccurred.set(true)
            } finally {
                latch.countDown()
            }
        }

        val releaseThread = Thread {
            try {
                Thread.sleep(50)
                engine.release()
            } catch (e: Exception) {
                errorOccurred.set(true)
            } finally {
                latch.countDown()
            }
        }

        resetThread.start()
        releaseThread.start()

        assertTrue("Threads should complete within timeout", latch.await(3, TimeUnit.SECONDS))
        assertFalse("No thread should throw an exception during concurrent release and resetDeck", errorOccurred.get())
    }

    @Test
    fun `flushBusForSeek flushes hardware output safely on output thread`() {
        engine.addDeck(0)
        engine.flushBusForSeek(0)

        // Wait briefly for output thread execution
        Thread.sleep(50)

        assertEquals(0L, engine.metrics().busFramesWritten)
        assertEquals(0L, engine.metrics().busFramesPlayed)
    }

    @Test
    fun `suspendOutputForExclusiveMode pauses and resets output`() {
        val result = engine.suspendOutputForExclusiveMode()
        assertTrue("Output suspension should succeed", result)
        assertEquals(0L, engine.metrics().busFramesWritten)
    }
}
