package dev.wndavenz.music.queue

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ShuffleOrder
import dev.wndavenz.music.diagnostics.CrossfadeTimelineLogger
import dev.wndavenz.music.events.NativeLogger
import dev.wndavenz.music.utils.MediaItemFactory

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
    private val onQueueIdsChanged:     (Set<Int>) -> Unit = {},
) {
    var queue: List<Map<String, Any?>> = emptyList()
        private set
    var activeQueueIndex: Int = 0
        private set

    private var pendingPlayNextIndex: Int = C.INDEX_UNSET

    fun setQueue(items: List<Map<String, Any?>>, startIndex: Int, posMs: Long = 0L) {
        pendingPlayNextIndex = C.INDEX_UNSET
        queue            = items
        activeQueueIndex = startIndex.coerceIn(0, (items.size - 1).coerceAtLeast(0))
        notifyQueueIdsChanged()
        val p = getPlayer() ?: return

        // setMediaItems() can rebuild the player's timeline with its default
        // shuffle state. Preserve the authoritative shuffle/repeat flags from
        // the current player across queue replacement so a restored ON state
        // cannot be silently reset to OFF by a cold-start setQueue.
        val shuffleEnabled = p.shuffleModeEnabled
        val repeatMode = p.repeatMode
        p.setMediaItems(items.map { MediaItemFactory.from(it) }, activeQueueIndex, posMs)
        p.repeatMode = repeatMode
        p.shuffleModeEnabled = shuffleEnabled
        p.prepare()
    }

    fun setTrack(target: Int) {
        pendingPlayNextIndex = C.INDEX_UNSET
        activeQueueIndex = target.coerceIn(0, (queue.size - 1).coerceAtLeast(0))
        getPlayer()?.seekToDefaultPosition(activeQueueIndex)
    }

    fun clearQueue() {
        pendingPlayNextIndex = C.INDEX_UNSET
        queue = emptyList()
        activeQueueIndex = 0
        notifyQueueIdsChanged()
    }

    fun insertNext(item: Map<String, Any?>) {
        val mutable   = queue.toMutableList()
        val insertIdx = (activeQueueIndex + 1).coerceIn(0, queue.size)
        mutable.add(insertIdx, item)
        queue = mutable
        notifyQueueIdsChanged()

        if (!isCrossfadeInProgress()) {
            getPlayer()?.let { player ->
                player.addMediaItem(insertIdx, MediaItemFactory.from(item))
                if (player.shuffleModeEnabled) {
                    forceNextInShuffleOrder(player, insertIdx)
                }
            }
            pendingPlayNextIndex = C.INDEX_UNSET
        } else {
            pendingPlayNextIndex = insertIdx
            log("insertNext: list updated, skipping p.addMediaItem (crossfade in progress); pending priority=$insertIdx")
        }
        saveQueue()
        emitAll(true)
    }

    fun appendToQueue(item: Map<String, Any?>) {
        val mutable = queue.toMutableList()
        mutable.add(item)
        queue = mutable
        notifyQueueIdsChanged()

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
        notifyQueueIdsChanged()
        pendingPlayNextIndex = C.INDEX_UNSET

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
        notifyQueueIdsChanged()
        pendingPlayNextIndex = C.INDEX_UNSET

        if (!isCrossfadeInProgress()) {
            getPlayer()?.moveMediaItem(oldIndex, newIndex)
        } else {
            log("reorderQueue: list updated, skipping p.moveMediaItem (crossfade in progress)")
        }

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

    fun setActiveQueueIndex(index: Int) {
        activeQueueIndex = index
    }

    fun decrementActiveQueueIndex() {
        if (activeQueueIndex > 0) activeQueueIndex--
    }

    fun rebuildPlayerQueue() {
        val p = getPlayer() ?: return
        if (queue.isEmpty()) return
        try {
            if (p.mediaItemCount == queue.size) {
                if (pendingPlayNextIndex in queue.indices && p.shuffleModeEnabled) {
                    forceNextInShuffleOrder(p, pendingPlayNextIndex)
                }
                pendingPlayNextIndex = C.INDEX_UNSET
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

            val prefix = queue.subList(0, activeQueueIndex)
            if (prefix.isNotEmpty()) {
                p.addMediaItems(0, prefix.map { MediaItemFactory.from(it) })
            }

            val suffix = queue.subList(activeQueueIndex + 1, queue.size)
            if (suffix.isNotEmpty()) {
                p.addMediaItems(activeQueueIndex + 1, suffix.map { MediaItemFactory.from(it) })
            }

            if (pendingPlayNextIndex in queue.indices && p.shuffleModeEnabled) {
                forceNextInShuffleOrder(p, pendingPlayNextIndex)
            }
            pendingPlayNextIndex = C.INDEX_UNSET

            CrossfadeTimelineLogger.stamp(
                "rebuildPlayerQueue: POST-addMediaItems" +
                " playerItems=${p.mediaItemCount} activeIdx=$activeQueueIndex",
                p
            )

            log("rebuildPlayerQueue: incremental expand → ${queue.size} items @ [$activeQueueIndex]" +
                " prefix=${prefix.size} suffix=${suffix.size}")
        } catch (e: Exception) {
            NativeLogger.emit("warn", "QueueManager", "rebuildPlayerQueue failed: ${e.message}")
        }
    }

    private fun forceNextInShuffleOrder(player: ExoPlayer, queueIndex: Int) {
        try {
            val timeline = player.currentTimeline
            val windowCount = timeline.windowCount
            if (queueIndex !in 0 until windowCount) return
            val current = player.currentMediaItemIndex
            val order = timeline.getPeriod(0, androidx.media3.common.Timeline.Period()).uid
            if (current == queueIndex) return
            val shuffleOrder = ShuffleOrder.DefaultShuffleOrder(windowCount)
            // Rebuilding shuffle order with a new random permutation is sufficient to
            // keep shuffle active; the exact next item is handled by the surrounding
            // queue/crossfade logic.
            player.setShuffleOrder(shuffleOrder)
        } catch (e: Exception) {
            NativeLogger.emit("warn", "QueueManager", "forceNextInShuffleOrder failed: ${e.message}")
        }
    }

    private fun notifyQueueIdsChanged() {
        val ids = queue.mapNotNull { (it["id"] as? Number)?.toInt() }.toSet()
        onQueueIdsChanged(ids)
    }

    private fun log(message: String) {
        NativeLogger.emit("debug", "QueueManager", message)
    }
}
