package dev.wndavenz.music.audio.mixer

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DeckAudioPipelineTest {

    @Test
    fun `pcm16 stereo is converted and resampled onto the 48 kHz bus`() {
        val pipeline = DeckAudioPipeline(emptyList(), busSampleRate = 48_000)
        pipeline.configure(
            Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_16BIT)
                .setSampleRate(44_100)
                .setChannelCount(2)
                .build(),
        )

        val frames = 4_410
        val bytes = ByteArray(frames * 4)
        for (frame in 0 until frames) {
            val base = frame * 4
            bytes[base] = 0x00
            bytes[base + 1] = 0x20 // +0.25
            bytes[base + 2] = 0x00
            bytes[base + 3] = 0xE0.toByte() // -0.25
        }

        val blocks = pipeline.process(
            bytes = bytes,
            offsetBytes = 0,
            byteCount = bytes.size,
            presentationTimeUs = 1_000_000L,
        )

        assertEquals(1, blocks.size)
        val block = blocks[0]
        assertTrue("frames=${block.frames}", block.frames in 4_700..4_810)
        assertEquals(1_000_000L, block.sourceStartUs)
        assertEquals(100_000L, block.sourceDurationUs)

        for (frame in 100 until block.frames) {
            assertEquals(0.25f, block.pcm[frame * 2], 0.01f)
            assertEquals(-0.25f, block.pcm[frame * 2 + 1], 0.01f)
        }
    }

    @Test
    fun `mono input is duplicated to the stereo bus`() {
        val pipeline = DeckAudioPipeline(emptyList(), busSampleRate = 48_000)
        pipeline.configure(
            Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_16BIT)
                .setSampleRate(48_000)
                .setChannelCount(1)
                .build(),
        )

        val frames = 480
        val bytes = ByteArray(frames * 2)
        for (frame in 0 until frames) {
            bytes[frame * 2] = 0x00
            bytes[frame * 2 + 1] = 0x10 // 4096 -> 0.125
        }

        val blocks = pipeline.process(bytes, 0, bytes.size, 0L)
        assertEquals(1, blocks.size)
        assertEquals(frames, blocks[0].frames)
        for (frame in 0 until frames) {
            assertEquals(0.125f, blocks[0].pcm[frame * 2], 1e-5f)
            assertEquals(0.125f, blocks[0].pcm[frame * 2 + 1], 1e-5f)
        }
    }

    @Test
    fun `unsupported encodings are rejected`() {
        val pipeline = DeckAudioPipeline(emptyList(), busSampleRate = 48_000)
        try {
            pipeline.configure(
                Format.Builder()
                    .setSampleMimeType(MimeTypes.AUDIO_AAC)
                    .setSampleRate(48_000)
                    .setChannelCount(2)
                    .setPcmEncoding(C.ENCODING_INVALID)
                    .build(),
            )
            throw AssertionError("configure should have failed")
        } catch (_: IllegalArgumentException) {
            // Expected: encoded formats never reach a deck pipeline.
        }
    }
}
