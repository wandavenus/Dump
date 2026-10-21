package dev.wndavenz.music.effects

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Regression tests for the always-on STFT contract in
 * [SignalsmithStretchAudioProcessor].
 *
 * Root cause these lock down: the processor used to run a dry bypass at
 * 1.0x / 0 semitones and splice in the Signalsmith STFT on the first
 * speed/pitch change. Signalsmith has a fixed block+interval input→output
 * latency (~150 ms at the default preset), so the splice replayed already
 * heard audio and dropped the synthesis warm-up interval — audible as a
 * crackle/stutter on the first slider move (and again when returning to
 * unity). The engine must therefore stay engaged from the first sample of
 * every stream; parameter changes only move its targets.
 *
 * The native library is unavailable on the JVM, so these tests inject a
 * recording [StretchNativeBridge]. They assert sequencing (no reset/recreate
 * on parameter changes, process on the very first buffer even at unity,
 * fail-open pass-through on native failure), not signal quality.
 */
@UnstableApi
@Suppress("DEPRECATION")
class SignalsmithStretchAudioProcessorAlwaysOnTest {

    private val inputFormat = AudioProcessor.AudioFormat(48_000, 2, C.ENCODING_PCM_FLOAT)

    @Test
    fun `configure creates one engine and activates the processor`() {
        val bridge = RecordingBridge()
        val processor = SignalsmithStretchAudioProcessor(bridge)

        val applied = processor.configure(inputFormat)

        assertEquals(48_000, applied.sampleRate)
        assertEquals(2, applied.channelCount)
        assertEquals(C.ENCODING_PCM_FLOAT, applied.encoding)
        assertTrue(processor.isActive)
        assertEquals(listOf(1L), bridge.created)
        assertEquals(0, bridge.resets.size)
    }

    @Test
    fun `first buffer at unity goes through the STFT engine, not bypass`() {
        val bridge = RecordingBridge()
        val processor = configured(bridge)

        val output = feed(processor, frames = 512, value = 0.25f)

        assertEquals(1, bridge.processCalls.size)
        assertEquals(512, bridge.processCalls.single().inputFrames)
        assertEquals(512, bridge.processCalls.single().outputFrames)
        // Only the mandatory post-configure flush reset the engine; processing
        // the first buffer did not splice in a bypass or reset anything.
        assertEquals(1, bridge.resets.size)
        assertEquals(512 * 2, output.size)
        assertEquals(0.25f, output.first(), 0f)
    }

    @Test
    fun `repeated speed and pitch drags never reset or recreate the engine`() {
        val bridge = RecordingBridge()
        val processor = configured(bridge)

        val speeds = listOf(1.5f, 1.25f, 0.7f, 2f, 1.02f, 1f)
        for (speed in speeds) {
            processor.setSpeed(speed)
            repeat(3) { feed(processor, frames = 256) }
        }
        for (pitch in listOf(3f, -2.5f, 0.25f, 0f)) {
            processor.setPitchSemitones(pitch)
            repeat(3) { feed(processor, frames = 256) }
        }

        assertEquals(1, bridge.created.size)
        assertEquals(1, bridge.resets.size)
        assertEquals(speeds.size * 3 + 4 * 3, bridge.processCalls.size)
    }

    @Test
    fun `returning to unity keeps the engine engaged`() {
        val bridge = RecordingBridge()
        val processor = configured(bridge)

        repeat(4) { feed(processor, frames = 256) }
        processor.setSpeed(1.5f)
        processor.setPitchSemitones(2f)
        repeat(4) { feed(processor, frames = 256) }
        // Old behaviour: exactly this return to unity switched to raw bypass
        // and reset the engine (nativeReset), producing the second crackle.
        processor.setSpeed(1f)
        processor.setPitchSemitones(0f)
        repeat(4) { feed(processor, frames = 256) }

        assertEquals(1, bridge.created.size)
        assertEquals(1, bridge.resets.size)
        assertEquals(12, bridge.processCalls.size)
    }

    @Test
    fun `flush resets once and the engine re-engages on the next buffer`() {
        val bridge = RecordingBridge()
        val processor = configured(bridge)
        repeat(2) { feed(processor, frames = 256) }
        val processedBeforeFlush = bridge.processCalls.size

        processor.flush()

        // 1 = mandatory post-configure flush, 2 = this explicit flush.
        assertEquals(2, bridge.resets.size)
        assertEquals(1, bridge.created.size)
        feed(processor, frames = 256)
        assertEquals(processedBeforeFlush + 1, bridge.processCalls.size)
    }

    @Test
    fun `native failure fails open to pass-through and is retried`() {
        val bridge = RecordingBridge()
        val processor = configured(bridge)
        bridge.processResult = -1

        val output = feed(processor, frames = 4, value = 0.5f)

        assertArrayEquals(FloatArray(4 * 2) { 0.5f }, output, 0f)
        assertEquals(2, bridge.resets.size)
        assertEquals(1, bridge.processCalls.size)

        bridge.processResult = 0
        feed(processor, frames = 4, value = 0.5f)
        assertEquals(2, bridge.processCalls.size)
        assertEquals(2, bridge.resets.size)
    }

    @Test
    fun `unavailable native library reports NOT_SET without creating a handle`() {
        val bridge = RecordingBridge().apply { isAvailable = false }
        val processor = SignalsmithStretchAudioProcessor(bridge)

        val applied = processor.configure(inputFormat)

        assertEquals(AudioProcessor.AudioFormat.NOT_SET, applied)
        assertFalse(processor.isActive)
        assertTrue(bridge.created.isEmpty())
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    private fun configured(bridge: RecordingBridge): SignalsmithStretchAudioProcessor {
        val processor = SignalsmithStretchAudioProcessor(bridge)
        processor.configure(inputFormat)
        // Media3 publishes the pending format on flush() (BaseAudioProcessor
        // contract): queueInput reads inputAudioFormat, so the same
        // configure→flush sequence the audio sink uses is required here.
        processor.flush()
        return processor
    }

    /** Feeds a uniform stereo block and returns the processor output in floats. */
    private fun feed(
        processor: SignalsmithStretchAudioProcessor,
        frames: Int,
        value: Float = 0f,
    ): FloatArray {
        val bytes = frames * 2 * 4
        // Little-endian like device memory: native code reads/writes raw floats
        // in the platform byte order, not through Java's ByteBuffer order.
        val input = ByteBuffer.allocateDirect(bytes).order(ByteOrder.LITTLE_ENDIAN)
        val inputFloats = input.asFloatBuffer()
        repeat(frames * 2) { inputFloats.put(value) }
        input.position(0).limit(bytes)

        processor.queueInput(input)

        val out = processor.output
        val outputFloats = FloatArray(out.remaining() / 4)
        out.duplicate().order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(outputFloats)
        return outputFloats
    }

    private data class ProcessCall(val handle: Long, val inputFrames: Int, val outputFrames: Int)

    private class RecordingBridge : StretchNativeBridge {
        override var isAvailable: Boolean = true

        private var nextHandle = 1L
        private var channels = 0

        var processResult = 0

        val created = mutableListOf<Long>()
        val destroyed = mutableListOf<Long>()
        val resets = mutableListOf<Long>()
        val pitchUpdates = mutableListOf<Float>()
        val processCalls = mutableListOf<ProcessCall>()
        val flushCalls = mutableListOf<Int>()

        override fun create(sampleRate: Int, channels: Int): Long {
            this.channels = channels
            val handle = nextHandle++
            created += handle
            return handle
        }

        override fun destroy(handle: Long) {
            destroyed += handle
        }

        override fun reset(handle: Long) {
            resets += handle
        }

        override fun setPitchSemitones(handle: Long, semitones: Float) {
            pitchUpdates += semitones
        }

        override fun outputLatencyFrames(handle: Long): Int = 4_320

        override fun process(
            handle: Long,
            input: ByteBuffer,
            inputFrames: Int,
            output: ByteBuffer,
            outputFrames: Int,
        ): Int {
            processCalls += ProcessCall(handle, inputFrames, outputFrames)
            if (processResult != 0) return processResult

            // Explicit little-endian views regardless of buffer order, to
            // mirror raw native float memory layout on device.
            val source = input.duplicate().order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
            val target = output.duplicate().order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
            target.clear()
            val total = outputFrames * channels
            for (index in 0 until total) {
                target.put(if (index < inputFrames * channels) source.get(index) else 0f)
            }
            return 0
        }

        override fun flush(handle: Long, output: ByteBuffer, outputFrames: Int): Int {
            flushCalls += outputFrames
            val target = output.duplicate().order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
            target.clear()
            repeat(outputFrames * channels) { target.put(0f) }
            return 0
        }
    }
}
