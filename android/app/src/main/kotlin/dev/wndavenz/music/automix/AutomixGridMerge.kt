package dev.wndavenz.music.automix

import dev.wndavenz.music.effects.AutomixLiveBeatState
import kotlin.math.abs
import kotlin.math.ln

/**
 * Weighted merge of one deck's offline analyzer grid and live tracker estimate.
 *
 * The two sources describe the same musical grid but measure it through
 * different clocks: the analyzer works in decoded-file time while the live
 * tracker measures elapsed time at the audio sink. Long-term tempo is
 * clock-independent, so BPMs that agree within [BPM_AGREEMENT_LOG_TOLERANCE]
 * are blended proportionally to their weights. A larger disagreement keeps the
 * offline source whole: it has ~48 s of analysis plus bar/chord context, while
 * the live history is at most a few seconds, and averaging sources that
 * disagree (for example a half/double reading) would produce a tempo that
 * matches neither. Beat and downbeat phases are never averaged across clocks:
 * when the sources agree the live phase wins only if it also agrees with the
 * analysed phase; otherwise the offline grid wins whole.
 */
internal object AutomixGridMerge {

    /** Reliability of a validated analyzer grid, comparable to a live confidence. */
    const val OFFLINE_GRID_WEIGHT = 0.8

    /** Natural-log BPM difference above which the two sources disagree. */
    const val BPM_AGREEMENT_LOG_TOLERANCE = 0.04

    /**
     * Circular phase difference, as a fraction of one beat, above which the
     * two sources are treated as disagreeing.
     */
    const val PHASE_AGREEMENT_FRACTION = 0.25

    /**
     * One deck's merged grid, ready to feed [AutomixPhaseLock.factorFor] or
     * [AutomixPhaseLock.phraseFactorFor]. Live contributions use the elapsed
     * phase as the position with a zero offset; offline contributions use the
     * player position with the analyzed offset.
     */
    data class DeckGrid(
        val bpm: Double,
        val beatPositionMs: Double,
        val beatOffsetMs: Double,
        val downbeatPositionMs: Double?,
        val downbeatOffsetMs: Double,
        val live: Boolean,
    )

    fun mergeDeck(
        live: AutomixLiveBeatState?,
        liveBeatMinConfidence: Float,
        liveDownbeatMinConfidence: Float,
        offlineBpm: Float?,
        offlinePositionMs: Double?,
        offlineBeatOffsetMs: Double?,
        offlineDownbeatOffsetMs: Double?,
    ): DeckGrid? {
        val liveValid = live != null &&
            live.confidence >= liveBeatMinConfidence &&
            live.bpm.isFinite() && live.bpm > 0f &&
            live.phaseElapsedMs.isFinite() && live.phaseElapsedMs >= 0.0
        val offlineValid = offlineBpm != null && offlineBpm.isFinite() &&
            offlineBpm > 0f &&
            offlinePositionMs != null && offlinePositionMs.isFinite() &&
            offlineBeatOffsetMs != null && offlineBeatOffsetMs.isFinite() &&
            offlineBeatOffsetMs >= 0.0
        if (!liveValid && !offlineValid) return null

        val liveDownbeatValid = liveValid && live != null &&
            live.downbeatConfidence >= liveDownbeatMinConfidence &&
            live.downbeatElapsedMs.isFinite() && live.downbeatElapsedMs >= 0.0
        val offlineDownbeatValid = offlineValid &&
            offlineDownbeatOffsetMs != null && offlineDownbeatOffsetMs.isFinite() &&
            offlineDownbeatOffsetMs >= 0.0

        val liveBpm = live?.bpm?.toDouble()
        val offlineBpmValue = offlineBpm?.toDouble()
        val liveWeight = if (liveValid) live!!.confidence.toDouble() else 0.0
        // A phase reading is only meaningful together with the tempo that
        // defines its period, so a phase source is never mixed across
        // disagreeing tempos: blended tempos keep nearly equal periods and may
        // take the live phase on agreement, while a mismatch moves both tempo
        // and phase to the same source.
        val tempoAgrees = liveValid && offlineValid &&
            abs(ln(liveBpm!! / offlineBpmValue!!)) <= BPM_AGREEMENT_LOG_TOLERANCE

        val bpm: Double
        val useLiveBeat: Boolean
        when {
            !liveValid -> {
                bpm = offlineBpmValue!!
                useLiveBeat = false
            }
            !offlineValid -> {
                bpm = liveBpm!!
                useLiveBeat = true
            }
            tempoAgrees -> {
                val liveTempo = liveBpm!!
                val offlineTempo = offlineBpmValue!!
                bpm = (liveTempo * liveWeight + offlineTempo * OFFLINE_GRID_WEIGHT) /
                    (liveWeight + OFFLINE_GRID_WEIGHT)
                val liveFraction = live!!.phaseElapsedMs / (60_000.0 / liveTempo)
                val offlineFraction = positiveModulo(
                    offlinePositionMs!! - offlineBeatOffsetMs!!,
                    60_000.0 / offlineTempo,
                ) / (60_000.0 / offlineTempo)
                // Phase only follows the live deck when it actually agrees
                // with the analysed phase. A confident but contradictory live
                // estimate must not overwrite 48 s of analysed history.
                useLiveBeat =
                    circularFractionalDistance(liveFraction, offlineFraction) <=
                        PHASE_AGREEMENT_FRACTION
            }
            else -> {
                // The sources disagree by more than the 4% log tolerance. The
                // offline estimate has ~48 s of analysis and is the only source
                // with bar/chord context; the live history is <= 6 s. Prefer
                // offline and let the live tracker resume only when the
                // analyzer has no usable grid at all.
                useLiveBeat = false
                bpm = offlineBpmValue!!
            }
        }

        // A downbeat phase shares the clock of its own beat grid, so it follows
        // the chosen beat source: live downbeats only when the live beat source
        // won (or the analyzer has none), otherwise the analyzer downbeat.
        val downbeatFromLive = liveDownbeatValid && (useLiveBeat || !offlineValid)
        val downbeatFromOffline = !downbeatFromLive && offlineDownbeatValid

        return DeckGrid(
            bpm = bpm,
            beatPositionMs = if (useLiveBeat) live!!.phaseElapsedMs else offlinePositionMs!!,
            beatOffsetMs = if (useLiveBeat) 0.0 else offlineBeatOffsetMs!!,
            downbeatPositionMs = when {
                downbeatFromLive -> live!!.downbeatElapsedMs
                downbeatFromOffline -> offlinePositionMs
                else -> null
            },
            downbeatOffsetMs = when {
                downbeatFromLive -> 0.0
                downbeatFromOffline -> offlineDownbeatOffsetMs!!
                else -> 0.0
            },
            live = useLiveBeat,
        )
    }

    internal fun circularFractionalDistance(a: Double, b: Double): Double {
        val difference = abs(a - b) % 1.0
        return minOf(difference, 1.0 - difference)
    }

    private fun positiveModulo(value: Double, modulus: Double): Double {
        val wrapped = value % modulus
        return if (wrapped < 0.0) wrapped + modulus else wrapped
    }
}
