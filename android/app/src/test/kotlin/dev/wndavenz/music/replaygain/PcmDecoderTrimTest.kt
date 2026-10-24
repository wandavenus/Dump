package dev.wndavenz.music.replaygain

import android.media.MediaCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PcmDecoderTrimTest {
    @Test
    fun trimsWholePcmFramesBeforeRequestedMediaTimestamp() {
        assertEquals(960, pcmFramesToTrim(
            targetUs = 1_000_000L,
            bufferStartUs = 980_000L,
            sampleRate = 48_000,
            frameCount = 2_048,
        ))
    }

    @Test
    fun roundsPartialSampleUpAndClampsToBuffer() {
        assertEquals(1, pcmFramesToTrim(1L, 0L, 48_000, 100))
        assertEquals(100, pcmFramesToTrim(1_000_000L, 0L, 48_000, 100))
    }

    @Test
    fun leavesBuffersAlreadyAtOrAfterTargetUntouched() {
        assertEquals(0, pcmFramesToTrim(1_000L, 1_000L, 48_000, 100))
        assertEquals(0, pcmFramesToTrim(1_000L, 1_500L, 48_000, 100))
    }

    @Test
    fun invalidRateOrEmptyBufferIsSafe() {
        assertEquals(0, pcmFramesToTrim(1_000L, 0L, 0, 100))
        assertEquals(0, pcmFramesToTrim(1_000L, 0L, 48_000, 0))
    }

    @Test
    fun inputEosDoesNotCompleteUntilOutputEosIsSeen() {
        val state = PcmDecodeEosState()

        state.markInputEosQueued()

        assertTrue(state.inputEosQueued)
        assertFalse(state.outputEosSeen)
        assertFalse(state.isComplete)

        state.observeOutputFlags(0)
        assertFalse(state.isComplete)

        state.observeOutputFlags(MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        assertTrue(state.outputEosSeen)
        assertTrue(state.isComplete)
    }
}
