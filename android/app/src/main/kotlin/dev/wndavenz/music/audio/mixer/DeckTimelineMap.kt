package dev.wndavenz.music.audio.mixer

/**
 * Per-deck mapping between **deck-local output frames** and the source media
 * timeline.
 *
 * A deck's [PcmRingBuffer] carries samples that already went through the
 * per-deck processor chain (including Signalsmith Stretch). One source buffer
 * can therefore produce a different number of output frames than the source
 * duration it represents. The mixer never guesses that ratio: every accepted
 * chunk records the exact source start/duration that produced it, and position
 * queries interpolate inside that segment.
 *
 * Frames are deck-local (starting at 0 for each stream generation), not bus
 * frames. [SingleAudioTrackEngine] converts the bus playhead into a
 * deck-local played-frame count before asking for a position.
 *
 * Segments live in a small fixed ring so appending a block does not allocate.
 * All access is synchronized because [positionAt] is called from the ExoPlayer
 * playback thread while the producer appends from the same thread but the
 * engine trims from its output thread. The critical sections only touch the
 * metadata arrays — no PCM copying happens under the lock.
 */
class DeckTimelineMap(capacitySegments: Int = DEFAULT_CAPACITY_SEGMENTS) {

    private val startFrames = LongArray(capacitySegments)
    private val frameCounts = LongArray(capacitySegments)
    private val sourceStartsUs = LongArray(capacitySegments)
    private val sourceDurationsUs = LongArray(capacitySegments)

    private var head = 0
    private var count = 0

    /** Records [frames] deck-local output frames covering the given source span. */
    @Synchronized
    fun append(
        localFrameStart: Long,
        frames: Int,
        sourceStartUs: Long,
        sourceDurationUs: Long,
    ) {
        if (frames <= 0) return
        if (count == startFrames.size) {
            // Drop the oldest segment. One segment is a few milliseconds, and
            // trimming normally keeps the map far below this bound; dropping
            // here only affects interpolation for frames already played.
            head = (head + 1) % startFrames.size
            count--
        }
        val index = (head + count) % startFrames.size
        startFrames[index] = localFrameStart
        frameCounts[index] = frames.toLong()
        sourceStartsUs[index] = sourceStartUs
        sourceDurationsUs[index] = sourceDurationUs.coerceAtLeast(0L)
        count++
    }

    /**
     * Returns the source media position (µs) for a deck-local output frame, or
     * `null` when the map is empty.
     */
    @Synchronized
    fun positionAt(localFrame: Long): Long? {
        if (count == 0) return null

        // Most queries hit the newest segment during steady playback.
        for (i in count - 1 downTo 0) {
            val index = (head + i) % startFrames.size
            val start = startFrames[index]
            val frames = frameCounts[index]
            if (localFrame >= start && localFrame < start + frames) {
                if (frames <= 0L) return sourceStartsUs[index]
                val offset = localFrame - start
                return sourceStartsUs[index] +
                    (offset * sourceDurationsUs[index]) / frames
            }
        }

        val firstIndex = head
        if (localFrame < startFrames[firstIndex]) return sourceStartsUs[firstIndex]

        val lastIndex = (head + count - 1) % startFrames.size
        return sourceStartsUs[lastIndex] + sourceDurationsUs[lastIndex]
    }

    /** Source position at the end of the newest segment, if any. */
    @Synchronized
    fun endPositionUs(): Long? {
        if (count == 0) return null
        val lastIndex = (head + count - 1) % startFrames.size
        return sourceStartsUs[lastIndex] + sourceDurationsUs[lastIndex]
    }

    /**
     * Drops segments that end at or before [localFrame]. The segment that
     * still covers [localFrame] is retained so position interpolation keeps
     * working.
     */
    @Synchronized
    fun trimBefore(localFrame: Long) {
        while (count > 1) {
            val index = head
            val end = startFrames[index] + frameCounts[index]
            if (end > localFrame) break
            head = (head + 1) % startFrames.size
            count--
        }
    }

    @Synchronized
    fun clear() {
        head = 0
        count = 0
    }

    @Synchronized
    fun segmentCount(): Int = count

    companion object {
        private const val DEFAULT_CAPACITY_SEGMENTS = 1024
    }
}
