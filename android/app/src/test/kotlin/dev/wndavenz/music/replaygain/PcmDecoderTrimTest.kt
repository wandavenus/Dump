package dev.wndavenz.music.replaygain

import org.junit.Assert.assertEquals
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
}
