package com.example.musicplayer.sleep_timer

import android.os.Handler

class SleepTimerManager(
    private val handler: Handler,
    private val emit: (Boolean, Boolean, Long) -> Unit,
    private val stop: () -> Unit,
    private val log: (String) -> Unit,
) {
    private var stopRunnable: Runnable? = null
    private var tickRunnable: Runnable? = null

    var active = false
        private set
    var endOfSong = false
        private set
    var endMs = 0L
        private set

    fun startDuration(durationMs: Long) {
        cancelInternal()
        if (durationMs <= 0L) return
        active = true
        endOfSong = false
        endMs = System.currentTimeMillis() + durationMs

        val tick = object : Runnable {
            override fun run() {
                if (!active) return
                emitState()
                handler.postDelayed(this, 1000L)
            }
        }
        tickRunnable = tick
        handler.postDelayed(tick, 1000L)

        stopRunnable = Runnable { triggerStop() }
        handler.postDelayed(stopRunnable!!, durationMs)
        emitState()
        log("Sleep timer started: ${durationMs}ms")
    }

    fun startEndOfSong() {
        cancelInternal()
        active = true
        endOfSong = true
        endMs = 0L
        emitState()
        log("Sleep timer: end-of-song mode")
    }

    fun triggerStop() {
        if (!active) return
        log("Sleep timer fired — pausing")
        cancelInternal()
        stop()
        emitState()
    }

    fun cancel() {
        if (!active) {
            log("cancelSleepTimer called but no active timer")
            return
        }
        cancelInternal()
        emitState()
        log("Sleep timer cancelled")
    }

    fun cancelInternal() {
        stopRunnable?.let { handler.removeCallbacks(it) }
        tickRunnable?.let { handler.removeCallbacks(it) }
        stopRunnable = null
        tickRunnable = null
        active = false
        endOfSong = false
        endMs = 0L
    }

    fun remainingMs(): Long = if (active && !endOfSong) {
        (endMs - System.currentTimeMillis()).coerceAtLeast(0L)
    } else {
        0L
    }

    fun emitState() = emit(active, endOfSong, remainingMs())
}
