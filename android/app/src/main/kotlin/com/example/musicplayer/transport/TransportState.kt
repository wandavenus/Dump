package com.example.musicplayer.transport

import android.os.Handler
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.crossfade.CrossfadeController
import com.example.musicplayer.events.EventEmitter
import com.example.musicplayer.queue.QueueManager
import com.example.musicplayer.sleep_timer.SleepTimerManager
import com.example.musicplayer.utils.TrackMapper

/**
 * Owns the position ticker and the emitAll() state emission function.
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
 */
@UnstableApi
class TransportState(
    private val handler: Handler,
    private val getPlayer: () -> ExoPlayer?,
    private val queueManager: QueueManager,
    private val crossfadeController: CrossfadeController,
    private val sleepTimerManager: SleepTimerManager,
) {
    private val positionUpdateMs = 200L
    private var lastEmittedRepeatMode: String? = null

    // ── Position ticker ───────────────────────────────────────────────────────

    private val positionTicker = object : Runnable {
        override fun run() {
            emitPositionOnly()
            crossfadeController.maybeCrossfadeOut()
            if (getPlayer()?.isPlaying == true) {
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
        player              = getPlayer(),
        queue               = queueManager.queue,
        activeQueueIndex    = queueManager.activeQueueIndex,
        crossfadeDurationSec = crossfadeController.crossfadeDurationSec,
    )
}
