package com.example.musicplayer

import androidx.media3.common.util.UnstableApi
import com.example.musicplayer.events.NativeLogger

/**
 * Encapsulates the two-phase shutdown sequence for [Media3PlaybackService].
 *
 * All dependencies are injected as lambdas so the coordinator is fully
 * testable as a plain JVM unit (no Android framework required).
 *
 * ── Phase 1: [prepareShutdown] ───────────────────────────────────────────────
 * Called from [Media3PlaybackService.handle] for the "release" MethodChannel
 * method, **before** [Media3PlaybackService.stopSelf].
 *
 * Quiesces the service:
 *   1. Cancels the sleep timer.
 *   2. Cancels any in-flight crossfade.
 *   3. Stops the position ticker.
 *   4. Abandons audio focus.
 *   5. Removes the foreground notification.
 *   6. Emits a final state snapshot to Flutter so the UI updates before the
 *      service dies.
 *
 * ── Phase 2: [performTeardown] ───────────────────────────────────────────────
 * Called from [Media3PlaybackService.onDestroy].
 *
 * Releases every native resource:
 *   1. Cancels crossfade (idempotent — safe even after Phase 1).
 *   2. Saves the queue to SharedPreferences.
 *   3. Cancels the sleep timer (idempotent).
 *   4. Releases audio effects (EQ, LoudnessEnhancer, …).
 *   5. Clears all pending Handler callbacks.
 *   6. Unregisters BroadcastReceivers.
 *   7. Abandons audio focus (idempotent).
 *   8. Releases primaryPlayer.
 *   9. Releases secondaryPlayer.
 *   10. Releases the MediaSession.
 *
 * ── Semantics ────────────────────────────────────────────────────────────────
 * • Both phases are **independently idempotent** — duplicate calls after the
 *   first invocation are no-ops.  This prevents double-release when
 *   [prepareShutdown] runs in "release" and [onDestroy] repeats some of the
 *   same steps.
 * • Phase 1 is **optional** — if [onDestroy] fires without a prior
 *   [prepareShutdown] (e.g., system kills the service), [performTeardown]
 *   still runs the full teardown unconditionally.
 * • "stop" vs "release":
 *     stop    → ExoPlayer transitions to STATE_IDLE; service stays alive.
 *     release → full service teardown; stopSelf() is called; onDestroy fires.
 */
@UnstableApi
class ServiceShutdownCoordinator(
    private val cancelCrossfade:        (resetVolume: Boolean) -> Unit,
    private val cancelSleepTimer:       () -> Unit,
    private val stopPositionTicker:     () -> Unit,
    private val emitAll:                () -> Unit,
    private val abandonAudioFocus:      () -> Unit,
    private val stopForeground:         () -> Unit,
    private val saveQueue:              () -> Unit,
    private val releaseEffects:         () -> Unit,
    private val clearHandlerCallbacks:  () -> Unit,
    private val unregisterReceivers:    () -> Unit,
    private val releasePrimaryPlayer:   () -> Unit,
    private val releaseSecondaryPlayer: () -> Unit,
    private val releaseMediaSession:    () -> Unit,
) {
    @Volatile var shutdownPrepared  = false
        private set
    @Volatile var teardownPerformed = false
        private set

    /**
     * Phase 1: pre-[stopSelf] quiescence.
     *
     * Cancels transient in-flight work, abandons audio focus, removes the
     * foreground notification, and emits a final state event so Flutter sees a
     * clean idle state before the service is destroyed.
     *
     * Idempotent — a second call is a no-op.
     */
    fun prepareShutdown() {
        if (shutdownPrepared) return
        shutdownPrepared = true
        NativeLogger.emit("info", "Shutdown",
            "prepareShutdown: quiescing service before stopSelf()")
        cancelSleepTimer()
        cancelCrossfade(true)
        stopPositionTicker()
        abandonAudioFocus()
        stopForeground()
        emitAll()
    }

    /**
     * Phase 2: full resource teardown (called from [onDestroy]).
     *
     * Releases all native resources.  Also cancels crossfade and sleep timer
     * in case [prepareShutdown] was not called first (system-kill path).
     *
     * Idempotent — a second call is a no-op; players and session are never
     * double-released.
     */
    fun performTeardown() {
        if (teardownPerformed) return
        teardownPerformed = true
        NativeLogger.emit("info", "Shutdown",
            "performTeardown: releasing all native resources")
        cancelCrossfade(true)
        saveQueue()
        cancelSleepTimer()
        releaseEffects()
        clearHandlerCallbacks()
        unregisterReceivers()
        abandonAudioFocus()
        releasePrimaryPlayer()
        releaseSecondaryPlayer()
        releaseMediaSession()
    }
}
