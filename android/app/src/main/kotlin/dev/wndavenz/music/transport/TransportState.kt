package dev.wndavenz.music.transport

import android.os.Handler
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import dev.wndavenz.music.crossfade.CrossfadeController
import dev.wndavenz.music.events.EventEmitter
import dev.wndavenz.music.events.NativeLogger
import dev.wndavenz.music.queue.QueueManager
import dev.wndavenz.music.sleep_timer.SleepTimerManager
import dev.wndavenz.music.utils.TrackMapper

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
    private val onStuck: (retryCount: Int) -> Unit = {},
    private val getActiveStreamSlot: () -> Int = { 0 },
) {
    private val positionUpdateMs = 200L
    private var lastEmittedRepeatMode: String? = null

    companion object {
        private const val WATCHDOG_STALL_MS  = 5_000L
        private const val WATCHDOG_MAX_RETRIES = 2
        private const val WATCHDOG_END_GUARD_MS = 2_000L
    }

    private var watchdogLastPositionMs = -1L
    private var watchdogStallAccMs     = 0L
    private var watchdogRetryCount     = 0

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

    private fun checkWatchdog(p: ExoPlayer) {
        val pos      = p.currentPosition
        val duration = p.duration

        val nearEnd      = duration > 0L && pos >= duration - WATCHDOG_END_GUARD_MS
        val unknownDur   = duration <= 0L
        val crossfading  = crossfadeController.crossfadeInProgress
        val exhausted    = watchdogRetryCount >= WATCHDOG_MAX_RETRIES

        if (crossfading || unknownDur || nearEnd || exhausted) {
            watchdogLastPositionMs = pos
            return
        }

        if (watchdogLastPositionMs < 0L) {
            watchdogLastPositionMs = pos
            return
        }

        if (pos != watchdogLastPositionMs) {
            watchdogLastPositionMs = pos
            watchdogStallAccMs     = 0L
            watchdogRetryCount     = 0
            return
        }

        watchdogStallAccMs += positionUpdateMs

        if (watchdogStallAccMs >= WATCHDOG_STALL_MS) {
            watchdogRetryCount++
            watchdogStallAccMs = 0L
            NativeLogger.emit(
                "warn", "Watchdog",
                "Stuck: pos=${pos}ms dur=${duration}ms retry=$watchdogRetryCount — invoking recovery",
            )
            onStuck(watchdogRetryCount)
        }
    }

    fun resetWatchdog() {
        watchdogLastPositionMs = -1L
        watchdogStallAccMs     = 0L
        watchdogRetryCount     = 0
    }

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
        EventEmitter.emit("shuffleMode",    p.shuffleModeEnabled)

        if (repeatStr != lastEmittedRepeatMode) {
            lastEmittedRepeatMode = repeatStr
            EventEmitter.emit("repeatMode", repeatStr)
        }

        if (emitQueue) EventEmitter.emit("queue", queueManager.queue)
        sleepTimerManager.emitSleepTimer()
    }

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
        streamSlot           = getActiveStreamSlot(),
    )
}
