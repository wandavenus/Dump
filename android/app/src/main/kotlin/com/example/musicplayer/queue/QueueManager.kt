package com.example.musicplayer.queue

import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.events.NativeLogger
import com.example.musicplayer.utils.MediaItemFactory

/**
 * Owns the authoritative queue list and activeQueueIndex.
 *
 * Applies mutations both to the in-memory list and to ExoPlayer's internal playlist,
 * skipping ExoPlayer mutations safely when crossfade is in progress.
 *
 * Fixes:
 * QS-02/QS-03: During crossfade, ExoPlayer mutations are deferred to a pending list.
 *   After crossfade promotion completes, rebuildPlayerQueue() is called to push the
 *   full current queue back into the active player, so skipNext / mutations work.
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
     * QS-02/QS-03/CE-03 fix: After a crossfade promotion, the new active player
     * only has 1 media item (the preloaded track at position 0). Rebuild the full
     * queue by prepending/appending items WITHOUT touching the current item to avoid
     * interrupting playback.
     *
     * After this call ExoPlayer's currentMediaItemIndex == activeQueueIndex.
     */
    fun rebuildPlayerQueue() {
        val p = getPlayer() ?: return
        if (queue.isEmpty()) return
        try {
            // Append all items that should come after the current track
            val afterItems = queue.drop(activeQueueIndex + 1).map { MediaItemFactory.from(it) }
            if (afterItems.isNotEmpty()) {
                p.addMediaItems(afterItems)
            }
            // Prepend all items that should come before the current track
            // Adding at index 0 shifts the current item to activeQueueIndex — correct.
            if (activeQueueIndex > 0) {
                val beforeItems = queue.take(activeQueueIndex).map { MediaItemFactory.from(it) }
                p.addMediaItems(0, beforeItems)
            }
            log("rebuildPlayerQueue: ${queue.size} items @ [$activeQueueIndex] (non-interrupting)")
        } catch (e: Exception) {
            log("rebuildPlayerQueue failed: ${e.message}")
        }
    }

    private fun log(msg: String) = NativeLogger.emit("info", "Queue", msg)
}
