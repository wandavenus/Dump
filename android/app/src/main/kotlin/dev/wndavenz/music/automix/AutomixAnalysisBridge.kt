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

    /**
     * Default tempo/key analysis budget (seconds of PCM). Callers may request a
     * different window: AutoMix samples the head/middle/tail of long files
     * instead of truncating them, which is why the window is a parameter.
     */
    const val MAX_ANALYZE_SECONDS = 300
    private const val TARGET_RATE_HZ = 22050
    private const val MIN_WINDOW_SECONDS = 1.0
    private const val MAX_WINDOW_SECONDS = 900.0

    /**
     * Handles the `analyze` channel method. [startSeconds] selects the window's
     * start inside the file (0 = beginning) and [maxSeconds] its length.
     */
    fun analyze(
        filePath: String,
        startSeconds: Double = 0.0,
        maxSeconds: Double = MAX_ANALYZE_SECONDS.toDouble(),
    ): Map<String, Any?> {
        val result = analyzePcm(filePath, startSeconds, maxSeconds)
            ?: return mapOf("success" to false, "error" to "analysis_failed")
        return result
    }

    private fun analyzePcm(
        path: String,
        startSeconds: Double,
        maxSeconds: Double,
    ): Map<String, Any?>? {
        val windowSeconds =
            maxSeconds.coerceIn(MIN_WINDOW_SECONDS, MAX_WINDOW_SECONDS).toInt()
        val startUs =
            (startSeconds.coerceAtLeast(0.0) * 1_000_000.0).toLong()
        var fileSeconds = 0.0
        var sampleRate = 0
        var channels = 0
        var analysisRate = 0
        var decimationFactor = 1
        var samples: FloatSampleBuffer? = null
        var decimationSum = 0f
        var decimationCount = 0

        val decoded = PcmDecoder.decode(
            path = path,
            startUs = startUs,
            onFormat = { fmt ->
                sampleRate = fmt.sampleRate
                channels = fmt.channels
                if (fmt.durationUs > 0) fileSeconds = fmt.durationUs / 1_000_000.0
                if (sampleRate > 0) {
                    // Match AudioFeatureExtractor's integer decimation, but do
                    // it while decoding so we never retain boxed Floats or a
                    // full-rate PCM copy for a multi-minute song.
                    decimationFactor = maxOf(
                        1,
                        (sampleRate / TARGET_RATE_HZ.toDouble()).roundToInt(),
                    )
                    analysisRate = sampleRate / decimationFactor
                    samples = FloatSampleBuffer(analysisRate * windowSeconds)
                }
            },
            feed = { buf, frameCount ->
                val ch = channels
                val output = samples ?: return@decode false
                if (ch <= 0 || analysisRate <= 0) return@decode false
                val cap = analysisRate * windowSeconds

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
        val reachedCap = collected.size.toLong() >= analysisRate.toLong() * windowSeconds
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
            "beatOffsetMs" to analysis.beatOffsetMs,
            "camelotNumber" to mapping?.first,
            "camelotMinor" to mapping?.second,
            "keyConfidence" to analysis.keyConfidence,
            "rmsDb" to analysis.rmsDb,
            "centroidHz" to analysis.centroidHz,
            "onsetRate" to analysis.onsetRate,
            "analyzedSeconds" to analysis.analyzedSeconds,
            // Window bookkeeping: the Dart side merges head/middle/tail windows
            // and needs to know each window's position and the file length.
            "segmentStartSeconds" to startSeconds.coerceAtLeast(0.0),
            "segmentSeconds" to analysis.analyzedSeconds,
            "fileSeconds" to fileSeconds,
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
