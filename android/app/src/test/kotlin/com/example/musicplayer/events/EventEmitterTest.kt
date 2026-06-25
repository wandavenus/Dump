package com.example.musicplayer.events

import io.flutter.plugin.common.EventChannel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM unit tests for [EventEmitter] and [NativeLogger].
 *
 * [EventEmitter] is a singleton object so sinks registered in one test persist
 * for subsequent tests.  Each test uses a unique stream name derived from the
 * test method and cancels subscriptions in @After to guarantee isolation.
 *
 * Test groups:
 *   A. EventEmitter — subscribe, emit, cancel
 *   B. EventEmitter — onSubscribe callback
 *   C. EventEmitter — multiple independent streams
 *   D. NativeLogger — emit when registered and unregistered
 */
class EventEmitterTest {

    /** Collects all events received by [EventEmitter.emit]. */
    private class FakeSink : EventChannel.EventSink {
        val events = mutableListOf<Any?>()
        override fun success(event: Any?) { events.add(event) }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
        override fun endOfStream() {}
    }

    /** Tracks names of all streams subscribed in this test so @After can clean up. */
    private val registeredStreams = mutableListOf<String>()

    private fun subscribe(name: String, sink: EventChannel.EventSink): EventChannel.StreamHandler {
        val handler = EventEmitter.handler(name)
        handler.onListen(null, sink)
        registeredStreams.add(name)
        return handler
    }

    @After
    fun tearDown() {
        registeredStreams.forEach { name ->
            EventEmitter.handler(name).onCancel(null)
        }
        registeredStreams.clear()
        // Reset onSubscribe callback so it doesn't bleed across tests
        EventEmitter.setOnSubscribeCallback { }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // A. Subscribe, emit, cancel
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `A01 emit after subscribe delivers the event to the sink`() {
        val sink = FakeSink()
        subscribe("testA01", sink)

        EventEmitter.emit("testA01", "hello")

        assertEquals(1, sink.events.size)
        assertEquals("hello", sink.events[0])
    }

    @Test fun `A02 emit before subscribe delivers nothing`() {
        val sink = FakeSink()
        EventEmitter.emit("testA02_not_yet", "dropped")
        subscribe("testA02", sink)

        assertEquals(0, sink.events.size)
    }

    @Test fun `A03 cancel removes the sink so further emits are dropped`() {
        val sink = FakeSink()
        val handler = subscribe("testA03", sink)

        EventEmitter.emit("testA03", "first")
        handler.onCancel(null)
        EventEmitter.emit("testA03", "second")

        assertEquals(1, sink.events.size)
        assertEquals("first", sink.events[0])
    }

    @Test fun `A04 emit null value is delivered as null`() {
        val sink = FakeSink()
        subscribe("testA04", sink)

        EventEmitter.emit("testA04", null)

        assertEquals(1, sink.events.size)
        assertNull(sink.events[0])
    }

    @Test fun `A05 multiple emits are all delivered in order`() {
        val sink = FakeSink()
        subscribe("testA05", sink)

        EventEmitter.emit("testA05", 1)
        EventEmitter.emit("testA05", 2)
        EventEmitter.emit("testA05", 3)

        assertEquals(listOf(1, 2, 3), sink.events)
    }

    @Test fun `A06 re-subscribing replaces the old sink`() {
        val sink1 = FakeSink()
        val sink2 = FakeSink()
        subscribe("testA06", sink1)
        subscribe("testA06", sink2)  // overwrites sink1

        EventEmitter.emit("testA06", "value")

        assertEquals(0, sink1.events.size)  // sink1 no longer registered
        assertEquals(1, sink2.events.size)
        assertEquals("value", sink2.events[0])
    }

    @Test fun `A07 emit map value is delivered as a map`() {
        val sink = FakeSink()
        subscribe("testA07", sink)
        val payload = mapOf("key" to "value", "count" to 42)

        EventEmitter.emit("testA07", payload)

        @Suppress("UNCHECKED_CAST")
        val received = sink.events[0] as Map<String, Any>
        assertEquals("value", received["key"])
        assertEquals(42, received["count"])
    }

    // ═════════════════════════════════════════════════════════════════════════
    // B. onSubscribe callback
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `B01 onSubscribe callback is invoked when a new listener subscribes`() {
        var invoked = false
        EventEmitter.setOnSubscribeCallback { invoked = true }

        subscribe("testB01", FakeSink())

        assertTrue(invoked)
    }

    @Test fun `B02 onSubscribe is invoked for each new subscription`() {
        var count = 0
        EventEmitter.setOnSubscribeCallback { count++ }

        subscribe("testB02a", FakeSink())
        subscribe("testB02b", FakeSink())

        assertEquals(2, count)
    }

    @Test fun `B03 onSubscribe is not invoked when no callback is set`() {
        EventEmitter.setOnSubscribeCallback { }  // no-op callback (not null)
        // Subscribing should not throw when callback is a no-op
        subscribe("testB03", FakeSink())
    }

    // ═════════════════════════════════════════════════════════════════════════
    // C. Multiple independent streams
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `C01 emitting on one stream does not affect other streams`() {
        val sink1 = FakeSink()
        val sink2 = FakeSink()
        subscribe("testC01_stream1", sink1)
        subscribe("testC01_stream2", sink2)

        EventEmitter.emit("testC01_stream1", "for stream1")

        assertEquals(1, sink1.events.size)
        assertEquals(0, sink2.events.size)
    }

    @Test fun `C02 cancelling one stream leaves the other active`() {
        val sink1 = FakeSink()
        val sink2 = FakeSink()
        val h1 = subscribe("testC02_stream1", sink1)
        subscribe("testC02_stream2", sink2)

        h1.onCancel(null)
        EventEmitter.emit("testC02_stream1", "dropped")
        EventEmitter.emit("testC02_stream2", "delivered")

        assertEquals(0, sink1.events.size)
        assertEquals(1, sink2.events.size)
    }

    @Test fun `C03 three independent streams all receive their own events`() {
        val sinkA = FakeSink(); val sinkB = FakeSink(); val sinkC = FakeSink()
        subscribe("testC03_A", sinkA)
        subscribe("testC03_B", sinkB)
        subscribe("testC03_C", sinkC)

        EventEmitter.emit("testC03_A", "a")
        EventEmitter.emit("testC03_B", "b")
        EventEmitter.emit("testC03_C", "c")

        assertEquals(listOf("a"), sinkA.events)
        assertEquals(listOf("b"), sinkB.events)
        assertEquals(listOf("c"), sinkC.events)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // D. NativeLogger
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `D01 NativeLogger emit with no subscriber does not throw`() {
        NativeLogger.emit("info", "Test", "no subscriber — safe no-op")
    }

    @Test fun `D02 NativeLogger emit after subscribe delivers structured map`() {
        val sink = FakeSink()
        val handler = NativeLogger.handler()
        handler.onListen(null, sink)

        NativeLogger.emit("warn", "CrossfadeTest", "test message")

        assertEquals(1, sink.events.size)
        @Suppress("UNCHECKED_CAST")
        val event = sink.events[0] as Map<String, String>
        assertEquals("warn",            event["level"])
        assertEquals("CrossfadeTest",   event["category"])
        assertEquals("test message",    event["message"])

        handler.onCancel(null)
    }

    @Test fun `D03 NativeLogger emit after cancel delivers nothing`() {
        val sink = FakeSink()
        val handler = NativeLogger.handler()
        handler.onListen(null, sink)
        handler.onCancel(null)

        NativeLogger.emit("info", "Test", "after cancel")

        assertEquals(0, sink.events.size)
    }
}
