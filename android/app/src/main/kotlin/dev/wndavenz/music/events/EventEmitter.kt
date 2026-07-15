package dev.wndavenz.music.events

import android.os.Handler
import android.os.Looper
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
 * Cold-start readiness gate for [dev.wndavenz.music.Media3PlaybackService].
 *
 * Root cause this exists to fix: on a fresh install the service does not exist
 * yet (it is only created on-demand by "play"/"setQueue" — see the
 * `needsService` comment in MainActivity — anything else must not force a
 * start, or a queueless cold start hits the startForeground() deadline crash).
 * Meanwhile several Dart init steps (e.g. AudioEffectsService.init() pushing
 * persisted bass boost / EQ / crossfade settings) fire their
 * first MethodChannel call into `musicplayer/media3_playback` unconditionally
 * at Dart startup. If that races ahead of `Media3PlaybackService.onCreate()`
 * finishing, `instance` is still null and the call fails with
 * `PlatformException(not_ready)` — exactly once, only when the service has
 * never been created before (a fresh install's first launch); every later
 * launch finds the service (or its persisted queue restore) already warm.
 *
 * [markReady] is called once, at the very end of `onCreate()`. [onListen]
 * replays readiness immediately to a listener that subscribes after that
 * point (e.g. Dart re-attaching on a later app launch while the service
 * process is still alive) instead of only firing for listeners already
 * attached at the moment `markReady()` runs.
 */
object ServiceReadyGate {
    @Volatile private var ready = false
    private var sink: EventChannel.EventSink? = null

    fun handler(): EventChannel.StreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            sink = events
            if (ready) events?.success(true)
        }
        override fun onCancel(arguments: Any?) { sink = null }
    }

    /** Called once, at the end of [dev.wndavenz.music.Media3PlaybackService.onCreate]. */
    fun markReady() {
        ready = true
        sink?.success(true)
    }

    /** Reset when the service is torn down, so the next onCreate() must mark ready again. */
    fun reset() {
        ready = false
    }
}

/**
 * Native log stream forwarded to Flutter for in-app debug display.
 * Replaces the original nested `object NativeLogs` inside Media3PlaybackService.
 * MainActivity still accesses this via Media3PlaybackService.NativeLogs (companion alias).
 */
object NativeLogger {
    // @Volatile: emit() is now called from arbitrary background threads (audio/
    // playback thread, native JNI callbacks) in addition to the main thread —
    // without this, a background-thread read of `sink` is not guaranteed to see
    // the value published by onListen() on the main thread.
    @Volatile private var sink: EventChannel.EventSink? = null

    // Reused single Handler bound to the main Looper — see emit() below.
    private val mainHandler = Handler(Looper.getMainLooper())

    fun handler(): EventChannel.StreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
        override fun onCancel(arguments: Any?) { sink = null }
    }

    /**
     * Safe to call from ANY thread — including ExoPlayer's playback/audio
     * thread and native JNI callbacks (see SignalsmithStretchAudioProcessor /
     * stretch_jni.cpp diagnostics).
     *
     * Root cause this guards against: EventChannel.EventSink.success() is only
     * legal on Flutter's main/platform thread; calling it directly from a
     * background thread throws IllegalStateException. When that throw happened
     * inside SignalsmithStretchAudioProcessor's companion object initializer
     * (touched for the first time on the playback thread), it became an
     * unrecoverable ExceptionInInitializerError/NoClassDefFoundError that broke
     * audio sink construction and silently killed playback. Posting to the main
     * thread makes emit() fire-and-forget and non-throwing from the caller's
     * perspective, so a logging call can never abort playback again.
     */
    fun emit(level: String, category: String, message: String) {
        val payload = mapOf("level" to level, "category" to category, "message" to message)
        mainHandler.post {
            runCatching { sink?.success(payload) }
        }
    }
}
