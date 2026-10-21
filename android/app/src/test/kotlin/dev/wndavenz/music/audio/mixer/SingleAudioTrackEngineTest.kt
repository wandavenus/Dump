package dev.wndavenz.music.audio.mixer

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.Collections

class SingleAudioTrackEngineTest {

    private val output = FakeSingleOutput()
    private val engine = SingleAudioTrackEngine(output, log = {})

    @After
    fun tearDown() {
        engine.release()
    }

    @Test
    fun `both decks are summed into one shared output`() {
        assertTrue(engine.configureOutput())
        val generationA = engine.addDeck(0)
        val generationB = engine.addDeck(1)

        val frames = 4_800
        appendConstant(0, generationA, frames, 0.25f, sourceDurationUs = 100_000)
        appendConstant(1, generationB, frames, 0.125f, sourceDurationUs = 100_000)
        engine.finishStream(0, generationA)
        engine.finishStream(1, generationB)

        engine.setDeckPlaying(0, true)
        engine.setDeckPlaying(1, true)

        await { output.writtenFrames >= frames.toLong() }
        val mixed = output.snapshot()

        assertEquals(frames, mixed.frames)
        for (index in 0 until mixed.frames * 2) {
            assertEquals("sample $index", 0.375f, mixed.pcm[index], 1e-4f)
        }
        assertEquals(1, output.configureCount)
    }

    @Test
    fun `deck volume scales only that deck`() {
        assertTrue(engine.configureOutput())
        val generationA = engine.addDeck(0)
        val generationB = engine.addDeck(1)

        appendConstant(0, generationA, 2_400, 0.4f, sourceDurationUs = 50_000)
        appendConstant(1, generationB, 2_400, 0.4f, sourceDurationUs = 50_000)
        engine.finishStream(0, generationA)
        engine.finishStream(1, generationB)
        engine.setDeckVolume(0, 0.5f)
        engine.setDeckVolume(1, 0f)
        engine.setDeckPlaying(0, true)
        engine.setDeckPlaying(1, true)

        await { output.writtenFrames >= 2_400L }
        val mixed = output.snapshot()
        for (index in 0 until mixed.frames * 2) {
            assertEquals(0.2f, mixed.pcm[index], 1e-4f)
        }
    }

    @Test
    fun `position follows played output and EOS reports the source end`() {
        assertTrue(engine.configureOutput())
        val generation = engine.addDeck(0)
        val frames = 4_800
        appendConstant(0, generation, frames, 0.1f, sourceDurationUs = 100_000)
        engine.finishStream(0, generation)
        engine.setDeckPlaying(0, true)

        await { output.writtenFrames >= frames.toLong() && engine.deckIsEnded(0) }

        assertTrue(engine.deckIsEnded(0))
        assertFalse(engine.deckHasPendingData(0))
        assertEquals(100_000L, engine.deckPositionUs(0, sourceEnded = true))
    }

    @Test
    fun `resetting one deck does not disturb the other`() {
        assertTrue(engine.configureOutput())
        val generationA = engine.addDeck(0)
        val generationB = engine.addDeck(1)
        appendConstant(0, generationA, 2_400, 0.2f, sourceDurationUs = 50_000)
        engine.finishStream(0, generationA)
        engine.setDeckPlaying(0, true)

        await { output.writtenFrames >= 2_400L && engine.deckIsEnded(0) }
        val positionBefore = engine.deckPositionUs(0, sourceEnded = true)

        val newGenerationB = engine.resetDeck(1)
        assertTrue(newGenerationB > generationB)
        assertEquals(positionBefore, engine.deckPositionUs(0, sourceEnded = true))
        assertFalse(engine.deckHasPendingData(0))

        appendConstant(1, newGenerationB, 480, 0.3f, sourceDurationUs = 10_000)
        assertEquals(
            SingleAudioTrackEngine.DEFAULT_RING_FRAMES - 480,
            engine.deckFreeFrames(1, newGenerationB),
        )
        engine.finishStream(1, newGenerationB)
    }

    @Test
    fun `a deck that has not produced data does not stall the audible deck`() {
        assertTrue(engine.configureOutput())
        val generationA = engine.addDeck(0)
        engine.addDeck(1)
        appendConstant(0, generationA, 2_400, 0.2f, sourceDurationUs = 50_000)
        engine.finishStream(0, generationA)

        engine.setDeckPlaying(0, true)
        engine.setDeckPlaying(1, true)

        await { output.writtenFrames >= 2_400L }
        assertTrue(output.snapshot().frames >= 2_400)
    }

    @Test
    fun `bus configuration is idempotent`() {
        assertTrue(engine.configureOutput())
        assertTrue(engine.configureOutput())
        assertEquals(1, output.configureCount)
    }

    private fun appendConstant(
        slot: Int,
        generation: Long,
        frames: Int,
        value: Float,
        sourceDurationUs: Long,
    ) {
        val pcm = FloatArray(frames * 2) { value }
        var offset = 0
        while (offset < frames) {
            val accepted = engine.appendFrames(
                slot = slot,
                generation = generation,
                pcm = pcm,
                offsetFrames = offset,
                frames = frames - offset,
                sourceStartUs = sourceDurationUs * offset / frames,
                sourceDurationUs = sourceDurationUs * (frames - offset) / frames,
            )
            if (accepted <= 0) fail("append rejected")
            offset += accepted
        }
    }

    private fun await(timeoutMs: Long = 5_000L, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (!condition()) {
            if (System.currentTimeMillis() > deadline) {
                fail("condition not met within ${timeoutMs}ms")
            }
            Thread.sleep(2L)
        }
    }

    private class MixedSnapshot(val pcm: FloatArray, val frames: Int)

    private class FakeSingleOutput : SharedAudioOutput {
        override var listener: SharedAudioOutput.Listener? = null

        @Volatile
        var writtenFrames: Long = 0L

        @Volatile
        var released: Boolean = false

        @Volatile
        var configureCount: Int = 0

        private val blocks = Collections.synchronizedList(ArrayList<FloatArray>())

        override fun configure(sampleRate: Int, channelCount: Int): Boolean {
            configureCount++
            return true
        }

        override fun isConfigured(): Boolean = true

        override fun play() = Unit

        override fun pause() = Unit

        override fun handleBuffer(
            pcm: FloatArray,
            frameCount: Int,
            presentationTimeUs: Long,
        ): Boolean {
            blocks.add(pcm.copyOf(frameCount * 2))
            writtenFrames += frameCount
            return true
        }

        override fun currentPositionUs(): Long =
            writtenFrames * 1_000_000L / SingleAudioTrackEngine.BUS_SAMPLE_RATE

        override fun hasPendingData(): Boolean = false

        override fun bufferSizeUs(): Long = 0L

        override fun audioSessionId(): Int = 0

        override fun flush() = Unit

        override fun release() {
            released = true
        }

        fun snapshot(): MixedSnapshot {
            val copy = synchronized(blocks) { ArrayList(blocks) }
            val totalFrames = copy.sumOf { it.size / 2 }
            val pcm = FloatArray(totalFrames * 2)
            var offset = 0
            for (block in copy) {
                System.arraycopy(block, 0, pcm, offset, block.size)
                offset += block.size
            }
            return MixedSnapshot(pcm, totalFrames)
        }
    }
}
