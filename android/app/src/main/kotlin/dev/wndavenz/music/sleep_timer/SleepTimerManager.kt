package dev.wndavenz.music.sleep_timer

import android.os.Handler
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import dev.wndavenz.music.events.EventEmitter
import dev.wndavenz.music.events.NativeLogger

/**
 * Self-contained sleep timer with fade-out support.
 *
 * Duration mode  → triggers a 20-second volume fade-out, then pauses.
 * End-of-song    → pauses immediately at the track boundary (no fade).
 *
 * Fade lifecycle is independent of the timer lifecycle so:
 *   • UI sees "timer inactive" the moment the fade starts (correct).
 *   • A manual cancel() during a fade aborts the fade and restores volume.
 *   • Starting a new timer during a fade cancels the fade first.
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
    private var fadeRunnable: Runnable? = null
    // K11 fix: the player's volume when the fade started — restored when the
    // fade completes or is cancelled, instead of a hardcoded 1.0f that ignores
    // the user's actual volume (e.g. 0.3).
    private var fadeInitialVolume = 1.0f

    // ── Public API ────────────────────────────────────────────────────────────

    fun startDuration(durationMs: Long) {
        cancelFadeOut()
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

        val stopRunnable = Runnable { triggerStop() }
        timerRunnable = stopRunnable
        handler.postDelayed(stopRunnable, durationMs)

        emitSleepTimer()
        log("Sleep timer started: ${durationMs}ms")
    }

    fun startEndOfSong() {
        cancelFadeOut()
        cancelInternal()
        sleepTimerActive = true
        sleepEndOfSong   = true
        sleepTimerEndMs  = 0L
        emitSleepTimer()
        log("Sleep timer: end-of-song mode")
    }

    /**
     * Fire point for both timed and end-of-song modes.
     *
     * Duration mode  → 20-second fade-out then pause.
     * End-of-song    → immediate pause (fade would play into the next track).
     *
     * Guard prevents double-firing if both onMediaItemTransition and the Handler
     * runnable race to call this.
     */
    fun triggerStop() {
        if (!sleepTimerActive) return

        // Capture before cancelInternal() clears the flag.
        val wasEndOfSong = sleepEndOfSong

        stopTicker()
        cancelInternal()
        emitAll()   // UI: timer is now inactive

        if (wasEndOfSong) {
            // End-of-song: pause immediately — fading into a new track is jarring.
            getPlayer()?.pause()
            log("Sleep timer (end-of-song) fired — paused immediately")
        } else {
            // Duration: start 20-second fade-out.
            val player = getPlayer() ?: run {
                log("Sleep timer fired but player unavailable — skipping fade")
                return
            }
            startFadeOut(player)
        }
    }

    /**
     * Explicit user cancellation.
     * Works both when the timer is active AND when a fade is already running
     * (timer already fired but volume is still ramping down).
     */
    fun cancel() {
        val hadActiveFade = fadeRunnable != null
        if (!sleepTimerActive && !hadActiveFade) {
            NativeLogger.emit("verbose", "SleepTimer", "cancelSleepTimer called but no active timer or fade")
            return
        }
        cancelFadeOut()
        if (sleepTimerActive) cancelInternal()
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

    // ── Fade-out ──────────────────────────────────────────────────────────────

    private fun startFadeOut(player: ExoPlayer) {
        val totalSteps  = 20
        val stepMs      = 1000L
        val initialVol  = player.volume.coerceAtLeast(0.01f)
        fadeInitialVolume = initialVol.coerceIn(0f, 1f)
        var step        = 0

        val runnable = object : Runnable {
            override fun run() {
                step++
                val p = getPlayer()
                if (p == null || step >= totalSteps) {
                    // Fade complete (or player gone) — pause and restore volume.
                    // Use the same captured reference for both operations so
                    // a concurrent player swap can't affect the wrong player.
                    p?.pause()
                    p?.volume = fadeInitialVolume
                    fadeRunnable = null
                    log("Sleep fade-out complete — paused, volume restored")
                    return
                }
                val fraction = 1.0f - step.toFloat() / totalSteps.toFloat()
                p.volume = (initialVol * fraction).coerceAtLeast(0f)
                handler.postDelayed(this, stepMs)
            }
        }
        fadeRunnable = runnable
        handler.postDelayed(runnable, stepMs)
        log("Sleep fade-out started: ${totalSteps}s")
    }

    /**
     * Cancel any running fade and restore the pre-fade volume.
     * K11 fix: only restores volume when a fade was actually in progress —
     * previously this also snapped a non-fading player's volume to 1.0f
     * whenever a new timer was started (startDuration/startEndOfSong), and
     * always restored to 1.0f instead of the user's volume.
     */
    private fun cancelFadeOut() {
        val hadActiveFade = fadeRunnable != null
        fadeRunnable?.let { handler.removeCallbacks(it) }
        fadeRunnable = null
        if (hadActiveFade) getPlayer()?.volume = fadeInitialVolume
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

    /**
     * Unconditional cleanup — call from Service.onDestroy() to guarantee all
     * Handler runnables are removed even if [cancel] was never called.
     * Unlike [cancel], this has no guard check and does not emit events.
     */
    fun release() {
        cancelFadeOut()
        cancelInternal()
    }

    private fun log(msg: String) = NativeLogger.emit("info", "SleepTimer", msg)
}
