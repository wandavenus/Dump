package dev.wndavenz.music.automix

import kotlin.math.abs

/**
 * Beat-phase resync for an AutoMix overlap.
 *
 * The offline planner lines the blend up with the outgoing deck's beat grid once,
 * when the fade is scheduled. The two ExoPlayers then decode independently, so
 * clock drift, seek rounding and buffer jitter slowly slide them out of phase
 * while they overlap. A blend that stays locked re-times the incoming deck
 * *during* the fade instead of freezing it at the phase it had at fade start —
 * that is what makes a long, beat-matched crossfade sound like one record.
 *
 * The correction is a **rate** correction, never a seek: [nudgeFor] returns the
 * relative change to add to the incoming deck's tempo multiplier so the two beat
 * grids meet again before the fade ends. It is capped at [MAX_NUDGE] (0.6 %), far
 * below the tempo change an ear can notice, and every caller re-derives it from
 * live positions, so a bad measurement self-corrects on the next pass.
 */
object AutomixPhaseLock {

    /** Largest relative tempo change a single correction may apply. */
    const val MAX_NUDGE = 0.006f

    /** Phase errors below this are left alone — measurement noise, not drift. */
    const val DEAD_ZONE_MS = 6.0

    /** Never correct with less than this much fade left to work with. */
    const val MIN_REMAINING_MS = 300.0

    /**
     * Signed phase error between the two decks, in milliseconds of the incoming
     * timeline.
     *
     * Positive means the incoming deck is **ahead** inside its beat (it has to be
     * slowed down to lock). Returns null when either grid is unusable, so callers
     * can simply skip the correction.
     */
    fun phaseErrorMs(
        outgoingPositionMs: Double,
        outgoingPhaseOffsetMs: Double,
        outgoingBeatMs: Double,
        incomingPositionMs: Double,
        incomingPhaseOffsetMs: Double,
        incomingBeatMs: Double,
    ): Double? {
        if (!outgoingPositionMs.isFinite() || !incomingPositionMs.isFinite()) return null
        if (!outgoingBeatMs.isFinite() || !incomingBeatMs.isFinite()) return null
        if (outgoingBeatMs < MIN_BEAT_MS || incomingBeatMs < MIN_BEAT_MS) return null

        // Compare the grids as fractions of their own beat so a half/double-time
        // pairing still compares like for like, then report the error in the
        // incoming deck's own milliseconds.
        val outgoingPhase = fold(outgoingPositionMs - outgoingPhaseOffsetMs, outgoingBeatMs)
        val incomingPhase = fold(incomingPositionMs - incomingPhaseOffsetMs, incomingBeatMs)
        var error = incomingPhase / incomingBeatMs - outgoingPhase / outgoingBeatMs
        if (error > 0.5) error -= 1.0
        if (error < -0.5) error += 1.0
        if (!error.isFinite()) return null
        return error * incomingBeatMs
    }

    /**
     * Relative tempo change for the incoming deck.
     *
     * Closing [errorMs] over the remaining [remainingMs] of the fade needs a rate
     * of `1 - error / remaining`; anything larger than [maxNudge] is clamped so a
     * bad measurement can never produce an audible pitch wobble.
     */
    fun nudgeFor(
        errorMs: Double,
        remainingMs: Double,
        maxNudge: Float = MAX_NUDGE,
    ): Float {
        if (!errorMs.isFinite() || !remainingMs.isFinite()) return 0f
        if (abs(errorMs) < DEAD_ZONE_MS) return 0f
        if (remainingMs < MIN_REMAINING_MS) return 0f
        val limit = abs(maxNudge).toDouble()
        if (limit <= 0.0) return 0f
        val rate = (-errorMs / remainingMs).coerceIn(-limit, limit)
        return if (rate.isFinite()) rate.toFloat() else 0f
    }

    /** Tempos outside 50..250 BPM are never used for a grid (mirrors Dart). */
    private const val MIN_BEAT_MS = 240.0 // 250 BPM

    private fun fold(valueMs: Double, beatMs: Double): Double {
        val remainder = valueMs % beatMs
        return if (remainder < 0) remainder + beatMs else remainder
    }
}
