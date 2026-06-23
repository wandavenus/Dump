package com.example.musicplayer.transport

import android.os.Handler
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.crossfade.CrossfadeController
import com.example.musicplayer.events.EventEmitter
import com.example.musicplayer.events.NativeLogger
import com.example.musicplayer.queue.QueueManager
import com.example.musicplayer.sleep_timer.SleepTimerManager
import com.example.musicplayer.utils.TrackMapper

/**
 * Owns the position ticker, stuck-playback watchdog, and the emitAll() state emission function.
 *
 * Fixes:
 * DE-01 to DE-06: emitAll() is the single canonical emission path.
 *   The trailing blanket emitAll() call that was at the bottom of handle() is removed.
 *   Each mutating handler calls emitAll() exactly once, from within its own branch.
 *
 * UW-01: sleepTimer is emitted in emitAll() so Flutter gets it on state transitions
 *   (subscription, track change, etc.) but the position ticker no longer re-emits
 *   it on every 200ms tick — the ticker calls emitPositionOnly() which skips it.
 *
 * PS-02 dedup: lastEmittedRepeatMode prevents repeat-mode double-emission
 *   when onRepeatModeChanged fires AND emitAll() runs in the same state transition.
 *
 * WD-01: Stuck-playback watchdog runs inside the position ticker.
 *   If isPlaying=true but position is frozen for WATCHDOG_STALL_MS (5 s), onStuck()
 *   is invoked with the retry count:
 *     retry 1 → p.prepare() re-initialises the codec pipeline (handles transient freeze).
 *     retry 2 → skip to next track (handles permanently corrupted / undecodable file).
 *   Guards: crossfade in progress, unknown duration, last 2 s of track, max 2 retries.
 *   The watchdog resets fully on stopPositionTicker() (pause / stop / track change).
 */
@UnstableApi
class TransportState(
    private val handler: Handler,
    private val getPlayer: () -> ExoPlayer?,
    private val queueManager: QueueManager,
    private val crossfadeController: CrossfadeController,
    private val sleepTimerManager: SleepTimerManager,
    /**
     * Called when the watchdog determines playback is stuck.
     * [retryCount] starts at 1 and increments on each successive stall after recovery.
     * Wired to Media3PlaybackService which decides whether to re-prepare or skip.
     */
    private val onStuck: (retryCount: Int) -> Unit = {},
) {
    private val positionUpdateMs = 200L
    private var lastEmittedRepeatMode: String? = null

    // ── Watchdog state ────────────────────────────────────────────────────────

    companion object {
        /** Stall duration (ms) before triggering the first recovery attempt. */
        private const val WATCHDOG_STALL_MS  = 5_000L
        /** Maximum number of recovery attempts before the watchdog gives up. */
        private const val WATCHDOG_MAX_RETRIES = 2
        /** Guard margin at end of track — don't fire watchdog in final 2 s. */
        private const val WATCHDOG_END_GUARD_MS = 2_000L
    }

    private var watchdogLastPositionMs = -1L
    private var watchdogStallAccMs     = 0L
    private var watchdogRetryCount     = 0

    // ── Position ticker ───────────────────────────────────────────────────────

    private val positionTicker = object : Runnable {
        override fun run() {
            emitPositionOnly()
            crossfadeController.maybeCrossfadeOut()
            val p = getPlayer()
            if (p?.isPlaying == true) {
                checkWatchdog(p)
                handler.postDelayed(this, positionUpdateMs)
            }
        }
    }

    fun startPositionTicker() {
        handler.removeCallbacks(positionTicker)
        if (getPlayer()?.isPlaying == true) handler.post(positionTicker)
    }

    fun stopPositionTicker() {
        handler.removeCallbacks(positionTicker)
        resetWatchdog()
    }

    // ── Watchdog logic ────────────────────────────────────────────────────────

    /**
     * Called on every 200 ms ticker tick while isPlaying == true.
     *
     * Position-movement check: position must advance between consecutive ticks.
     * At any finite playback speed > 0 the position advances by at least 1 ms per
     * 200 ms wall-clock interval, so even 0.1× speed is detected as healthy.
     *
     * Guards applied before accumulating stall time:
     *  • crossfade in progress — both players may briefly hold position during promotion.
     *  • duration unknown (≤ 0) — still in early loading phase.
     *  • position within final WATCHDOG_END_GUARD_MS of duration — natural deceleration.
     *  • max retries already reached — watchdog has given up.
     */
    private fun checkWatchdog(p: ExoPlayer) {
        val pos      = p.currentPosition
        val duration = p.duration

        val nearEnd      = duration > 0L && pos >= duration - WATCHDOG_END_GUARD_MS
        val unknownDur   = duration <= 0L
        val crossfading  = crossfadeController.crossfadeInProgress
        val exhausted    = watchdogRetryCount >= WATCHDOG_MAX_RETRIES

        if (crossfading || unknownDur || nearEnd || exhausted) {
            // Keep the last-position cursor in sync but don't accumulate stall time.
            watchdogLastPositionMs = pos
            return
        }

        // First tick after the watchdog was reset — initialise cursor and return.
        if (watchdogLastPositionMs < 0L) {
            watchdogLastPositionMs = pos
            return
        }

        if (pos != watchdogLastPositionMs) {
            // Position advanced → playback is healthy, clear accumulated stall.
            watchdogLastPositionMs = pos
            watchdogStallAccMs     = 0L
            watchdogRetryCount     = 0
            return
        }

        // Position unchanged this tick — accumulate stall time.
        watchdogStallAccMs += positionUpdateMs

        if (watchdogStallAccMs >= WATCHDOG_STALL_MS) {
            watchdogRetryCount++
            watchdogStallAccMs = 0L   // reset so the next threshold is a fresh 5 s window
            NativeLogger.emit(
                "warn", "Watchdog",
                "Stuck: pos=${pos}ms dur=${duration}ms retry=$watchdogRetryCount — invoking recovery",
            )
            onStuck(watchdogRetryCount)
        }
    }

    /** Full watchdog reset — call on pause, stop, or explicit track change. */
    fun resetWatchdog() {
        watchdogLastPositionMs = -1L
        watchdogStallAccMs     = 0L
        watchdogRetryCount     = 0
    }

    // ── State emission ────────────────────────────────────────────────────────

    /**
     * Full state snapshot — emitted on meaningful state changes.
     * Each mutating handle() branch calls this once.
     */
    fun emitAll(emitQueue: Boolean = false) {
        val p = getPlayer() ?: return

        val state = when (p.playbackState) {
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_READY     -> "ready"
            Player.STATE_ENDED     -> "completed"
            else                   -> "idle"
        }
        val repeatStr = when (p.repeatMode) {
            Player.REPEAT_MODE_ONE -> "one"
            Player.REPEAT_MODE_ALL -> "all"
            else                   -> "off"
        }

        EventEmitter.emit("playbackState",  mapOf("playing" to p.isPlaying, "processingState" to state))
        EventEmitter.emit("bufferingState", p.playbackState == Player.STATE_BUFFERING)
        EventEmitter.emit("position",       p.currentPosition.coerceAtLeast(0L))
        EventEmitter.emit("duration",       p.duration.coerceAtLeast(0L))
        EventEmitter.emit("currentTrack",   currentTrackMap())
        EventEmitter.emit("audioSessionId", p.audioSessionId)

        // DE-06 fix: deduplicate repeatMode — only emit when it changes.
        if (repeatStr != lastEmittedRepeatMode) {
            lastEmittedRepeatMode = repeatStr
            EventEmitter.emit("repeatMode", repeatStr)
        }

        if (emitQueue) EventEmitter.emit("queue", queueManager.queue)

        // sleepTimer: emit on full state snapshots so Flutter stays in sync
        // on subscription / track change / etc., but NOT on every 200ms tick.
        sleepTimerManager.emitSleepTimer()
    }

    /**
     * Lightweight emission used by the 200ms position ticker.
     * Skips sleepTimer, repeatMode, and other rarely-changing fields
     * to reduce EventChannel traffic.
     *
     * UW-01 fix: sleep timer no longer pushed every 200ms.
     */
    private fun emitPositionOnly() {
        val p = getPlayer() ?: return
        val state = when (p.playbackState) {
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_READY     -> "ready"
            Player.STATE_ENDED     -> "completed"
            else                   -> "idle"
        }
        EventEmitter.emit("playbackState",  mapOf("playing" to p.isPlaying, "processingState" to state))
        EventEmitter.emit("bufferingState", p.playbackState == Player.STATE_BUFFERING)
        EventEmitter.emit("position",       p.currentPosition.coerceAtLeast(0L))
        EventEmitter.emit("duration",       p.duration.coerceAtLeast(0L))
        EventEmitter.emit("currentTrack",   currentTrackMap())
    }

    fun emitRepeatMode(repeatMode: Int) {
        val repeatStr = when (repeatMode) {
            Player.REPEAT_MODE_ONE -> "one"
            Player.REPEAT_MODE_ALL -> "all"
            else                   -> "off"
        }
        // Guard: don't emit if emitAll() already covered this transition
        if (repeatStr != lastEmittedRepeatMode) {
            lastEmittedRepeatMode = repeatStr
            EventEmitter.emit("repeatMode", repeatStr)
        }
    }

    fun currentTrackMap(): Map<String, Any?>? = TrackMapper.currentTrackMap(
        player               = getPlayer(),
        queue                = queueManager.queue,
        activeQueueIndex     = queueManager.activeQueueIndex,
        crossfadeDurationSec = crossfadeController.crossfadeDurationSec,
    )
}
