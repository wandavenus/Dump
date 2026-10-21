package dev.wndavenz.music.audio.mixer

/**
 * Single-producer / single-consumer bounded ring of interleaved **stereo
 * float** PCM frames.
 *
 * One ExoPlayer renderer thread is the only writer; [SingleAudioTrackEngine]'s
 * output thread is the only reader. No lock is taken on the hot path:
 *
 *  - the producer owns [writeFrame] and publishes it through
 *    [writeFramePublished] after the samples have been copied;
 *  - the consumer owns [readFrame] and publishes it through
 *    [readFramePublished] after the samples have been copied out.
 *
 * Volatile publication is what makes the float copies visible across threads:
 * everything written before the volatile store happens-before the consumer's
 * volatile read.
 *
 * The ring never silently drops audio: [write] and [read] accept at most the
 * number of frames that fit, and report the accepted count so the caller can
 * apply backpressure through `AudioSink.handleBuffer`.
 */
class PcmRingBuffer(val capacityFrames: Int) {

    init {
        require(capacityFrames > 0) { "capacityFrames must be > 0" }
    }

    private val data = FloatArray(capacityFrames * CHANNELS)

    /** Absolute frame counters; they intentionally grow without wrapping. */
    private var writeFrame = 0L
    private var readFrame = 0L

    @Volatile
    private var writeFramePublished = 0L

    @Volatile
    private var readFramePublished = 0L

    /** Frames the consumer may read right now. */
    val availableToRead: Int
        get() {
            val available = writeFramePublished - readFramePublished
            return available.coerceIn(0L, capacityFrames.toLong()).toInt()
        }

    /** Frames the producer may write right now. */
    val availableToWrite: Int
        get() {
            val used = writeFrame - readFramePublished
            return (capacityFrames - used).coerceIn(0L, capacityFrames.toLong()).toInt()
        }

    /**
     * Copies up to [frames] stereo frames from [src] (starting at
     * [offsetFrames]) into the ring and returns the number of frames accepted.
     */
    fun write(src: FloatArray, offsetFrames: Int, frames: Int): Int {
        require(offsetFrames >= 0 && frames >= 0) { "negative offset/frames" }
        require(offsetFrames + frames <= src.size / CHANNELS) { "source overflow" }

        val accepted = minOf(frames, availableToWrite)
        if (accepted <= 0) return 0

        val writeIndex = (writeFrame % capacityFrames).toInt()
        val firstFrames = minOf(accepted, capacityFrames - writeIndex)
        copySamples(src, offsetFrames, data, writeIndex, firstFrames)
        if (accepted > firstFrames) {
            copySamples(src, offsetFrames + firstFrames, data, 0, accepted - firstFrames)
        }

        writeFrame += accepted
        writeFramePublished = writeFrame
        return accepted
    }

    /**
     * Copies up to [frames] stereo frames into [dst] (starting at
     * [offsetFrames]) and returns the number of frames read.
     */
    fun read(dst: FloatArray, offsetFrames: Int, frames: Int): Int {
        require(offsetFrames >= 0 && frames >= 0) { "negative offset/frames" }
        require(offsetFrames + frames <= dst.size / CHANNELS) { "destination overflow" }

        val available = writeFramePublished - readFrame
        val accepted = minOf(frames.toLong(), available, capacityFrames.toLong()).toInt()
        if (accepted <= 0) return 0

        val readIndex = (readFrame % capacityFrames).toInt()
        val firstFrames = minOf(accepted, capacityFrames - readIndex)
        copySamples(data, readIndex, dst, offsetFrames, firstFrames)
        if (accepted > firstFrames) {
            copySamples(data, 0, dst, offsetFrames + firstFrames, accepted - firstFrames)
        }

        readFrame += accepted
        readFramePublished = readFrame
        return accepted
    }

    /** Total frames written since construction (absolute counter). */
    val totalFramesWritten: Long
        get() = writeFramePublished

    private fun copySamples(
        src: FloatArray,
        srcFrame: Int,
        dst: FloatArray,
        dstFrame: Int,
        frames: Int,
    ) {
        System.arraycopy(
            src,
            srcFrame * CHANNELS,
            dst,
            dstFrame * CHANNELS,
            frames * CHANNELS,
        )
    }

    companion object {
        const val CHANNELS = 2
    }
}
