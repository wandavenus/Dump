package dev.wndavenz.music.automix

import dev.wndavenz.music.replaygain.PcmDecoder

/**
 * Thin glue between MainActivity's Automix channel and the DSP analysis.
 * Decodes at most [MAX_ANALYZE_SECONDS] seconds of a track into mono PCM
 * (reusing the MediaExtractor/MediaCodec loop in [PcmDecoder]) and runs the
 * native C analyzer through [AutomixNative]. MainActivity owns thread selection
 * and error mapping — this object only computes plain result maps.
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
        var downsampler: AutomixPcmDownsampler? = null
        var samples: FloatSampleBuffer? = null

        val decoded = PcmDecoder.decode(
            path = path,
            startUs = startUs,
            onFormat = { fmt ->
                sampleRate = fmt.sampleRate
                channels = fmt.channels
                if (fmt.durationUs > 0) fileSeconds = fmt.durationUs / 1_000_000.0
                if (sampleRate > 0 && channels > 0) {
                    // Filter at the source rate before decimation. This avoids
                    // folding ultrasonic/high-frequency content into the native
                    // STFT band and protects anti-phase stereo from cancelling
                    // into a false-silence analysis.
                    downsampler = AutomixPcmDownsampler(
                        sourceRateHz = sampleRate,
                        channels = channels,
                        targetRateHz = TARGET_RATE_HZ,
                    )
                    analysisRate = downsampler!!.outputRateHz
                    samples = FloatSampleBuffer(analysisRate * windowSeconds)
                }
            },
            feed = { buf, frameCount ->
                val output = samples ?: return@decode false
                val resampler = downsampler ?: return@decode false
                if (analysisRate <= 0) return@decode false
                val cap = analysisRate * windowSeconds

                for (f in 0 until frameCount) {
                    if (output.size >= cap) return@decode false
                    val mono = resampler.processFrame(buf, f) ?: continue
                    output.append(mono)
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

        if (!AutomixNative.ensureLoaded()) return null
        val analysis = AutomixNative.nativeAnalyze(
            collected.toFloatArray(),
            analysisRate,
        ) ?: return null

        // The chord pass runs on the same bounded background analysis worker;
        // it is deliberately separate from the realtime playback callback.
        val chordValues = try {
            AutomixNative.nativeAnalyzeChords(collected.toFloatArray(), analysisRate)
        } catch (_: LinkageError) {
            null // Fail open if this process loaded an older native library.
        }
        val pitchNames = arrayOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
        val chordQualities = arrayOf("maj", "min", "dim", "aug", "7", "maj7", "min7", "sus4")
        val chordProgression = if (chordValues != null && chordValues.size % 4 == 0) {
            (0 until chordValues.size step 4).mapNotNull { index ->
                val startMs = chordValues[index]
                val root = chordValues[index + 1].toInt()
                val quality = chordValues[index + 2].toInt()
                val confidence = chordValues[index + 3]
                if (!startMs.isFinite() || startMs < 0.0 || root !in 0..11 ||
                    quality !in chordQualities.indices || !confidence.isFinite() ||
                    confidence !in 0.0..1.0 || confidence < 0.08
                ) null else mapOf(
                    "startMs" to (startSeconds.coerceAtLeast(0.0) * 1000.0 + startMs),
                    "rootPitchClass" to root,
                    "root" to pitchNames[root],
                    "quality" to chordQualities[quality],
                    "label" to (pitchNames[root] + chordQualities[quality]),
                    "confidence" to confidence,
                )
            }
        } else {
            emptyList()
        }

        // Native result contract is kept in sync with
        // NAR_AUTOMIX_ANALYSIS_VALUE_COUNT in automix_native.h.
        if (analysis.size < 21) return null
        fun optional(index: Int): Double? =
            analysis.getOrNull(index)?.takeIf { it.isFinite() }
        val bpm = optional(0)
        val bpmConfidence = analysis[1]
        val tailBpmConfidence = analysis.getOrNull(20)?.takeIf { it.isFinite() } ?: 0.0
        val alternateBpm = optional(2)
        val beatOffsetMs = optional(3)
        val tonic = analysis[4].toInt()
        val isMinor = analysis[5] > 0.5
        val keyConfidence = analysis[6]
        val mapping = if (tonic in 0 until 12 && keyConfidence > 0.0) {
            keyToCamelot(tonic, isMinor)
        } else {
            null
        }

        return mapOf(
            "success" to true,
            "bpm" to bpm,
            "bpmConfidence" to bpmConfidence,
            "alternateBpm" to alternateBpm,
            "beatOffsetMs" to beatOffsetMs,
            "camelotNumber" to mapping?.first,
            "camelotMinor" to mapping?.second,
            "keyConfidence" to keyConfidence,
            "rmsDb" to optional(7),
            "centroidHz" to optional(8),
            "onsetRate" to analysis[9],
            "analyzedSeconds" to analysis[10],
            // Structural phase hints are window-relative; Dart adds the window
            // start when building the file-level intro/outro grid.
            "downbeatOffsetMs" to optional(11),
            "dropCueMs" to optional(12),
            "breakdownCueMs" to optional(13),
            "dropConfidence" to analysis[14],
            "breakdownConfidence" to analysis[15],
            "structureRegion" to analysis[16].toInt(),
            "structureConfidence" to analysis[17],
            "vocalLikelihood" to analysis[18],
            "vocalConfidence" to analysis[19],
            "tailBpmConfidence" to tailBpmConfidence,
            "chordProgression" to chordProgression,
            // Window bookkeeping: the Dart side merges head/middle/tail windows
            // and needs to know each window's position and the file length.
            "segmentStartSeconds" to startSeconds.coerceAtLeast(0.0),
            "segmentSeconds" to analysis[10],
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
