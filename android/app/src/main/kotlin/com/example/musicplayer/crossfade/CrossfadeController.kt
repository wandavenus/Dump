package com.example.musicplayer.crossfade

import android.os.Handler
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.events.NativeLogger
import com.example.musicplayer.events.SessionAuditLogger
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * TRUE CROSSFADE ENGINE
 *
 * Two-phase architecture:
 *
 *   Phase 1 — PRE-WARM  (PREWARM_LEAD_MS before the crossfade point)
 *     PreloadManager.prewarmStandby() starts the standby player at volume=0.
 *     Its AudioTrack and Android AudioFlinger mixing slot are fully active so there is
 *     zero startup latency when the actual fade begins.
 *
 *   Phase 2 — EQUAL-POWER FADE  (crossfadeDurationSec before the end of the track)
 *     Both players output audio simultaneously.  Volumes follow:
 *       old → cos(t × π/2) × targetVol        (perceptually constant power)
 *       new → sin(t × π/2) × targetVol
 *     At t=0:   old=target, new=0
 *     At t=0.5: old=0.707×target, new=0.707×target  ← no loudness dip / pump
 *     At t=1:   old=0,      new=target
 *
 * Bug fixes carried forward:
 *   CE-04: cancel(resetVolume) stops the old player (promotionOwner) AND restores the new
 *          player's volume — not just one or the other.
 *   QS-02/03/CE-03: onCrossfadeComplete callback triggers queue rebuild on promoted player.
 *   CE-02: explicit READY-state check with diagnostic log before promotion.
 *
 * MIUI 12 / Android 11 notes:
 *   - The standby player is created with setHandleAudioBecomingNoisy(false) in
 *     Media3PlaybackService.createConfiguredPlayer() so only the active player auto-responds
 *     to headphone unplug.
 *   - Audio focus is held by the service (not per-player) so both players share the same
 *     focus grant during the overlap window; we never request a second focus during a fade.
 */
@UnstableApi
class CrossfadeController(
    private val handler: Handler,
    private val getActivePlayer:      () -> ExoPlayer?,
    private val getStandbyPlayer:     () -> ExoPlayer?,
    private val setActivePlayer:      (ExoPlayer) -> Unit,
    private val switchSessionPlayer:  (ExoPlayer) -> Unit,
    private val preloadManager:       PreloadManager,
    private val getVolumeBeforeDuck:  () -> Float,
    private val hasAudioFocus:        () -> Boolean,
    private val requestAudioFocus:    () -> Boolean,
    private val getQueue:             () -> List<Map<String, Any?>>,
    private val getActiveQueueIndex:  () -> Int,
    private val setActiveQueueIndex:  (Int) -> Unit,
    private val onCrossfadeComplete:  () -> Unit,
    private val emitAll:              () -> Unit,
    private val refreshNotification:  () -> Unit,
    // Called at the very start of beginCrossfade() so offload scheduling can be
    // disabled before the first 16 ms Handler tick fires.
    private val onCrossfadeStarting:  () -> Unit = {},
) {
    companion object {
        /** How far before the crossfade point we start the standby audio pipeline. */
        const val PREWARM_LEAD_MS = 1500L

        /** Fade animation step — ~62 fps for smooth perceived volume curve. */
        const val FADE_STEP_MS = 16L

        /** Minimum actual fade duration regardless of track-end proximity. */
        const val MIN_FADE_MS = 80L
    }

    var crossfadeDurationSec: Float = 0f
        private set
    var crossfadeInProgress: Boolean = false
        private set
    var promotionTriggered: Boolean = false
        private set
    var promotionOwner: ExoPlayer? = null
        private set

    private var prewarmTriggered: Boolean = false
    private var crossfadeFadeRunnable: Runnable? = null

    // ── Public API ────────────────────────────────────────────────────────────

    fun setDuration(sec: Float) {
        crossfadeDurationSec = sec
    }

    /**
     * Called every 200 ms from the position ticker.
     *
     * Drives both phases:
     *   • enters pre-warm zone → warms up standby pipeline
     *   • enters fade zone     → begins equal-power crossfade
     */
    fun maybeCrossfadeOut() {
        if (crossfadeDurationSec <= 0f || promotionTriggered || crossfadeInProgress) return
        val p = getActivePlayer() ?: return

        val dur = p.duration
        if (dur <= 0L || dur == C.TIME_UNSET) return
        if (!p.hasNextMediaItem() && p.repeatMode == Player.REPEAT_MODE_OFF) return

        // Ensure next track is ready in standby
        preloadManager.preloadNextTrack()
        val standby = getStandbyPlayer() ?: return
        if (standby.mediaItemCount == 0) return

        val crossMs   = (crossfadeDurationSec * 1000f).toLong().coerceAtLeast(MIN_FADE_MS)
        val remaining = (dur - p.currentPosition).coerceAtLeast(0L)

        // ── Phase 1: pre-warm ─────────────────────────────────────────────────
        if (!prewarmTriggered && remaining <= (crossMs + PREWARM_LEAD_MS)) {
            prewarmTriggered = true
            preloadManager.prewarmStandby()
            log("Pre-warm triggered @ remaining=${remaining}ms (crossMs=${crossMs}ms)")
        }

        // ── Phase 2: crossfade ────────────────────────────────────────────────
        if (remaining in 1L..(crossMs + 250L)) {
            val actualFadeMs = minOf(crossMs, remaining).coerceAtLeast(MIN_FADE_MS)
            log("Crossfade trigger: remaining=${remaining}ms fade=${actualFadeMs}ms")
            beginCrossfade(actualFadeMs)
        }
    }

    /**
     * Cancel any pending or in-progress crossfade.
     *
     * CE-04 fix: stops the old player (promotionOwner) AND restores the new player's volume.
     */
    fun cancel(resetVolume: Boolean) {
        crossfadeFadeRunnable?.let { handler.removeCallbacks(it) }
        crossfadeFadeRunnable = null

        // Stop the old player if we're mid-fade
        if (crossfadeInProgress) {
            SessionAuditLogger.onCrossfadeCancelled("external cancel, resetVolume=$resetVolume")
            promotionOwner?.let { old ->
                try { old.pause()           } catch (_: Exception) {}
                try { old.stop()            } catch (_: Exception) {}
                try { old.clearMediaItems() } catch (_: Exception) {}
            }
        }

        crossfadeInProgress  = false
        promotionTriggered   = false
        prewarmTriggered     = false
        promotionOwner       = null

        if (resetVolume) getActivePlayer()?.volume = getVolumeBeforeDuck().coerceIn(0f, 1f)
    }

    /**
     * Called from onMediaItemTransition when a track changes outside of an active crossfade.
     * Resets promotionTriggered + prewarmTriggered so the next track can trigger a fresh fade.
     */
    fun resetPromotionState() {
        if (!crossfadeInProgress) {
            promotionTriggered = false
            prewarmTriggered   = false
        }
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun beginCrossfade(actualFadeMs: Long) {
        if (crossfadeInProgress) return

        val standby   = getStandbyPlayer() ?: return
        val current   = getActivePlayer()  ?: return
        val nextIndex = preloadManager.preloadedQueueIndex
        val queue     = getQueue()

        if (standby === current) return
        if (standby.mediaItemCount == 0 || nextIndex !in queue.indices) return

        // Diagnostic: log if standby isn't READY yet (pre-warm may not have settled)
        when (standby.playbackState) {
            Player.STATE_READY    -> log("Standby is READY — clean crossfade start")
            Player.STATE_BUFFERING -> log("warn: standby still BUFFERING — may have startup gap")
            Player.STATE_IDLE     -> {
                log("warn: standby is IDLE — forcing prepare+play")
                standby.prepare()
            }
            else                  -> log("warn: standby state=${standby.playbackState}")
        }

        crossfadeInProgress = true
        promotionTriggered  = true
        promotionOwner      = current

        // Notify AudioOffloadManager BEFORE the first Handler tick so offload
        // scheduling is disabled before the 16 ms volume-fade runnable starts.
        onCrossfadeStarting()
        val standbyTitle = queue.getOrNull(nextIndex)?.get("title") as? String ?: "Unknown"
        SessionAuditLogger.onCrossfadeStarting(actualFadeMs, standbyTitle)
        //setActiveQueueIndex(nextIndex)

        // Detach the old player's trailing queue tail to free memory
        try {
            val ci = current.currentMediaItemIndex
            if (current.mediaItemCount > ci + 1) {
                current.removeMediaItems(ci + 1, current.mediaItemCount)
            }
        } catch (e: Exception) {
            log("removeMediaItems(old tail): ${e.message}")
        }

        // Promote standby → active BEFORE starting playback so the MediaSession
        // immediately shows the new track in the notification.
        standby.volume = 0f
        setActivePlayer(standby)
        switchSessionPlayer(standby)

        // Ensure audio focus before starting the new player
        if (standby.playbackState != Player.STATE_READY) standby.prepare()
        if (hasAudioFocus() || requestAudioFocus()) {
            standby.play()
        }

        log("Promotion complete → [$nextIndex] '${queue[nextIndex]["title"]}' (fade=${actualFadeMs}ms)")
        emitAll()
        refreshNotification()

        runEqualPowerFade(
        standby,
        current,
        nextIndex,
        actualFadeMs,
        )
        }

    /**
     * Equal-power fade animation.
     *
     * Volumes at linear progress t ∈ [0,1]:
     *   old = targetVol × cos(t × π/2)
     *   new = targetVol × sin(t × π/2)
     *
     * Step interval: FADE_STEP_MS (16 ms ≈ 62 fps) for a smooth perceptual curve.
     */
    private fun runEqualPowerFade(
    newPlayer: ExoPlayer,
    oldPlayer: ExoPlayer,
    nextIndex: Int,
    durationMs: Long,
) {
        crossfadeFadeRunnable?.let { handler.removeCallbacks(it) }
        val targetVol  = getVolumeBeforeDuck().coerceIn(0f, 1f)
        val steps      = (durationMs / FADE_STEP_MS).coerceAtLeast(1L).toInt()
        val stepMs     = (durationMs / steps).coerceAtLeast(1L)
        var step       = 0

        val runnable = object : Runnable {
            override fun run() {
                // Guard: abort if the active player changed underneath us
                if (getActivePlayer() !== newPlayer) {
                    crossfadeInProgress   = false
                    promotionTriggered    = false
                    prewarmTriggered      = false
                    promotionOwner        = null
                    crossfadeFadeRunnable = null
                    log("Fade aborted — active player changed mid-fade")
                    return
                }

                if (step >= steps) {
                    // ── Crossfade complete ─────────────────────────────────────
                    setActiveQueueIndex(nextIndex) 
                    newPlayer.volume = targetVol

                    // Stop and release the old player's audio resources
                    try { oldPlayer.pause()           } catch (_: Exception) {}
                    try { oldPlayer.stop()            } catch (_: Exception) {}
                    try { oldPlayer.clearMediaItems() } catch (_: Exception) {}

                    setActivePlayer(newPlayer)
                    switchSessionPlayer(newPlayer)
                   
                    crossfadeInProgress   = false
                    promotionTriggered    = false
                    prewarmTriggered      = false
                    promotionOwner        = null
                    crossfadeFadeRunnable = null
                    preloadManager.resetPreloadedIndex()

                    log("Crossfade complete: ${durationMs}ms, $steps steps @ ${stepMs}ms/step")
                    SessionAuditLogger.onCrossfadeComplete(durationMs, steps)

                    // Rebuild full queue on promoted player + re-attach effects
                    onCrossfadeComplete()
                    emitAll()
                    refreshNotification()

                    // Preload the track after the newly active one
                    preloadManager.preloadNextTrack(force = true)
                    return
                }

                // ── Equal-power volume update ──────────────────────────────────
                val t      = step.toFloat() / steps.toFloat()
                val theta  = (t * PI / 2.0).toFloat()
                oldPlayer.volume = (targetVol * cos(theta)).coerceIn(0f, targetVol)
                newPlayer.volume = (targetVol * sin(theta)).coerceIn(0f, targetVol)
                step++
                handler.postDelayed(this, stepMs)
            }
        }
        crossfadeFadeRunnable = runnable
        handler.post(runnable)
        log("Equal-power fade started: ${durationMs}ms, ~$steps steps, ${stepMs}ms/step")
    }

    private fun log(msg: String) = NativeLogger.emit("info", "Crossfade", msg)
}
