package dev.wndavenz.music.events

import io.flutter.plugin.common.EventChannel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Regression tests for FlutterEngine-scoped native EventChannel listeners. */
class EngineSinkLifecycleTest {
    private data class EngineIdentity(val id: Int)

    private class FakeSink : EventChannel.EventSink {
        val events = mutableListOf<Any?>()
        override fun success(event: Any?) { events.add(event) }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
        override fun endOfStream() = Unit
    }

    private val owners = mutableListOf<Any>()

    private fun newEngineIdentity(): EngineIdentity =
        EngineIdentity(1).also { owners.add(it) }

    @After
    fun tearDown() {
        owners.forEach { owner ->
            EventEmitter.cleanupEngine(owner)
            NativeLogger.cleanupEngine(owner)
            ServiceReadyGate.cleanupEngine(owner)
        }
        owners.clear()
        EventEmitter.setOnSubscribeCallback { }
        NativeLogger.setEnabled(false)
        NativeLogger.resetDispatcher()
        ServiceReadyGate.reset()
    }

    @Test
    fun `detach clears only the sinks owned by that engine`() {
        val detachedEngine = newEngineIdentity()
        val activeEngine = newEngineIdentity()
        assertEquals(detachedEngine, activeEngine)
        assertFalse(detachedEngine === activeEngine)

        val detachedSink = FakeSink()
        val activeSink = FakeSink()
        EventEmitter.handler("detached-position", detachedEngine)
            .onListen(null, detachedSink)
        EventEmitter.handler("active-position", activeEngine)
            .onListen(null, activeSink)

        EventEmitter.cleanupEngine(detachedEngine)
        EventEmitter.emit("detached-position", 250L)
        EventEmitter.emit("active-position", 500L)

        assertTrue(detachedSink.events.isEmpty())
        assertEquals(listOf(500L), activeSink.events)
    }

    @Test
    fun `late onCancel from old engine cannot remove new engine sink`() {
        val oldEngine = newEngineIdentity()
        val newEngine = newEngineIdentity()
        val oldSink = FakeSink()
        val newSink = FakeSink()

        val oldHandler = EventEmitter.handler("duration", oldEngine)
        oldHandler.onListen(null, oldSink)
        EventEmitter.handler("duration", newEngine).onListen(null, newSink)

        oldHandler.onCancel(null)
        EventEmitter.emit("duration", 12_000L)

        assertTrue(oldSink.events.isEmpty())
        assertEquals(listOf(12_000L), newSink.events)
    }

    @Test
    fun `new engine subscription receives current transport snapshot callback`() {
        val engine = newEngineIdentity()
        val sink = FakeSink()
        val snapshot = mapOf("playing" to true, "processingState" to "ready")

        EventEmitter.setOnSubscribeCallback {
            EventEmitter.emit("playbackState", snapshot)
        }
        EventEmitter.handler("playbackState", engine).onListen(null, sink)

        assertEquals(listOf(snapshot), sink.events)
    }

    @Test
    fun `queued NativeLogger event from detached engine is dropped and cannot leak to replacement`() {
        NativeLogger.setEnabled(true)
        val pending = mutableListOf<Runnable>()
        NativeLogger.dispatcher = { runnable -> pending.add(runnable) }

        val oldEngine = newEngineIdentity()
        val newEngine = newEngineIdentity()
        val oldSink = FakeSink()
        val newSink = FakeSink()
        val oldHandler = NativeLogger.handler(oldEngine)
        oldHandler.onListen(null, oldSink)

        NativeLogger.emit("info", "old-engine", "queued before detach")
        val staleDispatch = pending.removeAt(0)

        NativeLogger.cleanupEngine(oldEngine)
        NativeLogger.handler(newEngine).onListen(null, newSink)
        oldHandler.onCancel(null)
        staleDispatch.run()

        assertTrue(oldSink.events.isEmpty())
        assertTrue(newSink.events.isEmpty())

        NativeLogger.emit("info", "new-engine", "current listener")
        pending.removeAt(0).run()
        assertEquals(1, newSink.events.size)
        @Suppress("UNCHECKED_CAST")
        val event = newSink.events.single() as Map<String, String>
        assertEquals("new-engine", event["category"])
        assertEquals("current listener", event["message"])
    }

    @Test
    fun `ServiceReadyGate retains service readiness across engine detach`() {
        ServiceReadyGate.reset()
        val oldEngine = newEngineIdentity()
        val newEngine = newEngineIdentity()
        val oldSink = FakeSink()
        val newSink = FakeSink()
        val oldHandler = ServiceReadyGate.handler(oldEngine)

        oldHandler.onListen(null, oldSink)
        ServiceReadyGate.markReady()
        assertEquals(listOf(true), oldSink.events)

        ServiceReadyGate.cleanupEngine(oldEngine)
        ServiceReadyGate.handler(newEngine).onListen(null, newSink)
        assertEquals(listOf(true), newSink.events)

        oldHandler.onCancel(null)
        assertEquals(listOf(true), newSink.events)
    }
}
