package com.example.musicplayer.queue

class QueueManager {
    var queue: List<Map<String, Any?>> = emptyList()
        private set
    var activeIndex: Int = 0
        private set

    fun set(items: List<Map<String, Any?>>, index: Int) {
        queue = items
        activeIndex = normalize(index)
    }

    fun updateActive(index: Int) { activeIndex = normalize(index) }
    fun snapshot(): List<Map<String, Any?>> = queue.map { HashMap(it) }
    fun normalize(index: Int): Int = index.coerceIn(0, (queue.size - 1).coerceAtLeast(0))

    fun insertNext(item: Map<String, Any?>): Int {
        val insertIdx = (activeIndex + 1).coerceIn(0, queue.size)
        queue = queue.toMutableList().also { it.add(insertIdx, item) }
        return insertIdx
    }

    fun append(item: Map<String, Any?>) { queue = queue.toMutableList().also { it.add(item) } }

    fun remove(index: Int): Boolean {
        if (index !in queue.indices) return false
        queue = queue.toMutableList().also { it.removeAt(index) }
        activeIndex = when {
            queue.isEmpty() -> 0
            index < activeIndex -> activeIndex - 1
            activeIndex >= queue.size -> queue.lastIndex
            else -> activeIndex
        }
        return true
    }

    fun move(oldIndex: Int, newIndex: Int): Boolean {
        if (oldIndex !in queue.indices || newIndex !in queue.indices || oldIndex == newIndex) return false
        queue = queue.toMutableList().also { list -> list.add(newIndex, list.removeAt(oldIndex)) }
        activeIndex = when {
            oldIndex == activeIndex -> newIndex
            oldIndex < activeIndex && newIndex >= activeIndex -> activeIndex - 1
            oldIndex > activeIndex && newIndex <= activeIndex -> activeIndex + 1
            else -> activeIndex
        }.coerceIn(0, (queue.size - 1).coerceAtLeast(0))
        return true
    }
}
