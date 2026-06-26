package com.example.musicplayer.queue

import androidx.media3.common.util.UnstableApi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * JVM unit tests for [QueueManager].
 *
 * All tests use [getPlayer] = { null } so no ExoPlayer/Android dependency is
 * exercised — the tests validate pure in-memory list mutation logic only.
 *
 * Test groups:
 *   A. setQueue / setTrack
 *   B. insertNext — index arithmetic
 *   C. appendToQueue
 *   D. removeFromQueue — activeQueueIndex adjustment (4 cases)
 *   E. reorderQueue — activeQueueIndex follows moved item (5 cases)
 *   F. Direct index setters
 *   G. Crossfade guard — list mutations still apply when isCrossfadeInProgress=true
 *   H. rebuildPlayerQueue — safe with null player
 */
@OptIn(UnstableApi::class)
class QueueManagerTest {

    private var saveQueueCount = 0
    private var emitAllCount   = 0

    private fun makeManager(
        isCrossfadeInProgress: () -> Boolean = { false },
    ) = QueueManager(
        getPlayer             = { null },
        isCrossfadeInProgress = isCrossfadeInProgress,
        saveQueue             = { saveQueueCount++ },
        emitAll               = { _ -> emitAllCount++ },
    )

    private fun item(title: String): Map<String, Any?> = mapOf(
        "title" to title,
        "uri"   to "file:///music/${title}.mp3",
    )

    private fun fiveItemQueue() = listOf(
        item("A"), item("B"), item("C"), item("D"), item("E"),
    )

    @Before
    fun setUp() {
        saveQueueCount = 0
        emitAllCount   = 0
    }

    // ═════════════════════════════════════════════════════════════════════════
    // A. setQueue / setTrack
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `A01 setQueue stores the queue`() {
        val mgr = makeManager()
        val q   = fiveItemQueue()
        mgr.setQueue(q, startIndex = 2)
        assertEquals(5, mgr.queue.size)
        assertEquals("C", mgr.queue[2]["title"])
    }

    @Test fun `A02 setQueue clamps startIndex to valid range`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 99)
        assertEquals(4, mgr.activeQueueIndex)  // clamped to last index
    }

    @Test fun `A03 setQueue clamps negative startIndex to 0`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = -3)
        assertEquals(0, mgr.activeQueueIndex)
    }

    @Test fun `A04 setQueue with empty list sets index to 0`() {
        val mgr = makeManager()
        mgr.setQueue(emptyList(), startIndex = 5)
        assertEquals(0, mgr.activeQueueIndex)
        assertTrue(mgr.queue.isEmpty())
    }

    @Test fun `A05 setTrack updates activeQueueIndex`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        mgr.setTrack(3)
        assertEquals(3, mgr.activeQueueIndex)
    }

    @Test fun `A06 setTrack clamps to valid range`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        mgr.setTrack(99)
        assertEquals(4, mgr.activeQueueIndex)
    }

    @Test fun `A07 setTrack clamps negative index to 0`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 2)
        mgr.setTrack(-1)
        assertEquals(0, mgr.activeQueueIndex)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // B. insertNext
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `B01 insertNext inserts immediately after activeQueueIndex`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 2)  // active = C at index 2
        mgr.insertNext(item("X"))
        assertEquals(6, mgr.queue.size)
        assertEquals("X", mgr.queue[3]["title"])  // inserted at 3
    }

    @Test fun `B02 insertNext at end of queue appends correctly`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 4)  // active = last item
        mgr.insertNext(item("X"))
        assertEquals("X", mgr.queue[5]["title"])
    }

    @Test fun `B03 insertNext calls saveQueue`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 1)
        val before = saveQueueCount
        mgr.insertNext(item("X"))
        assertEquals(before + 1, saveQueueCount)
    }

    @Test fun `B04 insertNext calls emitAll`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 1)
        val before = emitAllCount
        mgr.insertNext(item("X"))
        assertEquals(before + 1, emitAllCount)
    }

    @Test fun `B05 insertNext does not change activeQueueIndex`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 2)
        mgr.insertNext(item("X"))
        assertEquals(2, mgr.activeQueueIndex)  // active item doesn't move
    }

    // ═════════════════════════════════════════════════════════════════════════
    // C. appendToQueue
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `C01 appendToQueue adds item at the end`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        mgr.appendToQueue(item("Z"))
        assertEquals(6, mgr.queue.size)
        assertEquals("Z", mgr.queue[5]["title"])
    }

    @Test fun `C02 appendToQueue does not change activeQueueIndex`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 3)
        mgr.appendToQueue(item("Z"))
        assertEquals(3, mgr.activeQueueIndex)
    }

    @Test fun `C03 appendToQueue calls saveQueue`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        val before = saveQueueCount
        mgr.appendToQueue(item("Z"))
        assertEquals(before + 1, saveQueueCount)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // D. removeFromQueue — index adjustment
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `D01 removeFromQueue removes the correct item`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        mgr.removeFromQueue(2)  // remove "C"
        assertEquals(4, mgr.queue.size)
        assertEquals("D", mgr.queue[2]["title"])
    }

    @Test fun `D02 removeFromQueue(index < active) decrements activeQueueIndex`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 3)  // active = D at 3
        mgr.removeFromQueue(1)  // remove "B" (before active)
        assertEquals(2, mgr.activeQueueIndex)  // was 3 → now 2
        assertEquals("D", mgr.queue[mgr.activeQueueIndex]["title"])
    }

    @Test fun `D03 removeFromQueue(index > active) does not change activeQueueIndex`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 2)  // active = C at 2
        mgr.removeFromQueue(4)  // remove "E" (after active)
        assertEquals(2, mgr.activeQueueIndex)
        assertEquals("C", mgr.queue[mgr.activeQueueIndex]["title"])
    }

    @Test fun `D04 removeFromQueue(index == active) and active is last item clamps index`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 4)  // active = E at 4 (last)
        mgr.removeFromQueue(4)  // remove active item
        // queue now has 4 items, active should clamp to 3 (new last)
        assertEquals(3, mgr.activeQueueIndex)
    }

    @Test fun `D05 removeFromQueue last remaining item leaves index at 0`() {
        val mgr = makeManager()
        mgr.setQueue(listOf(item("Only")), startIndex = 0)
        mgr.removeFromQueue(0)
        assertEquals(0, mgr.activeQueueIndex)
        assertTrue(mgr.queue.isEmpty())
    }

    @Test fun `D06 removeFromQueue out-of-range index is ignored`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 2)
        val before = saveQueueCount
        mgr.removeFromQueue(99)
        // out-of-range: nothing changes
        assertEquals(5, mgr.queue.size)
        assertEquals(before, saveQueueCount)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // E. reorderQueue — activeQueueIndex follows the moved item
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `E01 reorderQueue moves the item to the new position`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        mgr.reorderQueue(0, 3)  // A moves from 0 to 3
        assertEquals("B", mgr.queue[0]["title"])
        assertEquals("A", mgr.queue[3]["title"])
    }

    @Test fun `E02 reorderQueue activeIndex follows moved active item forward`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 1)  // active = B at 1
        mgr.reorderQueue(1, 4)  // move B from 1 → 4
        assertEquals(4, mgr.activeQueueIndex)
        assertEquals("B", mgr.queue[mgr.activeQueueIndex]["title"])
    }

    @Test fun `E03 reorderQueue activeIndex follows moved active item backward`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 3)  // active = D at 3
        mgr.reorderQueue(3, 1)  // move D from 3 → 1
        assertEquals(1, mgr.activeQueueIndex)
        assertEquals("D", mgr.queue[mgr.activeQueueIndex]["title"])
    }

    @Test fun `E04 reorderQueue moving item before active shifts active down by 1`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 3)  // active = D at 3
        mgr.reorderQueue(4, 1)  // move E (after active) to 1 (before active)
        // Active item D shifts from 3 → 4 because E was inserted before it
        assertEquals(4, mgr.activeQueueIndex)
        assertEquals("D", mgr.queue[mgr.activeQueueIndex]["title"])
    }

    @Test fun `E05 reorderQueue moving item after active shifts active up by 1`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 2)  // active = C at 2
        mgr.reorderQueue(0, 4)  // move A (before active) to 4 (after active)
        // Active item C shifts from 2 → 1
        assertEquals(1, mgr.activeQueueIndex)
        assertEquals("C", mgr.queue[mgr.activeQueueIndex]["title"])
    }

    @Test fun `E06 reorderQueue same old and new index is a no-op`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 2)
        val before = saveQueueCount
        mgr.reorderQueue(2, 2)
        assertEquals(before, saveQueueCount)  // no save when no-op
    }

    @Test fun `E07 reorderQueue out-of-range old index is ignored`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 2)
        val before = saveQueueCount
        mgr.reorderQueue(99, 1)
        assertEquals(before, saveQueueCount)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // F. Direct index setters
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `F01 setActiveQueueIndex directly sets index`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        mgr.setActiveQueueIndex(4)
        assertEquals(4, mgr.activeQueueIndex)
    }

    @Test fun `F02 decrementActiveQueueIndex decrements when above zero`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 3)
        mgr.decrementActiveQueueIndex()
        assertEquals(2, mgr.activeQueueIndex)
    }

    @Test fun `F03 decrementActiveQueueIndex does nothing when already at 0`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        mgr.decrementActiveQueueIndex()
        assertEquals(0, mgr.activeQueueIndex)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // G. Crossfade guard — list mutations still apply
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `G01 insertNext during crossfade still updates in-memory list`() {
        val mgr = makeManager(isCrossfadeInProgress = { true })
        mgr.setQueue(fiveItemQueue(), startIndex = 2)
        mgr.insertNext(item("X"))
        assertEquals(6, mgr.queue.size)
        assertEquals("X", mgr.queue[3]["title"])
    }

    @Test fun `G02 appendToQueue during crossfade still updates in-memory list`() {
        val mgr = makeManager(isCrossfadeInProgress = { true })
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        mgr.appendToQueue(item("Z"))
        assertEquals(6, mgr.queue.size)
        assertEquals("Z", mgr.queue.last()["title"])
    }

    @Test fun `G03 removeFromQueue during crossfade still updates in-memory list`() {
        val mgr = makeManager(isCrossfadeInProgress = { true })
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        mgr.removeFromQueue(2)
        assertEquals(4, mgr.queue.size)
    }

    @Test fun `G04 reorderQueue during crossfade still reorders in-memory list`() {
        val mgr = makeManager(isCrossfadeInProgress = { true })
        mgr.setQueue(fiveItemQueue(), startIndex = 0)
        mgr.reorderQueue(0, 3)
        assertEquals("A", mgr.queue[3]["title"])
    }

    // ═════════════════════════════════════════════════════════════════════════
    // H. rebuildPlayerQueue — safe with null player
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `H01 rebuildPlayerQueue with null player does not throw`() {
        val mgr = makeManager()
        mgr.setQueue(fiveItemQueue(), startIndex = 2)
        mgr.rebuildPlayerQueue()  // player is null → should return silently
        // No assertion needed: just confirming no exception is thrown
    }

    @Test fun `H02 rebuildPlayerQueue with empty queue does not throw`() {
        val mgr = makeManager()
        mgr.rebuildPlayerQueue()  // empty queue → return early
    }
}
