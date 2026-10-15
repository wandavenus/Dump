package dev.wndavenz.music.automix

import dev.wndavenz.music.replaygain.PcmDecoder

/**
 * Thin glue between MainActivity's Automix channel and the DSP analysis.
 * Decodes at most [MAX_ANALYZE_SECONDS] seconds of a track into mono PCM
 * (reusing the MediaExtractor/MediaCodec loop in [PcmDecoder]) and runs
 * [AudioFeatureExtractor] over it. MainActivity owns thread selection and
 * error mapping — this object only computes plain Kotlin result maps,
 * mirroring the ReplayGainBridge contract.
 */
object AutomixAnalysis {

    companion object {
        /** Full-track tempo/key analysis budget (seconds of PCM). */
        const val MAX_ANALYZE_SECONDS = 300
    }

    /** Handles the `analyze` channel method; takes the raw file path. */
    fun analyze(filePath: String): Map<String, Any?> {
        val result = analyzePcm(filePath)
            ?: return mapOf("success" to false, "error" to "analysis_failed")
        return result
    }

    private fun analyzePcm(path: String): Map<String, Any?>? {
        val samples = ArrayList<Float>(1024 * 1024)
        var sampleRate = 0
        var channels = 0

        val decoded = PcmDecoder.decode(
            path = path,
            onFormat = { fmt ->
                sampleRate = fmt.sampleRate
                channels = fmt.channels
            },
            feed = { buf, frameCount ->
                val ch = channels
                if (ch <= 0) return@decode false
                // Mono downmix while collecting; stop after the time cap.
                val capped = sampleRate * MAX_ANALYZE_SECONDS
                for (f in 0 until frameCount) {
                    if (samples.size >= capped) break
                    if (ch == 1) {
                        samples.add(buf[f] / 32768f)
                    } else {
                        val l = buf[f * ch] / 32768f
                        val r = buf[f * ch + 1] / 32768f
                        samples.add((l + r) * 0.5f)
                    }
                }
                if (samples.size >= capped) {
                    false // early abort — enough data collected
                } else {
                    true
                }
            },
            onProgress = { /* single-pass decode; progress not consumed */ },
        )
        // PcmDecoder.decode() returns false BOTH for real decode failures and
        // for our own feed-abort at the time cap. A full-cap sample set is a
        // SUCCESS (>= 5 minutes is plenty for tempo/key), so treat the abort as
        // a completed decode; only propagate genuine failures.
        if (sampleRate <= 0) return null
        val reachedCap = samples.size.toLong() >= sampleRate.toLong() * MAX_ANALYZE_SECONDS
        if (!decoded && !reachedCap) return null
        if (samples.size < sampleRate) return null // under 1 s of audio

        val analysis = AudioFeatureExtractor.analyze(
            samples.toFloatArray(),
            sampleRate,
        ) ?: return null

        val tonic = analysis.tonicPc
        val mapping = if (tonic in 0 until 12 && analysis.keyConfidence > 0.0) {
            keyToCamelot(tonic, analysis.isMinor)
        } else {
            null
        }

        return mapOf(
            "success" to true,
            "bpm" to analysis.bpm,
            "bpmConfidence" to analysis.bpmConfidence,
            "alternateBpm" to analysis.alternateBpm,
            "camelotNumber" to mapping?.first,
            "camelotMinor" to mapping?.second,
            "keyConfidence" to analysis.keyConfidence,
            "rmsDb" to analysis.rmsDb,
            "centroidHz" to analysis.centroidHz,
            "onsetRate" to analysis.onsetRate,
            "analyzedSeconds" to analysis.analyzedSeconds,
        )
    }

    // ── Camelot wheel mapping ────────────────────────────────────────────────
    //
    // Mirrors `automixCamelotMajorNum` / `automixCamelotMinorNum` in
    // `lib/services/automix_service/engine.dart` — keep both in sync.

    val CAMELOT_MAJOR = intArrayOf(8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1)
    val CAMELOT_MINOR = intArrayOf(5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10)

    fun keyToCamelot(tonicPc: Int, isMinor: Boolean): Pair<Int, Boolean> {
        val pc = ((tonicPc % 12) + 12) % 12
        return if (isMinor) Pair(CAMELOT_MINOR[pc], true)
        else Pair(CAMELOT_MAJOR[pc], false)
    }
}
