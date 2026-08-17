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

    // Set only when insertNext happens while crossfade owns a temporary one-item timeline.
    // The priority is applied after rebuildPlayerQueue() restores the full timeline.
    private var pendingPlayNextIndex: Int = C.INDEX_UNSET

    // ── Queue replacement ─────────────────────────────────────────────────────

    fun setQueue(items: List<Map<String, Any?>>, startIndex: Int, posMs: Long = 0L) {
        pendingPlayNextIndex = C.INDEX_UNSET
        queue            = items
        activeQueueIndex = startIndex.coerceIn(0, (items.size - 1).coerceAtLeast(0))
        notifyQueueIdsChanged()
        val p = getPlayer() ?: return
        p.setMediaItems(items.map { MediaItemFactory.from(it) }, activeQueueIndex, posMs)
        p.prepare()
    }

    fun setTrack(target: Int) {
        pendingPlayNextIndex = C.INDEX_UNSET
        activeQueueIndex = target.coerceIn(0, (queue.size - 1).coerceAtLeast(0))
        getPlayer()?.seekToDefaultPosition(activeQueueIndex)
    }

    /**
     * Session-over clear (notification STOP): empties the queue bookkeeping
     * WITHOUT touching the player. The player is left untouched so no
     * listener emissions / notification refresh fire during the clear (the
     * service is torn down moments later, releasing both players).
     */
    fun clearQueue() {
        pendingPlayNextIndex = C.INDEX_UNSET
        queue = emptyList()
        activeQueueIndex = 0
        notifyQueueIdsChanged()
    }

    // ── Queue mutations ───────────────────────────────────────────────────────

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
            // The player timeline is intentionally not mutated during promotion.
            // Remember the exact inserted queue index so rebuildPlayerQueue() can
            // apply the same shuffle-priority operation after promotion.
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

    // ── Direct index setters (used by crossfade / skip logic) ─────────────────

    fun setActiveQueueIndex(index: Int) {
        activeQueueIndex = index
    }

    fun decrementActiveQueueIndex() {
        if (activeQueueIndex > 0) activeQueueIndex--
    }

    // ── Post-crossfade queue rebuild ──────────────────────────────────────────

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
            log("rebuildPlayerQueue failed: ${e.message}")
            CrossfadeTimelineLogger.stamp("rebuildPlayerQueue: EXCEPTION ${e.message}")
        }
    }

    /**
     * Makes the item inserted by "Putar Selanjutnya" the immediate next item
     * without disabling shuffle or replacing the rest of the randomized order.
     *
     * Media3 keeps shuffle order as a separate permutation of the original
     * playlist indices. Inserting a media item preserves the existing shuffled
     * order as far as possible, so simply inserting at currentIndex + 1 does
     * NOT guarantee that item is next while shuffle is enabled. We therefore
     * move only the requested index to immediately after the current index in
     * the existing shuffle permutation. The remainder of the permutation is
     * unchanged.
     */
    private fun forceNextInShuffleOrder(player: ExoPlayer, priorityIndex: Int) {
        val currentIndex = player.currentMediaItemIndex
        val order = player.shuffleOrder
        val length = order.length

        if (length != player.mediaItemCount ||
            currentIndex == C.INDEX_UNSET ||
            priorityIndex !in 0 until length ||
            currentIndex !in 0 until length ||
            currentIndex == priorityIndex) {
            return
        }

        val permutation = ArrayList<Int>(length)
        var index = order.firstIndex
        while (index != C.INDEX_UNSET && permutation.size < length) {
            permutation += index
            index = order.getNextIndex(index)
        }
        if (permutation.size != length ||
            permutation.toSet().size != length ||
            currentIndex !in permutation ||
            priorityIndex !in permutation) {
            log("insertNext: invalid shuffle permutation — leaving Media3 order unchanged")
            return
        }

        permutation.remove(priorityIndex)
        val currentPosition = permutation.indexOf(currentIndex)
        if (currentPosition < 0) return
        permutation.add(currentPosition + 1, priorityIndex)

        val customOrder = ShuffleOrder.DefaultShuffleOrder(
            permutation.toIntArray(),
            System.nanoTime(),
        )
        player.setShuffleOrder(customOrder)

        log("insertNext: shuffle priority → current=$currentIndex next=$priorityIndex")
    }

    private fun log(msg: String) = NativeLogger.emit("info", "Queue", msg)

    private fun notifyQueueIdsChanged() {
        onQueueIdsChanged(
            queue.mapNotNull { item ->
                (item["id"] as? Number)?.toInt()?.takeIf { it > 0 }
            }.toSet(),
        )
    }
}
