package dev.wndavenz.music.audio.mixer

/**
 * One immutable generation of a deck's decoded output.
 *
 * `flush()`, `seek()` and track changes replace the whole object rather than
 * clearing it in place, so the mixer can detect a stale generation and drop
 * any block that belonged to the previous timeline. The ring and timeline are
 * therefore never mutated by two owners at once.
 */
class DeckStream(
    val generation: Long,
    ringFrames: Int,
) {
    val ring = PcmRingBuffer(ringFrames)
    val timeline = DeckTimelineMap()

    /** Deck-local frames appended by the producer for this generation. */
    @Volatile
    var producedFrames: Long = 0L

    /** True after `playToEndOfStream()` drained the processor tail. */
    @Volatile
    var eos: Boolean = false
}

/** Observable mixer counters (logging / acceptance gates). */
data class MixerMetrics(
    val activeAudioTracks: Int,
    val audioTracksCreated: Long,
    val audioTracksReleased: Long,
    val busFramesWritten: Long,
    val busFramesPlayed: Long,
    val busUnderrunFrames: Long,
    val sessionId: Int,
)
