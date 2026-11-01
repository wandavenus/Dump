package dev.wndavenz.music.replaygain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class PcmDecoderLifecycleTest {
    private class FakeCodec {
        var releaseCount = 0
    }

    private class FakeExtractor {
        var releaseCount = 0

        fun readTrackMetadata(): Nothing =
            throw IllegalStateException("track metadata failed")
    }

    @Test
    fun releasesExtractorWhenPreDecodeMetadataThrows() {
        val extractor = FakeExtractor()

        val failure = runCatching {
            withPcmResource(extractor, { it.releaseCount++ }) { resource ->
                resource.readTrackMetadata()
            }
        }.exceptionOrNull()

        assertTrue(failure is IllegalStateException)
        assertEquals(1, extractor.releaseCount)
    }

    @Test
    fun releasesCreatedCodecWhenConfigureFails() {
        val codec = FakeCodec()
        var startCalled = false

        val result = createAndStartCodecOrReleaseOnFailure(
            create = { codec },
            configure = { throw IllegalStateException("configure failed") },
            start = { startCalled = true },
            release = { it.releaseCount++ },
        )

        assertNull(result)
        assertEquals(1, codec.releaseCount)
        assertFalse(startCalled)
    }

    @Test
    fun releasesCreatedCodecWhenStartFails() {
        val codec = FakeCodec()

        val result = createAndStartCodecOrReleaseOnFailure(
            create = { codec },
            configure = {},
            start = { throw IllegalStateException("start failed") },
            release = { it.releaseCount++ },
        )

        assertNull(result)
        assertEquals(1, codec.releaseCount)
    }

    @Test
    fun doesNotReleaseWhenFactoryFailsBeforeReturningACodec() {
        var releaseCalled = false

        val result = createAndStartCodecOrReleaseOnFailure<FakeCodec>(
            create = { throw IllegalArgumentException("no compatible codec") },
            configure = {},
            start = {},
            release = { releaseCalled = true },
        )

        assertNull(result)
        assertFalse(releaseCalled)
    }

    @Test
    fun keepsSuccessfullyStartedCodecForDecodeOwnership() {
        val codec = FakeCodec()
        var startCalled = false

        val result = createAndStartCodecOrReleaseOnFailure(
            create = { codec },
            configure = {},
            start = { startCalled = true },
            release = { it.releaseCount++ },
        )

        assertSame(codec, result)
        assertTrue(startCalled)
        assertEquals(0, codec.releaseCount)
    }
}
