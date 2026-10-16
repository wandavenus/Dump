package dev.wndavenz.music.automix

import dev.wndavenz.music.replaygain.ReplayGainNative

/**
 * JNI facade for native beat-phase resync during an AutoMix overlap.
 * The C implementation calculates the relative tempo factor from live deck
 * positions. Invalid metadata or an unavailable native library disables only
 * the correction; it never blocks or interrupts playback.
 */
object AutomixPhaseLock {

    /** Largest relative tempo change a single correction may apply (0.6%). */
    const val MAX_NUDGE = 0.006f

    @Volatile
    private var nativeMethodUnavailable = false

    @Volatile
    private var phraseNativeMethodUnavailable = false

    private external fun nativePhaseLockFactor(
        outgoingPositionMs: Double,
        outgoingPhaseOffsetMs: Double,
        outgoingBpm: Double,
        incomingPositionMs: Double,
        incomingPhaseOffsetMs: Double,
        incomingBpm: Double,
        remainingMs: Double,
        maxNudge: Double,
    ): Float

    private external fun nativePhrasePhaseLockFactor(
        outgoingPositionMs: Double,
        outgoingDownbeatOffsetMs: Double,
        outgoingBpm: Double,
        incomingPositionMs: Double,
        incomingDownbeatOffsetMs: Double,
        incomingBpm: Double,
        remainingMs: Double,
        maxNudge: Double,
        beatsPerPhrase: Int,
    ): Float

    /**
     * Phrase-aware correction. Downbeat offsets are absolute timestamps relative
     * to each file's start; they must come from a confident native analysis.
     * Returns null if the phrase grid or this native entry point is unavailable,
     * allowing callers to fall back to ordinary beat-phase correction.
     */
    fun phraseFactorFor(
        outgoingPositionMs: Double,
        outgoingDownbeatOffsetMs: Double,
        outgoingBpm: Double,
        incomingPositionMs: Double,
        incomingDownbeatOffsetMs: Double,
        incomingBpm: Double,
        remainingMs: Double,
        maxNudge: Float = MAX_NUDGE,
        beatsPerPhrase: Int = 16,
    ): Float? {
        if (!outgoingPositionMs.isFinite() || !outgoingDownbeatOffsetMs.isFinite() ||
            outgoingDownbeatOffsetMs < 0.0 || !outgoingBpm.isFinite() ||
            outgoingBpm !in MIN_BPM..MAX_BPM ||
            !incomingPositionMs.isFinite() || !incomingDownbeatOffsetMs.isFinite() ||
            incomingDownbeatOffsetMs < 0.0 || !incomingBpm.isFinite() ||
            incomingBpm !in MIN_BPM..MAX_BPM ||
            !remainingMs.isFinite() || !maxNudge.isFinite() ||
            beatsPerPhrase !in 1..64
        ) {
            return null
        }
        if (phraseNativeMethodUnavailable || !ReplayGainNative.ensureLoaded()) return null

        return try {
            nativePhrasePhaseLockFactor(
                outgoingPositionMs,
                outgoingDownbeatOffsetMs,
                outgoingBpm,
                incomingPositionMs,
                incomingDownbeatOffsetMs,
                incomingBpm,
                remainingMs,
                maxNudge.toDouble(),
                beatsPerPhrase,
            ).takeIf { it.isFinite() && it > 0f }
        } catch (_: LinkageError) {
            // Old native libraries may not yet expose the phrase-aware symbol.
            phraseNativeMethodUnavailable = true
            null
        }
    }

    /**
     * Returns the incoming deck's absolute tempo multiplier (1 = unchanged),
     * or null when its beat grid cannot be used.
     */
    fun factorFor(
        outgoingPositionMs: Double,
        outgoingPhaseOffsetMs: Double,
        outgoingBpm: Double,
        incomingPositionMs: Double,
        incomingPhaseOffsetMs: Double,
        incomingBpm: Double,
        remainingMs: Double,
        maxNudge: Float = MAX_NUDGE,
    ): Float? {
        if (!outgoingPositionMs.isFinite() || !outgoingPhaseOffsetMs.isFinite() ||
            !outgoingBpm.isFinite() || outgoingBpm !in MIN_BPM..MAX_BPM ||
            !incomingPositionMs.isFinite() || !incomingPhaseOffsetMs.isFinite() ||
            !incomingBpm.isFinite() || incomingBpm !in MIN_BPM..MAX_BPM ||
            !remainingMs.isFinite() || !maxNudge.isFinite()
        ) {
            return null
        }
        if (nativeMethodUnavailable || !ReplayGainNative.ensureLoaded()) return null

        return try {
            nativePhaseLockFactor(
                outgoingPositionMs,
                outgoingPhaseOffsetMs,
                outgoingBpm,
                incomingPositionMs,
                incomingPhaseOffsetMs,
                incomingBpm,
                remainingMs,
                maxNudge.toDouble(),
            ).takeIf { it.isFinite() }
        } catch (_: UnsatisfiedLinkError) {
            // A stale/mismatched native library must not prevent normal fades.
            nativeMethodUnavailable = true
            null
        }
    }

    private const val MIN_BPM = 50.0
    private const val MAX_BPM = 250.0
}
