package dev.wndavenz.music.automix

import kotlin.math.ceil

/**
 * Beat-aligned low-band transfer for the AutoMix overlap.
 *
 * A long progress-based bass ramp smears the low end across several bars. A DJ
 * swap instead moves the bass once, on a musical boundary, over a short window
 * (at most one beat). This helper computes that window from the outgoing
 * deck's analyzed grid and evaluates a smooth (C1) transfer inside it.
 *
 * The window is deliberately derived from source-media positions, so it stays
 * aligned when the outgoing deck's tempo changes during the blend.
 */
internal object AutomixBassSwap {
    /** Soft floor for the swap start, as a fraction of the fade. */
    const val MIN_PROGRESS = 0.35f

    /** The transfer never lasts longer than this fraction of the fade. */
    const val MAX_WIDTH_FRACTION = 0.35f

    /** Fallback transfer length when no beat grid is available. */
    const val FALLBACK_WIDTH_FRACTION = 0.20f

    data class Window(val startMs: Double, val durationMs: Double) {
        val endMs: Double get() = startMs + durationMs
    }

    data class Gains(val outgoing: Float, val incoming: Float)

    /**
     * Places the swap on the first beat boundary at or after [MIN_PROGRESS] of
     * the fade, provided the transfer still fits before the fade ends.
     * Returns null for invalid input so the caller can keep a safe fallback.
     */
    fun window(
        fadeStartPositionMs: Double,
        fadeDurationMs: Double,
        beatMs: Double?,
        beatOffsetMs: Double?,
    ): Window? {
        if (!fadeStartPositionMs.isFinite() || fadeStartPositionMs < 0.0 ||
            !fadeDurationMs.isFinite() || fadeDurationMs <= 0.0
        ) {
            return null
        }

        val width = transferWidthMs(fadeDurationMs, beatMs)
        val minStart = fadeStartPositionMs + fadeDurationMs * MIN_PROGRESS
        val maxStart = (fadeStartPositionMs + fadeDurationMs - width)
            .coerceAtLeast(minStart)
        // Prefer a boundary at or after the soft floor, but never later than
        // the last position that still leaves room for the transfer.
        val snapped = boundaryAtOrAfter(minStart, beatMs, beatOffsetMs)
            ?.takeIf { it <= maxStart }
        val start = snapped ?: minStart
        return Window(start, width)
    }

    /** Smoothstep transfer: 0 = outgoing bass only, 1 = incoming bass only. */
    fun gains(progress: Float): Gains {
        val p = progress.takeIf { it.isFinite() }?.coerceIn(0f, 1f) ?: 0f
        val eased = p * p * (3f - 2f * p)
        return Gains(outgoing = 1f - eased, incoming = eased)
    }

    /**
     * Position-based progress inside [window], so a tempo change during the
     * blend cannot move the swap off its beat boundary.
     */
    fun progress(window: Window, mediaPositionMs: Double): Float {
        if (!mediaPositionMs.isFinite() || window.durationMs <= 0.0) return 0f
        return ((mediaPositionMs - window.startMs) / window.durationMs)
            .coerceIn(0.0, 1.0)
            .toFloat()
    }

    private fun transferWidthMs(fadeDurationMs: Double, beatMs: Double?): Double {
        val maxWidth = fadeDurationMs * MAX_WIDTH_FRACTION
        return if (beatMs != null && beatMs.isFinite() && beatMs > 0.0) {
            minOf(beatMs, maxWidth)
        } else {
            fadeDurationMs * FALLBACK_WIDTH_FRACTION
        }
    }

    private fun boundaryAtOrAfter(
        targetMs: Double,
        periodMs: Double?,
        offsetMs: Double?,
    ): Double? {
        if (periodMs == null || offsetMs == null ||
            !periodMs.isFinite() || periodMs <= 0.0 || !offsetMs.isFinite()
        ) {
            return null
        }
        val phase = ((offsetMs % periodMs) + periodMs) % periodMs
        val steps = ceil((targetMs - phase) / periodMs)
        val boundary = phase + steps * periodMs
        return boundary.takeIf { it.isFinite() && it >= 0.0 }
    }
}
