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
