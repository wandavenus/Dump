package dev.wndavenz.music.automix

/** Maps Dart's AutoMix strategy codes to the fade policy consumed by Media3. */
internal object AutomixTransitionPolicy {
    const val CROSSFADE = 0
    const val STRUCTURE_ALIGNED = 1
    const val SHORT_HANDOVER = 2
    const val LONG_BLEND = 3
    const val QUICK_HANDOVER = 4

    const val MIN_FADE_MS = 80L
    const val EARLY_TRANSITION_MIN_LEAD_MS = 30_000L
    const val EARLY_TRANSITION_MAX_LEAD_MS = 65_000L

    /**
     * An incoming drop may only be used when the matching outgoing-track cue
     * will actually be accepted by CrossfadeController for this media duration.
     * The same predicate is used for scheduling the fade and seeking the standby.
     */
    fun isValidEarlyHandover(
        transitionStartMs: Long?,
        outgoingDurationMs: Long,
        fadeDurationMs: Long,
    ): Boolean {
        val startMs = transitionStartMs ?: return false
        if (outgoingDurationMs <= 0L || startMs < 0L || startMs >= outgoingDurationMs ||
            fadeDurationMs < 0L || fadeDurationMs >= EARLY_TRANSITION_MAX_LEAD_MS
        ) {
            return false
        }
        val leadMs = outgoingDurationMs - startMs
        return leadMs in EARLY_TRANSITION_MIN_LEAD_MS..EARLY_TRANSITION_MAX_LEAD_MS &&
            leadMs > fadeDurationMs + MIN_FADE_MS
    }

    /** A beat grid is considered eligible only when both planner-approved BPMs exist. */
    fun isBeatMatchedPair(outgoingBpm: Float?, incomingBpm: Float?): Boolean =
        outgoingBpm != null && incomingBpm != null &&
            outgoingBpm.isFinite() && incomingBpm.isFinite() &&
            outgoingBpm in 50f..220f && incomingBpm in 50f..220f

    fun hasTransitionCue(fadeSeconds: Float?): Boolean =
        fadeSeconds != null && fadeSeconds.isFinite() && fadeSeconds in 1.5f..12f

    /** Invalid speed metadata must never create a zero/negative/infinite time scale. */
    fun normalizedPlaybackSpeed(speed: Float): Float =
        speed.takeIf { it.isFinite() && it > 0f }?.coerceIn(0.1f, 8f) ?: 1f

    /**
     * Accumulates source-media time from a monotonic wall-clock delta and the
     * processor's applied speed. Sampling the applied value every tick supports
     * speed changes during a fade and avoids relying on ExoPlayer's unrelated
     * PlaybackParameters.speed when Signalsmith performs the time-stretch.
     */
    fun advanceMediaTimeline(
        elapsedMediaMs: Double,
        elapsedWallMs: Long,
        playbackSpeed: Float,
    ): Double {
        val elapsed = elapsedMediaMs.takeIf { it.isFinite() && it >= 0.0 } ?: 0.0
        val delta = elapsedWallMs.coerceAtLeast(0L).toDouble() *
            normalizedPlaybackSpeed(playbackSpeed).toDouble()
        val next = elapsed + delta
        return next.takeIf { it.isFinite() } ?: Double.MAX_VALUE
    }

    fun mediaTimelineProgress(elapsedMediaMs: Double, fadeDurationMs: Long): Float {
        if (fadeDurationMs <= 0L) return 1f
        val elapsed = elapsedMediaMs.takeIf { it.isFinite() && it >= 0.0 } ?: 0.0
        return (elapsed / fadeDurationMs.toDouble()).coerceIn(0.0, 1.0).toFloat()
    }

    /** Monotonic-clock gate for periodic phase-lock measurements. */
    fun shouldSamplePhaseLock(nowMs: Long, lastSampleMs: Long, intervalMs: Long): Boolean =
        intervalMs > 0L && nowMs >= lastSampleMs && nowMs - lastSampleMs >= intervalMs

    fun fadeSeconds(strategyCode: Int, requestedSeconds: Float?): Float? {
        val requested = requestedSeconds?.takeIf { it.isFinite() } ?: return null
        val adjusted = when (strategyCode) {
            SHORT_HANDOVER -> minOf(requested, 4f)
            LONG_BLEND -> maxOf(requested, 6f)
            QUICK_HANDOVER -> minOf(requested, 3f)
            else -> requested // Standard and structure-aligned use the cue duration.
        }
        return adjusted.coerceIn(1.5f, 12f)
    }

    fun curveGamma(strategyCode: Int, requestedGamma: Float?): Float? {
        val requested = requestedGamma?.takeIf { it.isFinite() } ?: return null
        val adjusted = when (strategyCode) {
            SHORT_HANDOVER -> maxOf(requested, 1.20f)
            LONG_BLEND -> minOf(requested, 0.95f)
            QUICK_HANDOVER -> maxOf(requested, 1.35f)
            else -> requested
        }
        return adjusted.coerceIn(0.6f, 1.6f)
    }
}


/**
 * Validated MethodChannel target fields consumed by Media3. Kept as a pure
 * parser so the exact Dart-to-Kotlin cue contract can be regression-tested.
 */
internal data class ParsedAutomixTransitionTarget(
    val id: Int,
    val multiplier: Float,
    val bpm: Float?,
    val beatOffsetMs: Long?,
    val downbeatOffsetMs: Long?,
    val dropCueMs: Long?,
    val fadeSeconds: Float?,
    val transitionStartMs: Long?,
    val curveGamma: Float?,
    val incomingTrim: Float?,
    val outgoingTrim: Float?,
) {
    companion object {
        fun fromMap(target: Map<String, Any?>): ParsedAutomixTransitionTarget? {
            val id = (target["id"] as? Number)?.toInt() ?: return null
            val multiplier = (target["multiplier"] as? Number)?.toFloat()
                ?.takeIf { it.isFinite() }?.coerceIn(0.92f, 1.08f) ?: 1f
            val bpm = (target["bpm"] as? Number)?.toFloat()
                ?.takeIf { it.isFinite() && it in 50f..220f }

            fun nonNegativeMillis(key: String): Long? =
                (target[key] as? Number)?.toDouble()
                    ?.takeIf { it.isFinite() && it >= 0.0 }
                    ?.toLong()

            val strategy = ((target["transitionStrategy"] as? Number)?.toInt() ?: 0)
                .coerceIn(
                    AutomixTransitionPolicy.CROSSFADE,
                    AutomixTransitionPolicy.QUICK_HANDOVER,
                )
            val requestedFade = (target["fadeSeconds"] as? Number)?.toFloat()
            val requestedCurve = (target["fadeCurve"] as? Number)?.toFloat()
            val transitionStartMs = (target["transitionStartMs"] as? Number)?.toDouble()
                ?.takeIf {
                    it.isFinite() && it >= 0.0 && it <= 86_400_000.0
                }?.toLong()

            return ParsedAutomixTransitionTarget(
                id = id,
                multiplier = multiplier,
                bpm = bpm,
                beatOffsetMs = nonNegativeMillis("beatOffsetMs"),
                downbeatOffsetMs = nonNegativeMillis("downbeatOffsetMs"),
                dropCueMs = nonNegativeMillis("dropCueMs"),
                fadeSeconds = AutomixTransitionPolicy.fadeSeconds(strategy, requestedFade),
                transitionStartMs = transitionStartMs,
                curveGamma = AutomixTransitionPolicy.curveGamma(strategy, requestedCurve),
                incomingTrim = (target["levelTrimIncoming"] as? Number)?.toFloat()
                    ?.takeIf { it.isFinite() }?.coerceIn(0f, 1f),
                outgoingTrim = (target["levelTrimOutgoing"] as? Number)?.toFloat()
                    ?.takeIf { it.isFinite() }?.coerceIn(0f, 1f),
            )
        }
    }
}
