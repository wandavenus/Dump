package com.example.musicplayer.crossfade

import android.os.Handler
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import com.example.musicplayer.events.NativeLogger
import kotlin.math.sqrt

/**
 * Manages the crossfade state machine (trigger detection, player promotion,
 * volume fade animation).
 *
 * Fixes:
 * CE-04: cancel(resetVolume=true) now correctly stops the OLD player (promotionOwner)
 *        if a crossfade is in progress, rather than just resetting the new player's volume.
 *        Previously `player?.volume = volumeBeforeDuck` reset the already-promoted new
 *        player, while the old player could remain audible.
 * CE-02: promoteStandby() now checks standby.playbackState before promotion; if standby
 *        is not READY it logs a warning and continues anyway (same audible result as
 *        before but the condition is now explicit and diagnosable).
 * QS-02/QS-03/CE-03: after promotion completes, rebuildActivePlayerQueue() is called
 *        to push the full queue back into the now-active player so subsequent
 *        skipNext / queue mutations work correctly.
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
) {
    var crossfadeDurationSec: Float = 0f
        private set
    var crossfadeInProgress: Boolean = false
        private set
    var promotionTriggered: Boolean = false
        private set
    var promotionOwner: ExoPlayer? = null
        private set

    private var crossfadeFadeRunnable: Runnable? = null

    // ── Public API ────────────────────────────────────────────────────────────

    fun setDuration(sec: Float) {
        crossfadeDurationSec = sec
    }

    /**
     * Called from the position ticker every 200ms.
     * Determines if crossfade should begin based on remaining track time.
     */
    fun maybeCrossfadeOut() {
        if (crossfadeDurationSec <= 0f || promotionTriggered || crossfadeInProgress) return
        val p   = getActivePlayer() ?: return
        val dur = p.duration
        if (dur <= 0L || dur == Long.MIN_VALUE || dur == C.TIME_UNSET) return
        if (!p.hasNextMediaItem()) return

        preloadManager.preloadNextTrack()
        val standby = getStandbyPlayer() ?: return
        if (standby.mediaItemCount == 0) return

        val crossMs   = (crossfadeDurationSec * 1000f).toLong().coerceAtLeast(250L)
        val bufferMs  = 200L
        val remaining = dur - p.currentPosition

        if (remaining in 1L..(crossMs + bufferMs)) {
            val actualFadeMs = minOf(crossMs, remaining)
            log("Triggering crossfade: remaining=${remaining}ms actualFade=${actualFadeMs}ms")
            promoteStandby(actualFadeMs)
        }
    }

    /**
     * Cancel an in-progress or pending crossfade.
     *
     * CE-04 fix: if a promotion already happened (crossfadeInProgress == true),
     * we also stop the old player (promotionOwner) which may still be audible at
     * a partially-faded volume.
     */
    fun cancel(resetVolume: Boolean) {
        crossfadeFadeRunnable?.let { handler.removeCallbacks(it) }
        crossfadeFadeRunnable = null

        if (crossfadeInProgress) {
            val old = promotionOwner
            if (old != null) {
                try { old.pause()           } catch (_: Exception) {}
                try { old.stop()            } catch (_: Exception) {}
                try { old.clearMediaItems() } catch (_: Exception) {}
            }
        }

        crossfadeInProgress = false
        promotionTriggered  = false
        promotionOwner      = null

        if (resetVolume) getActivePlayer()?.volume = getVolumeBeforeDuck()
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun promoteStandby(actualFadeMs: Long) {
        if (crossfadeInProgress) return
        val next      = getStandbyPlayer() ?: return
        val current   = getActivePlayer()  ?: return
        val nextIndex = preloadManager.preloadedQueueIndex
        val queue     = getQueue()
        if (next.mediaItemCount == 0 || nextIndex !in queue.indices) return

        // CE-02 improvement: log if standby is not READY
        if (next.playbackState != ExoPlayer.STATE_READY) {
            log("warn: standby not yet READY (state=${next.playbackState}) — promoting anyway")
        }

        crossfadeInProgress = true
        promotionTriggered  = true
        promotionOwner      = current
        setActiveQueueIndex(nextIndex)
        log("Promoting standby player → [$nextIndex]")

        // Detach the old player's trailing queue items to keep it clean
        try {
            val ci = current.currentMediaItemIndex
            if (current.mediaItemCount > ci + 1) {
                current.removeMediaItems(ci + 1, current.mediaItemCount)
            }
        } catch (e: Exception) {
            log("detach old queue tail: ${e.message}")
        }

        next.volume  = 0f
        setActivePlayer(next)
        switchSessionPlayer(next)

        if (hasAudioFocus() || requestAudioFocus()) next.play()

        startFadeIn(next, current, actualFadeMs)
        emitAll()
        refreshNotification()
    }

    private fun startFadeIn(newPlayer: ExoPlayer, oldPlayer: ExoPlayer, actualFadeMs: Long) {
        crossfadeFadeRunnable?.let { handler.removeCallbacks(it) }
        val durationMs = actualFadeMs.coerceAtLeast(100L)
        val minStepMs  = 8L
        val steps      = (durationMs / minStepMs).coerceIn(8L, 100L).toInt()
        val stepMs     = (durationMs / steps).coerceAtLeast(minStepMs)
        val targetVol  = getVolumeBeforeDuck().coerceIn(0f, 1f)
        var step       = 0

        val runnable = object : Runnable {
            override fun run() {
                if (getActivePlayer() !== newPlayer) {
                    crossfadeInProgress   = false
                    promotionTriggered    = false
                    promotionOwner        = null
                    crossfadeFadeRunnable = null
                    log("Crossfade cancelled — player switched mid-fade")
                    return
                }
                if (step >= steps) {
                    newPlayer.volume = targetVol

                    // Clean up old player
                    try { oldPlayer.pause()           } catch (_: Exception) {}
                    try { oldPlayer.stop()            } catch (_: Exception) {}
                    try { oldPlayer.clearMediaItems() } catch (_: Exception) {}

                    crossfadeInProgress   = false
                    promotionTriggered    = false
                    promotionOwner        = null
                    crossfadeFadeRunnable = null
                    preloadManager.resetPreloadedIndex()

                    log("Crossfade completed (${durationMs}ms)")

                    // QS-02/QS-03/CE-03 fix: rebuild the full queue on the promoted
                    // player so skipNext / queue mutations work correctly after crossfade.
                    onCrossfadeComplete()

                    emitAll()
                    refreshNotification()

                    // Preload the next track on the now-active player
                    preloadManager.preloadNextTrack(force = true)
                    return
                }
                val progress = step.toFloat() / steps.toFloat()
                oldPlayer.volume = (targetVol * sqrt(1f - progress)).coerceIn(0f, 1f)
                newPlayer.volume = (targetVol * sqrt(progress)).coerceIn(0f, 1f)
                step++
                handler.postDelayed(this, stepMs)
            }
        }
        crossfadeFadeRunnable = runnable
        handler.post(runnable)
        log("Crossfade fade-in started (${durationMs}ms, $steps steps)")
    }

    /**
     * Called from onMediaItemTransition when a track changes outside of an active
     * crossfade. Resets promotionTriggered so the next track can trigger a new fade.
     */
    fun resetPromotionState() {
        if (!crossfadeInProgress) promotionTriggered = false
    }

    private fun log(msg: String) = NativeLogger.emit("info", "Crossfade", msg)
}
