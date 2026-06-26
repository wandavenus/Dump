package com.example.musicplayer.queue

import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.diagnostics.CrossfadeTimelineLogger
import com.example.musicplayer.events.NativeLogger
import com.example.musicplayer.utils.MediaItemFactory

/**
 * Owns the authoritative queue list and activeQueueIndex.
 *
 * Applies mutations both to the in-memory list and to ExoPlayer's internal playlist,
 * skipping ExoPlayer mutations safely when crossfade is in progress.
 *
 * Fixes:
 * QS-02/QS-03: During crossfade, ExoPlayer mutations are deferred to the in-memory list.
 *   After crossfade promotion completes, rebuildPlayerQueue() is called to expand the
 *   single-item promoted player queue to the full N-item queue via addMediaItems().
 *   See CROSSFADE_OPTION_B_DESIGN.md for the rationale.
 *
 * reorderQueue activeQueueIndex adjustment logic is preserved exactly from the original.
 */
@UnstableApi
class QueueManager(
    private val getPlayer:             () -> ExoPlayer?,
    private val isCrossfadeInProgress: () -> Boolean,
    private val saveQueue:             () -> Unit,
    private val emitAll:               (emitQueue: Boolean) -> Unit,
) {
    var queue: List<Map<String, Any?>> = emptyList()
        private set
    var activeQueueIndex: Int = 0
        private set

    // ── Queue replacement ─────────────────────────────────────────────────────

    fun setQueue(items: List<Map<String, Any?>>, startIndex: Int, posMs: Long = 0L) {
        // LOW-08: Callers MUST cancel any active crossfade before calling setQueue.
        // TransportCommands.dispatch("setQueue") enforces this via crossfadeController.cancel().
        // Calling setQueue mid-crossfade would abruptly interrupt the fading audio.
        queue            = items
        activeQueueIndex = startIndex.coerceIn(0, (items.size - 1).coerceAtLeast(0))
        val p = getPlayer() ?: return
        p.setMediaItems(items.map { MediaItemFactory.from(it) }, activeQueueIndex, posMs)
        p.prepare()
    }

    fun setTrack(target: Int) {
        activeQueueIndex = target.coerceIn(0, (queue.size - 1).coerceAtLeast(0))
        getPlayer()?.seekToDefaultPosition(activeQueueIndex)
    }

    // ── Queue mutations ───────────────────────────────────────────────────────

    fun insertNext(item: Map<String, Any?>) {
        val mutable   = queue.toMutableList()
        val insertIdx = (activeQueueIndex + 1).coerceIn(0, queue.size)
        mutable.add(insertIdx, item)
        queue = mutable

        if (!isCrossfadeInProgress()) {
            getPlayer()?.addMediaItem(insertIdx, MediaItemFactory.from(item))
        } else {
            log("insertNext: list updated, skipping p.addMediaItem (crossfade in progress)")
        }
        saveQueue()
        emitAll(true)
    }

    fun appendToQueue(item: Map<String, Any?>) {
        val mutable = queue.toMutableList()
        mutable.add(item)
        queue = mutable

        if (!isCrossfadeInProgress()) {
            getPlayer()?.addMediaItem(MediaItemFactory.from(item))
        } else {
            log("appendToQueue: list updated, skipping p.addMediaItem (crossfade in progress)")
        }
        saveQueue()
        emitAll(true)
    }

    fun removeFromQueue(index: Int) {
        if (index !in queue.indices) return
        val mutable = queue.toMutableList()
        mutable.removeAt(index)
        queue = mutable

        // Adjust activeQueueIndex
        when {
            index < activeQueueIndex                          -> activeQueueIndex--
            index == activeQueueIndex && queue.isEmpty()      -> activeQueueIndex = 0
            index == activeQueueIndex && activeQueueIndex >= queue.size ->
                activeQueueIndex = queue.size - 1
        }
        if (activeQueueIndex !in queue.indices) {
            activeQueueIndex = (queue.size - 1).coerceAtLeast(0)
        }

        if (!isCrossfadeInProgress()) {
            getPlayer()?.removeMediaItem(index)
        } else {
            log("removeFromQueue: list updated, skipping p.removeMediaItem (crossfade in progress)")
        }
        saveQueue()
        emitAll(true)
        log("removeFromQueue: idx=$index remaining=${queue.size}")
    }

    fun reorderQueue(oldIndex: Int, newIndex: Int) {
        if (oldIndex !in queue.indices || newIndex !in queue.indices || oldIndex == newIndex) return
        val mutable = queue.toMutableList()
        val item    = mutable.removeAt(oldIndex)
        mutable.add(newIndex, item)
        queue = mutable

        if (!isCrossfadeInProgress()) {
            getPlayer()?.moveMediaItem(oldIndex, newIndex)
        } else {
            log("reorderQueue: list updated, skipping p.moveMediaItem (crossfade in progress)")
        }

        // Adjust activeQueueIndex to follow the moved item
        activeQueueIndex = when {
            oldIndex == activeQueueIndex                                   -> newIndex
            oldIndex < activeQueueIndex && newIndex >= activeQueueIndex    -> activeQueueIndex - 1
            oldIndex > activeQueueIndex && newIndex <= activeQueueIndex    -> activeQueueIndex + 1
            else                                                           -> activeQueueIndex
        }
        if (activeQueueIndex !in queue.indices) {
            activeQueueIndex = (queue.size - 1).coerceAtLeast(0)
        }
        saveQueue()
        emitAll(true)
        log("reorderQueue: [$oldIndex] → [$newIndex]")
    }

    // ── Direct index setters (used by crossfade / skip logic) ─────────────────

    fun setActiveQueueIndex(index: Int) {
        activeQueueIndex = index
    }

    fun decrementActiveQueueIndex() {
        if (activeQueueIndex > 0) activeQueueIndex--
    }

    // ── Post-crossfade queue rebuild ──────────────────────────────────────────

    /**
     * Option B: incremental queue rebuild via addMediaItems().
     *
     * After a crossfade promotion the new active player has exactly 1 MediaItem
     * (the track loaded by PreloadManager at index 0). Its MediaSourceHolder UID
     * is the one currently held by the active MediaPeriod and audio renderer.
     *
     * We expand the queue by inserting the items that belong BEFORE and AFTER that
     * single item using two addMediaItems() calls. Internally, addMediaItems() calls
     * addMediaSourcesInternal() which inserts new MediaSourceHolder objects into
     * mediaSourceHolderSnapshots WITHOUT clearing the list. The playing holder's UID
     * is unchanged, so the active MediaPeriod remains valid and handleMediaSourceListInfoRefreshed()
     * resolves the new window index without invoking resetInternal() or disableRenderers().
     *
     * Contrast with setMediaItems(), which calls setMediaSourcesInternal(), clears
     * mediaSourceHolderSnapshots entirely, allocates new UIDs for every item including
     * the one currently playing, then forces resetInternal() + disableRenderers() —
     * the direct cause of the 50–200 ms audible dropout documented in CROSSFADE_OPTION_B_DESIGN.md.
     *
     * Edge cases:
     *   queue.size == 1          → both prefix and suffix are empty; no calls made.
     *   activeQueueIndex == 0    → prefix empty; only suffix call is made.
     *   activeQueueIndex == last → suffix empty; only prefix call is made.
     *   p.mediaItemCount already == queue.size → already fully populated; skip.
     */
    fun rebuildPlayerQueue() {
        val p = getPlayer() ?: return
        if (queue.isEmpty()) return
        try {
            // Guard: if the promoted player already holds the full queue (unexpected but
            // safe to detect), skip expansion to avoid redundant addMediaItems() calls.
            if (p.mediaItemCount == queue.size) {
                log("rebuildPlayerQueue: player already has ${queue.size} items — skipping expansion")
                return
            }

            CrossfadeTimelineLogger.stamp(
                "rebuildPlayerQueue: PRE-addMediaItems" +
                " queueSize=${queue.size} activeIdx=$activeQueueIndex" +
                " playerItems=${p.mediaItemCount}" +
                " currentItem='${p.currentMediaItem?.mediaId ?: "null"}'" +
                " targetItem='${queue.getOrNull(activeQueueIndex)?.get("uri") ?: "?"}'",
                p
            )

            // Items that belong before the currently playing track in the full queue.
            // Inserting at index 0 shifts the current item's window index from 0 to
            // activeQueueIndex. The MediaSourceHolder UID of the playing item is unchanged.
            val prefix = queue.subList(0, activeQueueIndex)
            if (prefix.isNotEmpty()) {
                p.addMediaItems(0, prefix.map { MediaItemFactory.from(it) })
                CrossfadeTimelineLogger.stamp(
                    "rebuildPlayerQueue: addMediaItems(0, prefix[${prefix.size}]) done" +
                    " playerItems=${p.mediaItemCount} currentIdx=${p.currentMediaItemIndex}",
                    p
                )
            }

            // Items that belong after the currently playing track.
            // Inserted at activeQueueIndex + 1; current item stays at activeQueueIndex.
            val suffix = queue.subList(activeQueueIndex + 1, queue.size)
            if (suffix.isNotEmpty()) {
                p.addMediaItems(activeQueueIndex + 1, suffix.map { MediaItemFactory.from(it) })
                CrossfadeTimelineLogger.stamp(
                    "rebuildPlayerQueue: addMediaItems(${activeQueueIndex + 1}, suffix[${suffix.size}]) done" +
                    " playerItems=${p.mediaItemCount} currentIdx=${p.currentMediaItemIndex}",
                    p
                )
            }

            CrossfadeTimelineLogger.stamp(
                "rebuildPlayerQueue: POST-addMediaItems" +
                " playerItems=${p.mediaItemCount} activeIdx=$activeQueueIndex",
                p
            )

            log("rebuildPlayerQueue: incremental expand → ${queue.size} items @ [$activeQueueIndex]" +
                " prefix=${prefix.size} suffix=${suffix.size}")
        } catch (e: Exception) {
            log("rebuildPlayerQueue failed: ${e.message}")
            CrossfadeTimelineLogger.stamp("rebuildPlayerQueue: EXCEPTION ${e.message}")
        }
    }

    private fun log(msg: String) = NativeLogger.emit("info", "Queue", msg)
}
