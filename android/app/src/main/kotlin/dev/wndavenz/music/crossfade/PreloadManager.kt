package dev.wndavenz.music.crossfade

import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import dev.wndavenz.music.diagnostics.CrossfadeTimelineLogger
import dev.wndavenz.music.events.NativeLogger
import dev.wndavenz.music.utils.MediaItemFactory

/**
 * Manages the standby (secondary) player used for true crossfade.
 *
 * Two-phase standby lifecycle:
 *   1. PRELOADED  — setMediaItem + prepare(); buffered but silent (volume=0).
 *   2. PREWARMED  — play() at volume=0; audio pipeline is warm, no startup latency.
 *
 * The CrossfadeController drives the transition from PRELOADED → PREWARMED by calling
 * prewarmStandby() ~1.5 s before the actual crossfade begins.  This guarantees that
 * both players are already outputting audio when the equal-power fade starts, so the
 * overlap is truly simultaneous from the very first fade step.
 *
 * MIUI 12 note: standby player is created with setHandleAudioBecomingNoisy(false) so
 * only the active player responds to headphone unplug events.
 */
@UnstableApi
class PreloadManager(
    private val getActivePlayer:         () -> ExoPlayer?,
    private val getStandbyPlayer:        () -> ExoPlayer?,
    private val createPlayer:            () -> ExoPlayer,
    private val attachListener:          (ExoPlayer) -> Unit,
    private val detachListener:          (ExoPlayer) -> Unit,
    private val setStandbyPlayer:        (ExoPlayer?) -> Unit,
    private val getActivePlayerRef:      () -> ExoPlayer?,
    private val getCrossfadeDurationSec: () -> Float,
    private val getQueue:                () -> List<Map<String, Any?>>,
) {
    var preloadedQueueIndex: Int = C.INDEX_UNSET
        private set

    /** True once prewarmStandby() has been called for the current preloaded track. */
    var isPrewarmed: Boolean = false
        private set

    // ── Public API ────────────────────────────────────────────────────────────

    fun ensureStandbyPlayer(): ExoPlayer? {
        if (getCrossfadeDurationSec() <= 0f) return null
        val existing = getStandbyPlayer()
        if (existing != null) return existing
        val created = createPlayer()
        setStandbyPlayer(created)
        attachListener(created)
        return created
    }

    /**
     * Preload the next queue track into the standby player (PRELOADED state).
     * Does NOT start playback — that happens via prewarmStandby().
     *
     * @param force Reload even if the standby already has the next index preloaded.
     */
    fun preloadNextTrack(force: Boolean = false) {
        if (getCrossfadeDurationSec() <= 0f) return
        val queue = getQueue()
        if (queue.isEmpty()) return
        val current = getActivePlayer() ?: return
        val standby = ensureStandbyPlayer() ?: return
        if (standby === current) return

        val nextIndex = current.nextMediaItemIndex
        if (nextIndex == C.INDEX_UNSET || nextIndex !in queue.indices) {
            clearStandbyQueue(); return
        }
        if (!force && standby.mediaItemCount > 0 && preloadedQueueIndex == nextIndex) return

        try {
            // Always stop/clear before reconfiguring to avoid stale state
            try { standby.stop() }         catch (_: Exception) {}
            try { standby.clearMediaItems() } catch (_: Exception) {}

            standby.volume             = 0f
            standby.repeatMode         = current.repeatMode
            standby.shuffleModeEnabled = current.shuffleModeEnabled
            standby.playbackParameters = current.playbackParameters
            standby.setMediaItem(MediaItemFactory.from(queue[nextIndex]))
            standby.prepare()
            isPrewarmed         = false
            preloadedQueueIndex = nextIndex
            val title = queue[nextIndex]["title"] as? String ?: "Unknown"
            log("preloadNextTrack → [$nextIndex] '$title'")
        } catch (e: Exception) {
            preloadedQueueIndex = C.INDEX_UNSET
            isPrewarmed         = false
            log("preloadNextTrack failed: ${e.message}")
        }
    }

    /**
     * Phase-2 pre-warm: start the standby player at volume=0 so its audio
     * pipeline (AudioTrack, AudioMixer) is fully running before the fade begins.
     *
     * Called by CrossfadeController ~PREWARM_LEAD_MS before the actual crossfade.
     * Safe to call multiple times — subsequent calls are no-ops.
     */
    fun prewarmStandby() {
        if (isPrewarmed) return
        val standby = getStandbyPlayer() ?: return
        if (standby.mediaItemCount == 0 || preloadedQueueIndex == C.INDEX_UNSET) return

        CrossfadeTimelineLogger.stamp("prewarmStandby: ENTER", standby)

        standby.volume = 0f

        when (standby.playbackState) {
            Player.STATE_IDLE   -> {
                CrossfadeTimelineLogger.stamp("prewarmStandby: standby.prepare() [was IDLE]", standby)
                standby.prepare()
                CrossfadeTimelineLogger.stamp("prewarmStandby: standby.prepare() DONE", standby)
            }
            Player.STATE_ENDED  -> {
                CrossfadeTimelineLogger.stamp("prewarmStandby: standby.seekTo(0)+prepare() [was ENDED]", standby)
                standby.seekTo(0L)
                standby.prepare()
                CrossfadeTimelineLogger.stamp("prewarmStandby: standby.seekTo+prepare() DONE", standby)
            }
            else -> {
                CrossfadeTimelineLogger.stamp(
                    "prewarmStandby: standby already prepared (state=${standby.playbackState})", standby)
            }
        }

        // Do NOT call standby.play() here.
        // Calling play() during prewarm causes the media clock to advance for the full
        // PREWARM_LEAD_MS window, so by the time beginCrossfade() fires the standby is
        // already ~1 s into the track and the intro is silently skipped.
        // A subsequent seekTo(0) to correct this triggers a decoder/renderer flush on a
        // playing player, which destroys the audio overlap and produces a hard cut instead
        // of a smooth crossfade.
        //
        // prepare() alone is sufficient to warm the decoder and fill ExoPlayer's
        // LoadControl buffer (STATE_READY). The AudioTrack OS object is created on the
        // first play() call in beginCrossfade(), which takes ~20 ms — imperceptible at
        // the near-zero volume of the first fade step on any crossfade >= 1 s.
        isPrewarmed = true
        log("prewarmStandby: standby decoder buffered at pos=0, waiting for beginCrossfade()")
    }

    /** Stops and clears the standby player's queue without releasing it. */
    fun clearStandbyQueue() {
        getStandbyPlayer()?.let { standby ->
            try { standby.pause()           } catch (_: Exception) {}
            try { standby.stop()            } catch (_: Exception) {}
            try { standby.clearMediaItems() } catch (_: Exception) {}
        }
        preloadedQueueIndex = C.INDEX_UNSET
        isPrewarmed         = false
    }

    /** Fully releases the standby player instance. */
    fun releaseStandbyPlayer() {
        val standby = getStandbyPlayer() ?: return
        detachListener(standby)
        try { standby.release() } catch (_: Exception) {}
        setStandbyPlayer(null)
        preloadedQueueIndex = C.INDEX_UNSET
        isPrewarmed         = false
    }

    /** Resets the preloaded index (called after promotion completes). */
    fun resetPreloadedIndex() {
        preloadedQueueIndex = C.INDEX_UNSET
        isPrewarmed         = false
    }

    private fun log(msg: String) = NativeLogger.emit("info", "Preload", msg)
}
