package dev.wndavenz.music.audio.mixer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

class SincResamplerTest {

    @Test
    fun `equal rates are a bit-exact copy`() {
        val resampler = SincResampler(48_000, 48_000)
        val input = FloatArray(8) { it.toFloat() / 8f }
        val output = FloatArray(8)
        val frames = resampler.resample(input, 4, output)

        assertEquals(4, frames)
        assertTrue(resampler.isBypass)
        assertEquals(input.toList(), output.toList())
    }

    @Test
    fun `44 point 1 to 48 kHz produces the expected number of frames`() {
        val resampler = SincResampler(44_100, 48_000)
        val inputFrames = 4_410
        val input = FloatArray(inputFrames * 2) { 0.25f }
        val output = FloatArray(resampler.outputFramesUpperBound(inputFrames) * 2)

        val frames = resampler.resample(input, inputFrames, output)

        // The final half-window is intentionally carried into the next block,
        // so allow a small shortfall.
        assertTrue("frames=$frames", frames in 4_780..4_810)
    }

    @Test
    fun `DC level is preserved by the normalised kernel`() {
        val resampler = SincResampler(44_100, 48_000)
        val inputFrames = 8_192
        val input = FloatArray(inputFrames * 2) { 0.25f }
        val output = FloatArray(resampler.outputFramesUpperBound(inputFrames) * 2)

        val frames = resampler.resample(input, inputFrames, output)

        assertTrue(frames > 8_000)
        for (frame in 256 until frames) {
            assertEquals(0.25f, output[frame * 2], 1e-3f)
            assertEquals(0.25f, output[frame * 2 + 1], 1e-3f)
        }
    }

    @Test
    fun `block boundaries do not change the filtered signal`() {
        val totalFrames = 4_800
        val input = FloatArray(totalFrames * 2) { index ->
            val frame = index / 2
            sin(2.0 * PI * 441.0 * frame / 44_100.0).toFloat()
        }

        val single = SincResampler(44_100, 48_000)
        val singleOut = FloatArray(single.outputFramesUpperBound(totalFrames) * 2)
        val singleFrames = single.resample(input, totalFrames, singleOut)

        val split = SincResampler(44_100, 48_000)
        val splitOut = FloatArray(split.outputFramesUpperBound(totalFrames) * 2)
        var splitFrames = 0
        var offset = 0
        val chunk = 1_200
        while (offset < totalFrames) {
            val frames = minOf(chunk, totalFrames - offset)
            val scratch = FloatArray(split.outputFramesUpperBound(frames) * 2)
            val produced = split.resample(
                input.copyOfRange(offset * 2, (offset + frames) * 2),
                frames,
                scratch,
            )
            System.arraycopy(
                scratch,
                0,
                splitOut,
                splitFrames * 2,
                produced * 2,
            )
            splitFrames += produced
            offset += frames
        }

        val compareFrames = minOf(singleFrames, splitFrames, 4_000)
        assertTrue(compareFrames > 3_000)
        for (index in 0 until compareFrames * 2) {
            assertEquals("sample $index", singleOut[index], splitOut[index], 1e-5f)
        }
    }

    @Test
    fun `downsampling rejects content above the output Nyquist`() {
        val inputRate = 96_000
        val outputRate = 48_000
        val frames = 9_600
        val input = FloatArray(frames * 2) { index ->
            val frame = index / 2
            sin(2.0 * PI * 30_000.0 * frame / inputRate).toFloat()
        }
        val resampler = SincResampler(inputRate, outputRate)
        val output = FloatArray(resampler.outputFramesUpperBound(frames) * 2)
        val produced = resampler.resample(input, frames, output)

        var sumSquares = 0.0
        var count = 0
        for (frame in 512 until produced - 512) {
            val sample = output[frame * 2]
            sumSquares += sample.toDouble() * sample
            count++
        }
        val rms = kotlin.math.sqrt(sumSquares / count)
        // A 1.0-amplitude tone would have RMS ~0.707 without filtering; the
        // anti-alias low-pass must push the aliased 18 kHz image far below it.
        assertTrue("rms=$rms", rms < 0.02)
    }

    @Test
    fun `reset clears the filter history`() {
        val resampler = SincResampler(44_100, 48_000)
        val input = FloatArray(2_048 * 2) { 0.5f }
        val output = FloatArray(resampler.outputFramesUpperBound(2_048) * 2)
        resampler.resample(input, 2_048, output)

        resampler.reset()
        val restarted = FloatArray(resampler.outputFramesUpperBound(512) * 2)
        val frames = resampler.resample(input, 512, restarted)
        assertTrue(frames > 0)
    }
}
