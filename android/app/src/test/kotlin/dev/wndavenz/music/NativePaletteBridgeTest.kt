package dev.wndavenz.music

import android.os.Handler
import androidx.palette.graphics.Palette
import java.util.ArrayDeque
import java.util.concurrent.ExecutorService
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.doAnswer
import org.mockito.kotlin.doThrow
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import java.util.concurrent.RejectedExecutionException

/**
 * JVM contract and selection tests for [NativePaletteBridge].
 *
 * The bridge receives a synchronous test Handler and extractor so these tests
 * never depend on Android's main Looper, filesystem, or MediaMetadataRetriever.
 * Palette role selection still uses real AndroidX [Palette.Swatch] instances.
 *
 * Test groups:
 *   A. MethodChannel validation/version contract
 *   B. Native per-song request coalescing and five-color output
 *   C. Queue rejection and transient null-artwork result
 *   D. Dispose lifecycle and exactly-once completion
 *   E. OKLab clustering and dominant-neutral correction
 */
class NativePaletteBridgeTest {

    private class RecordingResult : io.flutter.plugin.common.MethodChannel.Result {
        val successes = mutableListOf<Any?>()
        val errors = mutableListOf<Triple<String, String?, Any?>>()
        var notImplementedCount = 0

        override fun success(result: Any?) {
            synchronized(this) { successes += result }
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            synchronized(this) { errors += Triple(errorCode, errorMessage, errorDetails) }
        }

        override fun notImplemented() {
            synchronized(this) { notImplementedCount++ }
        }
    }

    private class RecordingExecutor : ExecutorService {
        val tasks = ArrayDeque<Runnable>()
        var shutdown = false

        override fun execute(command: Runnable) {
            check(!shutdown) { "executor is shut down" }
            tasks.addLast(command)
        }

        fun runNext() {
            tasks.removeFirst().run()
        }

        override fun shutdown() {
            shutdown = true
        }

        override fun shutdownNow(): MutableList<Runnable> {
            shutdown = true
            return tasks.toMutableList().also { tasks.clear() }
        }

        override fun isShutdown(): Boolean = shutdown
        override fun isTerminated(): Boolean = shutdown && tasks.isEmpty()
        override fun awaitTermination(timeout: Long, unit: TimeUnit): Boolean = isTerminated
        override fun <T> submit(task: java.util.concurrent.Callable<T>): java.util.concurrent.Future<T> =
            unsupported()
        override fun <T> submit(task: Runnable, result: T): java.util.concurrent.Future<T> =
            unsupported()
        override fun submit(task: Runnable): java.util.concurrent.Future<*> = unsupported()
        override fun <T> invokeAll(
            tasks: Collection<java.util.concurrent.Callable<T>>,
        ): MutableList<java.util.concurrent.Future<T>> = unsupported()
        override fun <T> invokeAll(
            tasks: Collection<java.util.concurrent.Callable<T>>,
            timeout: Long,
            unit: TimeUnit,
        ): MutableList<java.util.concurrent.Future<T>> = unsupported()
        override fun <T> invokeAny(tasks: Collection<java.util.concurrent.Callable<T>>): T =
            unsupported()
        override fun <T> invokeAny(
            tasks: Collection<java.util.concurrent.Callable<T>>,
            timeout: Long,
            unit: TimeUnit,
        ): T = unsupported()

        private fun <T> unsupported(): T =
            throw UnsupportedOperationException("not used by NativePaletteBridge tests")
    }

    private fun immediateHandler(): Handler = mock {
        on { post(any()) } doAnswer {
            it.getArgument<Runnable>(0).run()
            true
        }
    }

    private fun bridge(
        executor: ExecutorService = RecordingExecutor(),
        extractor: ((Int) -> List<Int>?)? = { _ ->
            listOf(
                0xFF112233.toInt(),
                0xFF445566.toInt(),
                0xFF778899.toInt(),
                0xFFAABBCC.toInt(),
                0xFF101820.toInt(),
            )
        },
    ): NativePaletteBridge = NativePaletteBridge(
        artworkCacheManager = mock(),
        executor = executor,
        mainHandler = immediateHandler(),
            callbackWatchdog = mock(),
        extractColorsOverride = extractor,
    )

    private fun palette(vararg swatches: Pair<Int, Int>): Palette =
        Palette.Builder(swatches.map { (rgb, population) ->
            Palette.Swatch(rgb, population)
        }).generate()

    @Test
    fun `A01 validates arguments and exposes cache version`() {
        val executor = RecordingExecutor()
        val bridge = bridge(executor)
        val invalid = RecordingResult()
        val version = RecordingResult()

        bridge.handleCall("extractPalette", "1", invalid)
        bridge.handleCall("getCacheVersion", null, version)

        assertEquals("invalid_song_id", invalid.errors.single().first)
        assertEquals(NativePaletteBridge.CACHE_VERSION, version.successes.single())
        assertTrue(executor.tasks.isEmpty())
    }

    @Test
    fun `A02 unknown methods are reported as not implemented`() {
        val result = RecordingResult()
        bridge().handleCall("unknown", null, result)
        assertEquals(1, result.notImplementedCount)
    }

    @Test
    fun `B01 coalesces same song and fans out one five-color result`() {
        val executor = RecordingExecutor()
        var extractionCalls = 0
        val bridge = bridge(executor) {
            extractionCalls++
            listOf(1, 2, 3, 4, 5)
        }
        val first = RecordingResult()
        val second = RecordingResult()

        bridge.handleCall("extractPalette", 42, first)
        bridge.handleCall("extractPalette", 42, second)

        assertEquals(1, executor.tasks.size)
        executor.runNext()

        assertEquals(1, extractionCalls)
        assertEquals(listOf(1, 2, 3, 4, 5), first.successes.single())
        assertEquals(listOf(1, 2, 3, 4, 5), second.successes.single())
        assertTrue(first.errors.isEmpty())
        assertTrue(second.errors.isEmpty())
    }

    @Test
    fun `B03 coalesces requests while completed result awaits Handler delivery`() {
        val executor = RecordingExecutor()
        val callbacks = ArrayDeque<Runnable>()
        val handler = mock<Handler> {
            on { post(any()) } doAnswer {
                callbacks.addLast(it.getArgument<Runnable>(0))
                true
            }
        }
        val bridge = NativePaletteBridge(
            artworkCacheManager = mock(),
            executor = executor,
            mainHandler = handler,
            callbackWatchdog = mock(),
            extractColorsOverride = { listOf(1, 2, 3, 4, 5) },
        )
        val first = RecordingResult()
        val second = RecordingResult()

        bridge.handleCall("extractPalette", 42, first)
        executor.runNext()
        bridge.handleCall("extractPalette", 42, second)

        assertEquals(0, executor.tasks.size)
        assertEquals(2, callbacks.size)
        callbacks.removeFirst().run()
        callbacks.removeFirst().run()
        assertEquals(1, first.successes.size)
        assertEquals(1, second.successes.size)
        assertTrue(executor.tasks.isEmpty())
    }

    @Test
    fun `D03 watchdog completes an accepted but undelivered Handler callback`() {
        val executor = RecordingExecutor()
        val watchdog = mock<ScheduledExecutorService>()
        val watchdogCallback = argumentCaptor<Runnable>()
        whenever(
            watchdog.schedule(
                watchdogCallback.capture(),
                eq(5_000L),
                eq(TimeUnit.MILLISECONDS),
            ),
        ).thenReturn(null)
        val handler = mock<Handler> {
            on { post(any()) } doAnswer { true }
        }
        val bridge = NativePaletteBridge(
            artworkCacheManager = mock(),
            executor = executor,
            mainHandler = handler,
            callbackWatchdog = watchdog,
            extractColorsOverride = { listOf(1, 2, 3, 4, 5) },
        )
        val result = RecordingResult()

        bridge.handleCall("extractPalette", 43, result)
        executor.runNext()
        watchdogCallback.firstValue.run()

        assertEquals("palette_unavailable", result.errors.single().first)
        assertTrue(result.successes.isEmpty())
        bridge.dispose()
    }

    @Test
    fun `B02 different songs receive independent jobs`() {
        val executor = RecordingExecutor()
        val bridge = bridge(executor) { songId -> listOf(songId) }
        val first = RecordingResult()
        val second = RecordingResult()

        bridge.handleCall("extractPalette", 1, first)
        bridge.handleCall("extractPalette", 2, second)

        assertEquals(2, executor.tasks.size)
        executor.runNext()
        executor.runNext()
        assertEquals(listOf(1), first.successes.single())
        assertEquals(listOf(2), second.successes.single())
    }

    @Test
    fun `C01 queue rejection is returned as palette busy`() {
        val executor = mock<ExecutorService>()
        doThrow(RejectedExecutionException()).whenever(executor).execute(any())
        val result = RecordingResult()

        bridge(executor).handleCall("extractPalette", 9, result)

        assertEquals("palette_busy", result.errors.single().first)
    }

    @Test
    fun `C02 null artwork result remains a successful null extraction`() {
        val executor = RecordingExecutor()
        val result = RecordingResult()
        val bridge = bridge(executor) { null }

        bridge.handleCall("extractPalette", 11, result)
        executor.runNext()

        assertEquals(1, result.successes.size)
        assertEquals(null, result.successes.single())
        assertTrue(result.errors.isEmpty())
    }

    @Test
    fun `C03 extraction exception is mapped to a stable channel error`() {
        val executor = RecordingExecutor()
        val result = RecordingResult()
        val bridge = bridge(executor) {
            throw IllegalStateException("decode failed")
        }

        bridge.handleCall("extractPalette", 12, result)
        executor.runNext()

        assertEquals("palette_extraction_failed", result.errors.single().first)
        assertTrue(result.successes.isEmpty())
    }

    @Test
    fun `C04 out of memory is mapped without leaving the request unresolved`() {
        val executor = RecordingExecutor()
        val result = RecordingResult()
        val bridge = bridge(executor) {
            throw OutOfMemoryError("test memory pressure")
        }

        bridge.handleCall("extractPalette", 13, result)
        executor.runNext()

        assertEquals("palette_memory_error", result.errors.single().first)
        assertTrue(result.successes.isEmpty())
    }

    @Test
    fun `D01 dispose completes pending requests once and suppresses queued work`() {
        val executor = RecordingExecutor()
        val result = RecordingResult()
        val bridge = bridge(executor) { listOf(1, 2, 3, 4, 5) }

        bridge.handleCall("extractPalette", 7, result)
        bridge.dispose()
        bridge.dispose()
        executor.runNext()

        assertEquals(1, result.errors.size)
        assertEquals("palette_unavailable", result.errors.single().first)
        assertTrue(result.successes.isEmpty())
    }

    @Test
    fun `D02 requests after dispose are rejected without executor work`() {
        val executor = RecordingExecutor()
        val bridge = bridge(executor)
        bridge.dispose()
        val result = RecordingResult()

        bridge.handleCall("extractPalette", 8, result)

        assertEquals("palette_unavailable", result.errors.single().first)
        assertTrue(executor.tasks.isEmpty())
    }

    @Test
    fun `E01 clustering preserves five roles and merges similar swatches`() {
        val blue = 0xFF123A80.toInt()
        val nearbyBlue = 0xFF183F84.toInt()
        val warm = 0xFFC87545.toInt()
        val result = bridge().selectBestFiveForTest(
            palette(
                blue to 80,
                nearbyBlue to 70,
                warm to 60,
                0xFF5E8CBA.toInt() to 20,
            ),
        )

        assertEquals(5, result.size)
        assertEquals(blue, result[0])
        // The role selector may choose a representative from a merged warm
        // cluster rather than the exact input swatch. Verify that a distinct
        // warm family survives instead of requiring RGB identity.
        assertTrue(
            result.drop(1).any { color ->
                redDistance(color, warm) < redDistance(blue, warm)
            },
        )
    }

    @Test
    fun `E02 dominant neutral replaces a much smaller chromatic family`() {
        val neutral = 0xFFEEEEEE.toInt()
        val chromatic = 0xFFCC2244.toInt()
        val result = bridge().selectBestFiveForTest(
            palette(
                neutral to 300,
                chromatic to 20,
                0xFF882244.toInt() to 10,
            ),
        )

        assertEquals(5, result.size)
        assertEquals(neutral, result[0])
        assertNotNull(result[3])
        assertNotNull(result[4])
    }

    @Test
    fun `E03 empty palette returns the stable five-color fallback`() {
        val emptyPalette = mock<Palette>()
        whenever(emptyPalette.swatches).thenReturn(emptyList())
        val result = bridge().selectBestFiveForTest(emptyPalette)
        assertEquals(NativePaletteBridge.FALLBACK, result)
    }

    private fun redDistance(first: Int, second: Int): Int =
        kotlin.math.abs(((first shr 16) and 0xFF) - ((second shr 16) and 0xFF)) +
            kotlin.math.abs(((first shr 8) and 0xFF) - ((second shr 8) and 0xFF)) +
            kotlin.math.abs((first and 0xFF) - (second and 0xFF))
}