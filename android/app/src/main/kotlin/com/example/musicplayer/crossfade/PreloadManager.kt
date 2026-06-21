package com.example.musicplayer.crossfade

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.events.NativeLogger
import com.example.musicplayer.utils.MediaItemFactory

/**
 * Manages the standby (secondary) player used for crossfade preloading.
 *
 * Responsible for:
 * - Creating / releasing the standby ExoPlayer on demand
 * - Preloading the next track into standby
 * - Clearing / releasing standby state
 */
@UnstableApi
class PreloadManager(
    private val getActivePlayer:    () -> ExoPlayer?,
    private val getStandbyPlayer:   () -> ExoPlayer?,
    private val createPlayer:       () -> ExoPlayer,
    private val attachListener:     (ExoPlayer) -> Unit,
    private val detachListener:     (ExoPlayer) -> Unit,
    private val setStandbyPlayer:   (ExoPlayer?) -> Unit,
    private val getActivePlayerRef: () -> ExoPlayer?,  // same as active but for identity checks
    private val getCrossfadeDurationSec: () -> Float,
    private val getQueue:           () -> List<Map<String, Any?>>,
) {
    var preloadedQueueIndex: Int = C.INDEX_UNSET
        private set

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Ensures a standby player exists and returns it.
     * Returns null if crossfade is disabled.
     */
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
     * Preload the next queue track into the standby player.
     *
     * @param force Reload even if the standby already has the next index preloaded.
     */
    fun preloadNextTrack(force: Boolean = false) {
        if (getCrossfadeDurationSec() <= 0f) return
        val queue   = getQueue()
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
            standby.pause()
            standby.stop()
            standby.clearMediaItems()
            standby.volume             = 0f
            standby.repeatMode         = current.repeatMode
            standby.shuffleModeEnabled = current.shuffleModeEnabled
            standby.playbackParameters = current.playbackParameters
            standby.setMediaItem(MediaItemFactory.from(queue[nextIndex]))
            standby.prepare()
            preloadedQueueIndex = nextIndex
            log("preloadNextTrack → [$nextIndex] '${queue[nextIndex]["title"]}'")
        } catch (e: Exception) {
            preloadedQueueIndex = C.INDEX_UNSET
            log("preloadNextTrack failed: ${e.message}")
        }
    }

    /** Stops and clears the standby player's queue without releasing it. */
    fun clearStandbyQueue() {
        getStandbyPlayer()?.let { standby ->
            try { standby.pause()           } catch (_: Exception) {}
            try { standby.stop()            } catch (_: Exception) {}
            try { standby.clearMediaItems() } catch (_: Exception) {}
        }
        preloadedQueueIndex = C.INDEX_UNSET
    }

    /** Fully releases the standby player instance. */
    fun releaseStandbyPlayer() {
        val standby = getStandbyPlayer() ?: return
        detachListener(standby)
        try { standby.release() } catch (_: Exception) {}
        setStandbyPlayer(null)
        preloadedQueueIndex = C.INDEX_UNSET
    }

    /** Resets the preloaded index (called after promotion completes). */
    fun resetPreloadedIndex() {
        preloadedQueueIndex = C.INDEX_UNSET
    }

    private fun log(msg: String) = NativeLogger.emit("info", "Preload", msg)
}
