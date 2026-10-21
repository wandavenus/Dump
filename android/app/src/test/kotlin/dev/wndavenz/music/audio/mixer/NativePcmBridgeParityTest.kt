package dev.wndavenz.music.audio.mixer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.nio.ByteBuffer

class NativePcmBridgeParityTest {

    @Test
    fun `native bridge gracefully reports unavailability when lib is unmapped`() {
        assertFalse("Native bridge should report false on JVM host tests without native library", NativePcmBridge.isAvailable)

        val handle = NativePcmBridge.createMixer(48_000, 480)
        assertEquals("Handle should be 0L when native library is unmapped", 0L, handle)

        val res = NativePcmBridge.mix(
            handle = 0L,
            activeMask = 1,
            deck0 = FloatArray(960),
            deck1 = FloatArray(960),
            gains = floatArrayOf(1f, 1f),
            targets = floatArrayOf(1f, 1f),
            output = FloatArray(960),
            frames = 480
        )
        assertFalse("Native mix should return false when handle is 0L", res)
    }

    @Test
    fun `processDeck returns negative status when bridge is unmapped`() {
        val directBuf = ByteBuffer.allocateDirect(1024)
        val status = NativePcmBridge.processDeck(
            handle = 0L,
            input = directBuf,
            offsetBytes = 0,
            inputFrames = 100,
            channels = 2,
            format = PcmSampleFormat.FLOAT_32,
            bigEndian = false,
            output = FloatArray(200)
        )
        assertEquals("Process deck should return negative status on unmapped library", -1, status)
    }
}
