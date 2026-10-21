package dev.wndavenz.music.audio.mixer

import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.C
import androidx.media3.exoplayer.audio.AudioSink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import java.nio.ByteBuffer

class DeckAudioSinkTest {

    private lateinit var mockOutput: Media3SharedAudioOutput
    private lateinit var engine: SingleAudioTrackEngine
    private lateinit var sink: DeckAudioSink

    @Before
    fun setUp() {
        mockOutput = mock()
        whenever(mockOutput.configure(any(), any())).thenReturn(true)
        whenever(mockOutput.handleBuffer(any(), any(), any())).thenReturn(true)
        whenever(mockOutput.currentPositionUs()).thenReturn(1_000_000L)

        engine = SingleAudioTrackEngine(
            output = mockOutput,
            busSampleRate = 48_000,
            deckCount = 2,
            ringFrames = 4800,
            maxBlockFrames = 480,
        )
        sink = DeckAudioSink(
            engine = engine,
            output = mockOutput,
            slot = 0,
            processors = emptyList(),
        )
    }

    @Test
    fun `configure succeeds for linear stereo float PCM`() {
        val config = AudioSink.AudioSinkConfig.Builder(
            Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_FLOAT)
                .setSampleRate(48_000)
                .setChannelCount(2)
                .build()
        ).build()

        sink.configure(config)
        assertTrue(sink.supportsFormat(config.format))
    }

    @Test
    fun `handleBuffer backpressure retries with identical buffer positioning`() {
        // Configure sink with 48kHz stereo float
        val config = AudioSink.AudioSinkConfig.Builder(
            Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_FLOAT)
                .setSampleRate(48_000)
                .setChannelCount(2)
                .build()
        ).build()
        sink.configure(config)

        // Fill engine deck 0 ring completely by appending frames
        val bigPcm = FloatArray(4800 * 2)
        engine.appendFrames(0, 1L, bigPcm, 0, 4800, 0L, 100_000L)

        // Offer a buffer when the ring has no space
        val input = ByteBuffer.allocateDirect(100 * 2 * 4)
        val initialPos = input.position()
        val initialLimit = input.limit()

        val accepted = sink.handleBuffer(input, 0L, 1)
        assertFalse("handleBuffer should return false when ring cannot store block", accepted)
        assertEquals("Buffer position must remain unchanged on rejection", initialPos, input.position())
        assertEquals("Buffer limit must remain unchanged on rejection", initialLimit, input.limit())
    }

    @Test
    fun `EOS draining updates deck EOS state when pending frames drain`() {
        val config = AudioSink.AudioSinkConfig.Builder(
            Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_FLOAT)
                .setSampleRate(48_000)
                .setChannelCount(2)
                .build()
        ).build()
        sink.configure(config)

        sink.playToEndOfStream()
        assertTrue("isEnded should return true after EOS finishes and ring is drained", sink.isEnded())
    }
}
