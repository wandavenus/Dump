package dev.wndavenz.music.audio.mixer

/**
 * Maps absolute output-bus frames to a deck's source-media timeline.
 *
 * The mixer consumes PCM before AudioTrack has played it. These segments keep
 * that in-flight position metadata until the hardware playhead passes them.
 */
class DeckPlayedTimelineMap(capacitySegments: Int = DEFAULT_CAPACITY_SEGMENTS) {
    private val busStarts = LongArray(capacitySegments)
    private val frameCounts = LongArray(capacitySegments)
    private val sourceStartsUs = LongArray(capacitySegments)
    private val sourceDurationsUs = LongArray(capacitySegments)

    private var head = 0
    private var count = 0
    private var anchorPositionUs: Long? = null
    private var lastEndPositionUs: Long? = null

    init {
        require(capacitySegments > 0) { "capacitySegments must be > 0" }
    }

    @Synchronized
    fun append(busStartFrame: Long, frames: Int, sourceStartUs: Long, sourceDurationUs: Long) {
        if (frames <= 0) return
        if (count == busStarts.size) {
            val oldest = head
            anchorPositionUs = sourceStartsUs[oldest] + sourceDurationsUs[oldest]
            head = (head + 1) % busStarts.size
            count--
        }
        val index = (head + count) % busStarts.size
        busStarts[index] = busStartFrame
        frameCounts[index] = frames.toLong()
        sourceStartsUs[index] = sourceStartUs
        sourceDurationsUs[index] = sourceDurationUs.coerceAtLeast(0L)
        count++
        lastEndPositionUs = sourceStartUs + sourceDurationUs.coerceAtLeast(0L)
    }

    /** Source media position for an audible bus frame, or null before this deck starts. */
    @Synchronized
    fun positionAt(busFrame: Long): Long? {
        var previousPosition = anchorPositionUs
        for (i in 0 until count) {
            val index = (head + i) % busStarts.size
            val start = busStarts[index]
            val end = start + frameCounts[index]
            if (busFrame < start) return previousPosition
            if (busFrame < end) {
                return sourceStartsUs[index] +
                    ((busFrame - start) * sourceDurationsUs[index]) / frameCounts[index]
            }
            previousPosition = sourceStartsUs[index] + sourceDurationsUs[index]
        }
        return previousPosition ?: lastEndPositionUs
    }

    @Synchronized
    fun hasPendingData(busFrame: Long): Boolean {
        for (i in 0 until count) {
            val index = (head + i) % busStarts.size
            if (busStarts[index] + frameCounts[index] > busFrame) return true
        }
        return false
    }

    @Synchronized
    fun trimBefore(busFrame: Long) {
        while (count > 0) {
            val index = head
            if (busStarts[index] + frameCounts[index] > busFrame) break
            anchorPositionUs = sourceStartsUs[index] + sourceDurationsUs[index]
            head = (head + 1) % busStarts.size
            count--
        }
    }

    @Synchronized
    fun clear() {
        head = 0
        count = 0
        anchorPositionUs = null
        lastEndPositionUs = null
    }

    @Synchronized
    fun segmentCount(): Int = count

    companion object {
        private const val DEFAULT_CAPACITY_SEGMENTS = 4096
    }
}
