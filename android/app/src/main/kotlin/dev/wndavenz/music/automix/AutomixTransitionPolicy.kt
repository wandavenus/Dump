package dev.wndavenz.music.automix

/** Maps Dart's AutoMix strategy codes to the fade policy consumed by Media3. */
internal object AutomixTransitionPolicy {
    const val CROSSFADE = 0
    const val STRUCTURE_ALIGNED = 1
    const val SHORT_HANDOVER = 2
    const val LONG_BLEND = 3
    const val QUICK_HANDOVER = 4

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
