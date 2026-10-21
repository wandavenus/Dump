package dev.wndavenz.music.audio.mixer

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.min

/**
 * Post-sum safety limiter for the shared mix bus.
 *
 * This is the last stage after both decks are summed in float, so it protects
 * against constructive peaks that neither per-deck limiter can see. Attack is
 * instantaneous (the ceiling is never exceeded), release is exponential over
 * [releaseMs]; there is no lookahead, so it is a sample-peak protector rather
 * than a true-peak guarantee.
 *
 * Non-finite input is replaced with silence instead of poisoning the gain
 * state.
 */
class BusLimiter(
    private val ceiling: Float = DEFAULT_CEILING,
    releaseMs: Float = DEFAULT_RELEASE_MS,
    sampleRate: Int = SingleAudioTrackEngine.BUS_SAMPLE_RATE,
) {

    init {
        require(ceiling in 0.1f..1f) { "ceiling out of range" }
    }

    private val releaseCoefficient: Float =
        if (releaseMs <= 0f) 1f
        else (1.0 - exp(-1.0 / (releaseMs / 1000.0 * sampleRate))).toFloat()

    private val gain = FloatArray(PcmRingBuffer.CHANNELS) { 1f }

    fun reset() {
        gain.fill(1f)
    }

    /** Limits [frames] interleaved stereo frames in place. */
    fun process(buffer: FloatArray, frames: Int) {
        var frame = 0
        while (frame < frames) {
            val base = frame * PcmRingBuffer.CHANNELS
            for (channel in 0 until PcmRingBuffer.CHANNELS) {
                val sample = buffer[base + channel]
                if (!sample.isFinite()) {
                    buffer[base + channel] = 0f
                    continue
                }
                val peak = abs(sample)
                val current = gain[channel]
                val required = if (peak * current > ceiling) {
                    ceiling / peak
                } else {
                    1f
                }
                // Instant attack, exponential release back towards unity.
                val next = min(required, current + (1f - current) * releaseCoefficient)
                val limited = (sample * next).coerceIn(-ceiling, ceiling)
                gain[channel] = next
                buffer[base + channel] = limited
            }
            frame++
        }
    }

    companion object {
        /** Headroom below full scale so downstream int conversion cannot wrap. */
        const val DEFAULT_CEILING = 0.98f
        const val DEFAULT_RELEASE_MS = 50f
    }
}

/** Shared per-deck gain ramp maths. */
object MixGain {

    /**
     * One-pole coefficient that reaches ~63 % of a step in [timeMs]; the mix
     * loop applies it per frame so 16 ms crossfade volume ticks become a
     * continuous ramp instead of a staircase.
     */
    fun smoothingCoefficient(
        sampleRate: Int = SingleAudioTrackEngine.BUS_SAMPLE_RATE,
        timeMs: Float = DEFAULT_SMOOTHING_MS,
    ): Float {
        if (sampleRate <= 0 || timeMs <= 0f) return 1f
        return (1.0 - exp(-1.0 / (timeMs / 1000.0 * sampleRate))).toFloat()
    }

    const val DEFAULT_SMOOTHING_MS = 12f
}
