package dev.wndavenz.music.automix

import dev.wndavenz.music.replaygain.PcmDecoder
import kotlin.math.roundToInt

/**
 * Thin glue between MainActivity's Automix channel and the DSP analysis.
 * Decodes at most [MAX_ANALYZE_SECONDS] seconds of a track into mono PCM
 * (reusing the MediaExtractor/MediaCodec loop in [PcmDecoder]) and runs
 * [AudioFeatureExtractor] over it. MainActivity owns thread selection and
 * error mapping — this object only computes plain Kotlin result maps,
 * mirroring the ReplayGainBridge contract.
 */
object AutomixAnalysis {

    private class FloatSampleBuffer(private val maxSamples: Int) {
        private var values = FloatArray(minOf(16 * 1024, maxSamples).coerceAtLeast(1))
        var size: Int = 0
            private set

        fun append(value: Float) {
            check(size < maxSamples) { "AutoMix PCM sample cap exceeded" }
            if (size == values.size) {
                values = values.copyOf(minOf(maxSamples, values.size * 2))
            }
            values[size++] = value
        }

        fun toFloatArray(): FloatArray =
            if (size == values.size) values else values.copyOf(size)
    }

    /** Full-track tempo/key analysis budget (seconds of PCM). */
    const val MAX_ANALYZE_SECONDS = 300
    private const val TARGET_RATE_HZ = 22050

    /** Handles the `analyze` channel method; takes the raw file path. */
    fun analyze(filePath: String): Map<String, Any?> {
        val result = analyzePcm(filePath)
            ?: return mapOf("success" to false, "error" to "analysis_failed")
        return result
    }

    private fun analyzePcm(path: String): Map<String, Any?>? {
        var sampleRate = 0
        var channels = 0
        var analysisRate = 0
        var decimationFactor = 1
        var samples: FloatSampleBuffer? = null
        var decimationSum = 0f
        var decimationCount = 0

        val decoded = PcmDecoder.decode(
            path = path,
            onFormat = { fmt ->
                sampleRate = fmt.sampleRate
                channels = fmt.channels
                if (sampleRate > 0) {
                    // Match AudioFeatureExtractor's integer decimation, but do
                    // it while decoding so we never retain boxed Floats or a
                    // full-rate PCM copy for a multi-minute song.
                    decimationFactor = maxOf(
                        1,
                        (sampleRate / TARGET_RATE_HZ.toDouble()).roundToInt(),
                    )
                    analysisRate = sampleRate / decimationFactor
                    samples = FloatSampleBuffer(analysisRate * MAX_ANALYZE_SECONDS)
                }
            },
            feed = { buf, frameCount ->
                val ch = channels
                val output = samples ?: return@decode false
                if (ch <= 0 || analysisRate <= 0) return@decode false
                val cap = analysisRate * MAX_ANALYZE_SECONDS

                for (f in 0 until frameCount) {
                    if (output.size >= cap) return@decode false
                    val mono = if (ch == 1) {
                        buf[f] / 32768f
                    } else {
                        val left = buf[f * ch] / 32768f
                        val right = buf[f * ch + 1] / 32768f
                        (left + right) * 0.5f
                    }

                    decimationSum += mono
                    decimationCount++
                    if (decimationCount == decimationFactor) {
                        output.append(decimationSum / decimationFactor)
                        decimationSum = 0f
                        decimationCount = 0
                    }
                    if (output.size >= cap) return@decode false
                }
                true
            },
            onProgress = { /* single-pass decode; progress not consumed */ },
        )

        // PcmDecoder.decode() returns false both for decode failures and our
        // intentional feed-abort at the cap. Treat only a full capped buffer
        // as success; all other decoder failures remain failures.
        val collected = samples ?: return null
        if (sampleRate <= 0 || analysisRate <= 0) return null
        val reachedCap = collected.size.toLong() >=
            analysisRate.toLong() * MAX_ANALYZE_SECONDS
        if (!decoded && !reachedCap) return null
        if (collected.size < analysisRate) return null // under 1 s of audio

        val analysis = AudioFeatureExtractor.analyze(
            collected.toFloatArray(),
            analysisRate,
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
