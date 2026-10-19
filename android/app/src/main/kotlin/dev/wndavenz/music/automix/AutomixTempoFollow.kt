package dev.wndavenz.music.automix

import kotlin.math.abs

/**
 * Live tempo refinement for the incoming deck during an AutoMix overlap.
 *
 * The planner publishes a static multiplier from the analyzed exit/head BPMs.
 * The live tracker measures the tempo of the PCM actually decoded on each deck,
 * which can drift from that offline estimate. This helper turns the difference
 * into a bounded *relative* correction on top of the planner's multiplier:
 *
 *   factor = (liveOut / liveIn) / (offlineOut / offlineIn)
 *
 * Both live estimates must be confident; otherwise the static planner match is
 * already the safest choice and no correction is returned. The correction is
 * capped at ±2 %, and the resulting absolute ratio is kept inside the
 * processor's ±8 % stretch range. Analysis can report half/double time, so both
 * ratios are octave-folded near 1.0 before dividing.
 */
internal object AutomixTempoFollow {
    const val MIN_CONFIDENCE = 0.50f
    const val MAX_CORRECTION = 0.02f
    const val RAMP_FRACTION = 0.25f

    private const val MIN_BPM = 50f
    private const val MAX_BPM = 250f
    private const val STRETCH_MIN = 0.92
    private const val STRETCH_MAX = 1.08
    // Matches the controller's apply epsilon: smaller corrections would be
    // re-posted every tick without changing the target.
    private const val MIN_APPLIED_DELTA = 0.001f

    /**
     * Returns the relative factor to apply on top of the planner's multiplier,
     * or null when the live pair cannot improve on the static match.
     */
    fun relativeFactor(
        outgoingLiveBpm: Float?,
        outgoingLiveConfidence: Float,
        incomingLiveBpm: Float?,
        incomingLiveConfidence: Float,
        outgoingOfflineBpm: Float?,
        incomingOfflineBpm: Float?,
        baseMultiplier: Float,
        maxCorrection: Float = MAX_CORRECTION,
    ): Float? {
        if (!confident(outgoingLiveBpm, outgoingLiveConfidence) ||
            !confident(incomingLiveBpm, incomingLiveConfidence) ||
            !inRange(outgoingOfflineBpm) || !inRange(incomingOfflineBpm)
        ) {
            return null
        }
        val base = baseMultiplier.takeIf { it.isFinite() && it > 0f } ?: return null
        val liveRatio = foldOctave(
            outgoingLiveBpm!!.toDouble() / incomingLiveBpm!!.toDouble(),
        ) ?: return null
        val offlineRatio = foldOctave(
            outgoingOfflineBpm!!.toDouble() / incomingOfflineBpm!!.toDouble(),
        ) ?: return null
        if (offlineRatio <= 0.0) return null

        val correction = maxCorrection
            .takeIf { it.isFinite() && it >= 0f }
            ?.coerceAtMost(0.04f)
            ?: MAX_CORRECTION
        // The relative correction is capped, and the resulting absolute
        // stretch (planner multiplier × factor) stays inside the processor's
        // supported range.
        val desired = base.toDouble() * (liveRatio / offlineRatio)
        val low = maxOf(
            base.toDouble() * (1.0 - correction.toDouble()),
            STRETCH_MIN,
        )
        val high = minOf(
            base.toDouble() * (1.0 + correction.toDouble()),
            STRETCH_MAX,
        )
        if (low > high) return null
        val factor = (desired.coerceIn(low, high) / base.toDouble()).toFloat()
        return factor.takeIf { it.isFinite() && abs(it - 1f) >= MIN_APPLIED_DELTA }
    }

    /**
     * Smoothstep ramp from 1.0 to [factor] across the first [RAMP_FRACTION] of
     * the fade, so the correction never starts with a step.
     */
    fun ramp(factor: Float?, progress: Float): Float {
        val target = factor?.takeIf { it.isFinite() && it > 0f } ?: return 1f
        val t = progress.takeIf { it.isFinite() }?.coerceIn(0f, 1f) ?: 0f
        val p = (t / RAMP_FRACTION).coerceIn(0f, 1f)
        val eased = p * p * (3f - 2f * p)
        return 1f + (target - 1f) * eased
    }

    private fun confident(bpm: Float?, confidence: Float): Boolean =
        inRange(bpm) && confidence.isFinite() && confidence >= MIN_CONFIDENCE

    private fun inRange(bpm: Float?): Boolean =
        bpm != null && bpm.isFinite() && bpm in MIN_BPM..MAX_BPM

    /** Keeps the octave candidate closest to 1.0 (same ratio, half/double pulse). */
    private fun foldOctave(ratio: Double): Double? {
        if (!ratio.isFinite() || ratio <= 0.0) return null
        return listOf(ratio, ratio * 2.0, ratio / 2.0)
            .filter { it.isFinite() && it > 0.0 }
            .minByOrNull { abs(it - 1.0) }
    }
}
