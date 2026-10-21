package dev.wndavenz.music.audio.mixer

/**
 * Hardware output owned by [SingleAudioTrackEngine].
 *
 * Exactly one implementation exists per service session, and it is the only
 * owner of the physical `AudioTrack`. Deck sinks never touch it directly:
 * everything except [currentPositionUs] / [hasPendingData] is funnelled
 * through the engine's single output thread so the underlying sink is never
 * called concurrently.
 *
 * The interface is intentionally free of Media3 types so the engine can be
 * unit-tested against a capture implementation on the JVM.
 */
interface SharedAudioOutput {

    /** Callbacks raised by the hardware sink (already serialized on its thread). */
    interface Listener {
        fun onUnderrun(
            bufferSizeBytes: Int,
            bufferSizeMs: Long,
            elapsedSinceLastFeedMs: Long,
        )

        fun onPositionDiscontinuity()

        fun onAudioSessionIdChanged(audioSessionId: Int)

        fun onAudioTrackInitialized(
            encoding: Int,
            sampleRate: Int,
            channelConfig: Int,
            bufferSize: Int,
        )

        fun onAudioTrackReleased(
            encoding: Int,
            sampleRate: Int,
            channelConfig: Int,
        )

        /** Recoverable sink error; reported for logging only. */
        fun onSinkError(message: String)

        /** Fatal bus failure; the engine can no longer produce audio. */
        fun onError(message: String)
    }

    var listener: Listener?

    /** Configures the bus at [sampleRate] with [channelCount] float channels. */
    fun configure(sampleRate: Int, channelCount: Int): Boolean

    fun isConfigured(): Boolean

    fun play()

    fun pause()

    /**
     * Writes [frameCount] interleaved stereo float frames. Must not return
     * until the sink accepted the whole block (the engine thread is dedicated
     * to this call and can block on the AudioTrack buffer).
     */
    fun handleBuffer(
        pcm: FloatArray,
        frameCount: Int,
        presentationTimeUs: Long,
    ): Boolean

    /** Playhead position in µs, or a negative value when not set yet. */
    fun currentPositionUs(): Long

    fun hasPendingData(): Boolean

    /** Reported hardware buffer duration in µs (0 when unknown). */
    fun bufferSizeUs(): Long

    fun audioSessionId(): Int

    fun flush()

    fun release()
}
