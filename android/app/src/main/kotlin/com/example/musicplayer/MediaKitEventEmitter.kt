package com.example.musicplayer

import io.flutter.plugin.common.EventChannel

/**
 * Singleton event emitter for the MediaKit transport EventChannel.
 *
 * [MediaKitPlaybackService] calls [emitTransport] when the system (lock screen,
 * BT device, notification buttons) issues a transport command. The Flutter
 * [MediaKitServiceBridge] receives these events on the
 * `musicplayer/mediakit_transport` EventChannel.
 *
 * Transport payload schema:
 *   {
 *     "action":     String  — "play" | "pause" | "next" | "previous" | "seek" | "stop"
 *     "positionMs": Long?   — only present for "seek" action
 *   }
 */
object MediaKitEventEmitter {

    @Volatile private var transportSink: EventChannel.EventSink? = null

    /** Returns the [EventChannel.StreamHandler] to register in [MainActivity]. */
    fun transportHandler(): EventChannel.StreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            transportSink = events
        }
        override fun onCancel(arguments: Any?) {
            transportSink = null
        }
    }

    /**
     * Emits a transport command to Flutter.
     *
     * @param action     One of "play", "pause", "next", "previous", "seek", "stop".
     * @param positionMs Seek target in milliseconds; only included when [action] == "seek".
     */
    fun emitTransport(action: String, positionMs: Long? = null) {
        val payload = mutableMapOf<String, Any?>("action" to action)
        if (positionMs != null) payload["positionMs"] = positionMs
        transportSink?.success(payload)
    }
}
