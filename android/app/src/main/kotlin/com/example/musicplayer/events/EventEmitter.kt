package com.example.musicplayer.events

import io.flutter.plugin.common.EventChannel

/**
 * Central event bus for all playback-related EventChannel streams.
 *
 * Fixes: duplicate emission guard — callers may emit freely; deduplication
 * of high-frequency events (position, playbackState, repeatMode, shuffleMode)
 * is handled by TransportState, not here, so the sink layer stays simple.
 *
 * Replaces the original nested `object Events` inside Media3PlaybackService.
 * MainActivity still accesses this via Media3PlaybackService.Events (companion alias).
 */
object EventEmitter {
    private val sinks = mutableMapOf<String, EventChannel.EventSink?>()

    /** Called whenever a new Flutter listener subscribes to any stream. */
    private var onSubscribe: (() -> Unit)? = null

    fun setOnSubscribeCallback(callback: () -> Unit) {
        onSubscribe = callback
    }

    fun handler(name: String): EventChannel.StreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            sinks[name] = events
            onSubscribe?.invoke()
        }
        override fun onCancel(arguments: Any?) {
            sinks[name] = null
        }
    }

    fun emit(name: String, value: Any?) {
        sinks[name]?.success(value)
    }
}

/**
 * Native log stream forwarded to Flutter for in-app debug display.
 * Replaces the original nested `object NativeLogs` inside Media3PlaybackService.
 * MainActivity still accesses this via Media3PlaybackService.NativeLogs (companion alias).
 */
object NativeLogger {
    private var sink: EventChannel.EventSink? = null

    fun handler(): EventChannel.StreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
        override fun onCancel(arguments: Any?) { sink = null }
    }

    fun emit(level: String, category: String, message: String) {
        sink?.success(mapOf("level" to level, "category" to category, "message" to message))
    }
}
