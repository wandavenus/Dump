package com.example.musicplayer.events

import com.example.musicplayer.Media3PlaybackService
import io.flutter.plugin.common.EventChannel

object EventEmitter {
    private val sinks = mutableMapOf<String, EventChannel.EventSink?>()
    private val lastValues = mutableMapOf<String, Any?>()
    private val dedupeNames = setOf("repeatMode", "shuffleMode", "bufferingState", "audioSessionId")

    fun handler(name: String) = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            sinks[name] = events
            Media3PlaybackService.instance?.emitAll(emitQueue = true)
        }
        override fun onCancel(arguments: Any?) { sinks[name] = null }
    }

    fun emit(name: String, value: Any?) {
        if (name in dedupeNames && lastValues[name] == value) return
        if (name in dedupeNames) lastValues[name] = value
        sinks[name]?.success(value)
    }

    fun resetDedupe(name: String? = null) {
        if (name == null) lastValues.clear() else lastValues.remove(name)
    }
}

object NativeLogEmitter {
    private var sink: EventChannel.EventSink? = null

    fun handler() = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
        override fun onCancel(arguments: Any?) { sink = null }
    }

    fun emit(level: String, category: String, message: String) {
        sink?.success(mapOf("level" to level, "category" to category, "message" to message))
    }
}
