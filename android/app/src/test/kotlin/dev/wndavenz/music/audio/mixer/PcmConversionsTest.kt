package dev.wndavenz.music.audio.mixer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class PcmConversionsTest {

    @Test
    fun `decodes signed 16-bit little endian samples`() {
        val bytes = byteArrayOf(
            0x00, 0x10, // 4096
            0x00, 0xF0.toByte(), // -4096 -> 0xF000
        )
        val out = PcmConversions.readFloats(
            bytes,
            0,
            frames = 2,
            channelCount = 1,
            format = PcmSampleFormat.SIGNED_16,
            bigEndian = false,
        )
        assertEquals(0.125f, out[0], 1e-6f)
        assertEquals(-0.125f, out[1], 1e-6f)
    }

    @Test
    fun `decodes signed 24-bit samples`() {
        val bytes = byteArrayOf(
            0x00, 0x00, 0x40, // +0.5 * 2^23
            0x00, 0x00, 0xC0.toByte(), // -0.5 * 2^23
        )
        val out = PcmConversions.readFloats(
            bytes,
            0,
            frames = 2,
            channelCount = 1,
            format = PcmSampleFormat.SIGNED_24,
            bigEndian = false,
        )
        assertEquals(0.5f, out[0], 1e-6f)
        assertEquals(-0.5f, out[1], 1e-6f)
    }

    @Test
    fun `decodes 32-bit float samples`() {
        val bytes = ByteArray(8)
        val buffer = java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        buffer.putFloat(0.25f)
        buffer.putFloat(-0.75f)

        val out = PcmConversions.readFloats(
            bytes,
            0,
            frames = 2,
            channelCount = 1,
            format = PcmSampleFormat.FLOAT_32,
            bigEndian = false,
        )
        assertEquals(0.25f, out[0], 1e-6f)
        assertEquals(-0.75f, out[1], 1e-6f)
    }

    @Test
    fun `decodes unsigned 8-bit samples around the midpoint`() {
        val bytes = byteArrayOf(0x80.toByte(), 0xC0.toByte(), 0x40)
        val out = PcmConversions.readFloats(
            bytes,
            0,
            frames = 3,
            channelCount = 1,
            format = PcmSampleFormat.UNSIGNED_8,
            bigEndian = false,
        )
        assertEquals(0f, out[0], 1e-6f)
        assertEquals(0.5f, out[1], 1e-6f)
        assertEquals(-0.5f, out[2], 1e-6f)
    }

    @Test
    fun `mono is duplicated to stereo`() {
        val stereo = PcmConversions.toStereo(floatArrayOf(0.1f, 0.2f), 2, 1)
        assertArrayEquals(floatArrayOf(0.1f, 0.1f, 0.2f, 0.2f), stereo, 0f)
    }

    @Test
    fun `stereo is copied unchanged`() {
        val input = floatArrayOf(0.1f, -0.1f, 0.2f, -0.2f)
        val stereo = PcmConversions.toStereo(input, 2, 2)
        assertArrayEquals(input, stereo, 0f)
    }

    @Test
    fun `five point one folds centre and surrounds at minus three dB`() {
        // FL, FR, FC, LFE, BL, BR — only the centre is non-zero.
        val input = floatArrayOf(0f, 0f, 1f, 0f, 0f, 0f)
        val stereo = PcmConversions.toStereo(input, 1, 6)
        assertEquals(0.70710677f, stereo[0], 1e-6f)
        assertEquals(0.70710677f, stereo[1], 1e-6f)
    }
}
