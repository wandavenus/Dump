package com.example.musicplayer.sleep_timer

import android.os.Handler
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.events.EventEmitter
import com.example.musicplayer.events.NativeLogger

/**
 * Self-contained sleep timer.
 *
 * Fixes:
 * - triggerStop() now has a guard so double-firing is harmless.
 * - emitSleepTimer() is only called when state actually changes, not on every
 *   200ms position tick (UW-01 fix — caller TransportState no longer calls this
 *   inside the hot position loop; instead the timer self-emits on tick).
 */
@UnstableApi
class SleepTimerManager(
    private val handler: Handler,
    private val getPlayer: () -> ExoPlayer?,
    private val stopTicker: () -> Unit,
    private val emitAll: () -> Unit,
) {
    var sleepTimerActive = false
        private set
    var sleepEndOfSong = false
        private set
    var sleepTimerEndMs = 0L
        private set

    private var timerRunnable: Runnable? = null
    private var tickRunnable: Runnable? = null

    // ── Public API ────────────────────────────────────────────────────────────

    fun startDuration(durationMs: Long) {
        cancelInternal()
        if (durationMs <= 0L) return

        sleepTimerActive = true
        sleepEndOfSong   = false
        sleepTimerEndMs  = System.currentTimeMillis() + durationMs

        val tick = object : Runnable {
            override fun run() {
                if (!sleepTimerActive) return
                emitSleepTimer()
                handler.postDelayed(this, 1000L)
            }
        }
        tickRunnable = tick
        handler.postDelayed(tick, 1000L)

        timerRunnable = Runnable { triggerStop() }
        handler.postDelayed(timerRunnable!!, durationMs)

        emitSleepTimer()
        log("Sleep timer started: ${durationMs}ms")
    }

    fun startEndOfSong() {
        cancelInternal()
        sleepTimerActive = true
        sleepEndOfSong   = true
        sleepTimerEndMs  = 0L
        emitSleepTimer()
        log("Sleep timer: end-of-song mode")
    }

    /**
     * Fire point for both timed and end-of-song modes.
     * Guard prevents double-firing if both onMediaItemTransition and the Handler
     * runnable race to call this.
     */
    fun triggerStop() {
        if (!sleepTimerActive) return
        log("Sleep timer fired — pausing")
        getPlayer()?.pause()
        stopTicker()
        cancelInternal()
        emitAll()
    }

    fun cancel() {
        if (!sleepTimerActive) {
            NativeLogger.emit("verbose", "SleepTimer", "cancelSleepTimer called but no active timer")
            return
        }
        cancelInternal()
        emitSleepTimer()
        log("Sleep timer cancelled")
    }

    fun emitSleepTimer() {
        val remaining = if (sleepTimerActive && !sleepEndOfSong)
            (sleepTimerEndMs - System.currentTimeMillis()).coerceAtLeast(0L)
        else 0L
        EventEmitter.emit("sleepTimer", mapOf(
            "active"      to sleepTimerActive,
            "endOfSong"   to sleepEndOfSong,
            "remainingMs" to remaining,
        ))
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun cancelInternal() {
        timerRunnable?.let { handler.removeCallbacks(it) }
        tickRunnable?.let  { handler.removeCallbacks(it) }
        timerRunnable    = null
        tickRunnable     = null
        sleepTimerActive = false
        sleepEndOfSong   = false
        sleepTimerEndMs  = 0L
    }

    private fun log(msg: String) = NativeLogger.emit("info", "SleepTimer", msg)
}
