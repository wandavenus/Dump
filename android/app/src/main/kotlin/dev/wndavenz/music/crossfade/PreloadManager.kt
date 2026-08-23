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
 *   1. PRELOADED — setMediaItem + prepare(); buffered but silent (volume=0).
 *   2. PREWARMED — prepare() keeps the decoder buffered before promotion.
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
     * During promotion the active player temporarily owns a one-item timeline.
     * That timeline is not authoritative, so it must never be used to derive the
     * next queue index. The full queue is restored when promotion completes and
     * the completion path calls this method with force=true.
     */
    fun preloadNextTrack(force: Boolean = false) {
        if (getCrossfadeDurationSec() <= 0f) return
        val queue = getQueue()
        if (queue.isEmpty()) return
        val current = getActivePlayer() ?: return
        val standby = ensureStandbyPlayer() ?: return
        if (standby === current) return

        // A promoted standby contains only the incoming track. Its
        // nextMediaItemIndex therefore describes the temporary one-item timeline,
        // not the authoritative queue, and must not overwrite preloadedQueueIndex.
        if (current.mediaItemCount < queue.size) return

        val nextIndex = current.nextMediaItemIndex
        if (nextIndex == C.INDEX_UNSET || nextIndex !in queue.indices) {
            clearStandbyQueue()
            return
        }
        // Content-identity staleness check (play-next bug): an index match alone is not
        // proof the preload is current — a queue mutation (e.g. insertNext) can shift
        // positions so a STALE preload's index equals the new next index. Verify the
        // standby actually holds queue[nextIndex] via mediaId, mirroring
        // MediaItemFactory's "id ?: path" convention.
        val expectedMediaId =
            (queue[nextIndex]["id"] ?: queue[nextIndex]["path"])?.toString()
        val standbyHoldsExpected =
            expectedMediaId != null && standby.currentMediaItem?.mediaId == expectedMediaId
        if (!force && standby.mediaItemCount > 0 && preloadedQueueIndex == nextIndex &&
            standbyHoldsExpected
        ) {
            return
        }

        try {
            try { standby.stop() } catch (_: Exception) {}
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
            isPrewarmed = false
            log("preloadNextTrack failed: ${e.message}")
        }
    }

    /** Phase-2 pre-warm: prepare the standby decoder at volume=0. */
    fun prewarmStandby() {
        if (isPrewarmed) return
        val standby = getStandbyPlayer() ?: return
        if (standby.mediaItemCount == 0 || preloadedQueueIndex == C.INDEX_UNSET) return

        CrossfadeTimelineLogger.stamp("prewarmStandby: ENTER", standby)
        standby.volume = 0f

        when (standby.playbackState) {
            Player.STATE_IDLE -> {
                CrossfadeTimelineLogger.stamp("prewarmStandby: standby.prepare() [was IDLE]", standby)
                standby.prepare()
                CrossfadeTimelineLogger.stamp("prewarmStandby: standby.prepare() DONE", standby)
            }
            Player.STATE_ENDED -> {
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

        isPrewarmed = true
        log("prewarmStandby: standby decoder buffered at pos=0, waiting for beginCrossfade()")
    }

    fun clearStandbyQueue() {
        getStandbyPlayer()?.let { standby ->
            try { standby.pause() } catch (_: Exception) {}
            try { standby.stop() } catch (_: Exception) {}
            try { standby.clearMediaItems() } catch (_: Exception) {}
        }
        preloadedQueueIndex = C.INDEX_UNSET
        isPrewarmed = false
    }

    fun releaseStandbyPlayer() {
        val standby = getStandbyPlayer() ?: return
        detachListener(standby)
        try { standby.release() } catch (_: Exception) {}
        setStandbyPlayer(null)
        preloadedQueueIndex = C.INDEX_UNSET
        isPrewarmed = false
    }

    fun resetPreloadedIndex() {
        preloadedQueueIndex = C.INDEX_UNSET
        isPrewarmed = false
    }

    private fun log(msg: String) = NativeLogger.emit("info", "Preload", msg)
}
