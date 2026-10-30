package dev.wndavenz.music.automix

import dev.wndavenz.music.replaygain.PcmDecoder
import kotlin.math.roundToInt

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
        // NaN never compares true, so coerceIn/coerceAtLeast would pass it
        // through: the decode window would silently start at 0 while the chord
        // timestamps became NaN. Sanitize both bounds once, up front.
        val safeMaxSeconds =
            if (maxSeconds.isFinite()) maxSeconds else MAX_ANALYZE_SECONDS.toDouble()
        val windowSeconds =
            safeMaxSeconds.coerceIn(MIN_WINDOW_SECONDS, MAX_WINDOW_SECONDS).roundToInt()
        val safeStartSeconds = if (startSeconds.isFinite() && startSeconds > 0.0) {
            startSeconds
        } else {
            0.0
        }
        val startUs = (safeStartSeconds * 1_000_000.0).toLong()
        var fileSeconds = 0.0
        var sampleRate = 0
        var channels = 0
        var analysisRate = 0
        var downsampler: AutomixPcmDownsampler? = null
        var samples: FloatSampleBuffer? = null
        var reachedEof = false
        // Exact-size windows hit the cap on their final sample, so aborting at
        // the cap would hide the EOF that follows it. Allow a short overrun
        // (discarded, not stored) to observe end-of-stream, then abort.
        var overrunSamples = 0

        val decoded = PcmDecoder.decode(
            path = path,
            startUs = startUs,
            trimBeforeUs = startUs,
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
                        channelMask = fmt.channelMask,
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
                    val mono = resampler.processFrame(buf, f) ?: continue
                    if (output.size < cap) {
                        output.append(mono)
                    } else {
                        overrunSamples++
                        if (overrunSamples > analysisRate) return@decode false
                    }
                }
                true
            },
            onProgress = { /* single-pass decode; progress not consumed */ },
            onEos = { reachedEof = true },
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
        // Reuse one bounded PCM copy for both native passes. Long tracks can
        // produce several million samples, so avoid a second ~26 MB allocation.
        val monoPcm = collected.toFloatArray()
        val centerRatio = downsampler?.centerChannelRatio ?: Double.NaN
        val analysis = try {
            AutomixNative.nativeAnalyzeCentered(
                monoPcm,
                analysisRate,
                centerRatio,
            )
        } catch (_: LinkageError) {
            // Fail open if this process loaded an older native library.
            AutomixNative.nativeAnalyze(monoPcm, analysisRate)
        } ?: return null
        // Preserve the original analyzer ABI contract before doing extra work,
        // including when an older or mismatched native library is loaded.
        if (analysis.size < 28) return null

        // The chord pass runs on the same bounded background analysis worker;
        // it is deliberately separate from the realtime playback callback.
        val chordValues = try {
            AutomixNative.nativeAnalyzeChords(monoPcm, analysisRate)
        } catch (_: LinkageError) {
            null // Fail open if this process loaded an older native library.
        }
        val pitchNames = arrayOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
        // Quality id order must match nar_automix_analyze_chords and the
        // _automixChordQualities set in lib/services/automix_service/models.dart.
        val chordQualities = arrayOf(
            "maj", "min", "dim", "aug", "7", "maj7", "min7", "sus4",
            "sus2", "m7b5", "dim7", "aug7",
        )
        val chordProgression = if (chordValues != null && chordValues.size % 4 == 0) {
            (0 until chordValues.size step 4).mapNotNull { index ->
                val startMs = chordValues[index]
                val rootValue = chordValues[index + 1]
                val qualityValue = chordValues[index + 2]
                val confidence = chordValues[index + 3]
                val root = rootValue.toInt()
                val quality = qualityValue.toInt()
                if (!startMs.isFinite() || startMs < 0.0 ||
                    !rootValue.isFinite() || rootValue != root.toDouble() || root !in 0..11 ||
                    !qualityValue.isFinite() || qualityValue != quality.toDouble() ||
                    quality !in chordQualities.indices || !confidence.isFinite() ||
                    confidence !in 0.0..1.0 || confidence < 0.08
                ) null else mapOf(
                    "startMs" to (safeStartSeconds * 1000.0 + startMs),
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
        fun optional(index: Int): Double? =
            analysis.getOrNull(index)?.takeIf { it.isFinite() }
        val bpm = optional(0)
        val bpmConfidence = analysis[1]
        val tailBpmConfidence = analysis.getOrNull(20)?.takeIf { it.isFinite() } ?: 0.0
        // Tempo-curve slots: NaN when the quarter-window estimate did not
        // reach publishing confidence, or for stability when it is unmeasurable.
        val startBpm = optional(21)
        val endBpm = optional(22)
        val tempoStability = analysis.getOrNull(23)
            ?.takeIf { it.isFinite() && it in 0.0..1.0 }
        // Quarter RMS profile: a coarse within-window energy trend. Values are
        // dBFS medians and stay finite for successful analysis, but an older
        // native library could return zeros/NaN; only forward finite entries.
        val energyQuarters = (24..27)
            .map { analysis.getOrNull(it)?.takeIf { value -> value.isFinite() } }
            .takeIf { values -> values.all { it != null } }
            ?.map { it!! }
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
            // Bar length that owns the published downbeat phase (2 covers
            // compound 6/8 at a dotted-quarter pulse). Optional so a native
            // library predating the metre hypothesis still works; the consumer
            // treats absence as the legacy 4/4 assumption.
            "meter" to analysis.getOrNull(32)?.let { value ->
                val rounded = value.toInt()
                rounded.takeIf {
                    value.isFinite() && value == rounded.toDouble() &&
                        AutomixTransitionPolicy.isSupportedMeter(rounded)
                }
            },
            // Strongest track-level section boundary in this window (2 s chroma
            // change blocks). Window-relative like the drop/breakdown cues.
            "sectionCueMs" to optional(33),
            "sectionCueConfidence" to (analysis.getOrNull(34)
                ?.takeIf { it.isFinite() && it in 0.0..1.0 } ?: 0.0),
            "dropCueMs" to optional(12),
            "breakdownCueMs" to optional(13),
            "dropConfidence" to analysis[14],
            "breakdownConfidence" to analysis[15],
            "structureRegion" to analysis[16].toInt(),
            "structureConfidence" to analysis[17],
            "vocalLikelihood" to analysis[18],
            "vocalConfidence" to analysis[19],
            "tailBpmConfidence" to tailBpmConfidence,
            "startBpm" to startBpm,
            "endBpm" to endBpm,
            "tempoStability" to tempoStability,
            // These fields were appended to the native ABI so local tempos are
            // never paired with a phase measured at a different BPM. Optional
            // reads preserve compatibility with older native libraries.
            "startBpmConfidence" to optional(28),
            "endBpmConfidence" to optional(29),
            "startBeatOffsetMs" to optional(30),
            "endBeatOffsetMs" to optional(31),
            "energyQuarters" to energyQuarters,
            "chordProgression" to chordProgression,
            // Window bookkeeping: the Dart side merges head/middle/tail windows
            // and needs to know each window's position and the file length.
            // Use the sanitized value so the reported offset always matches the
            // position the decoder actually started from.
            "segmentStartSeconds" to safeStartSeconds,
            "segmentSeconds" to analysis[10],
            "fileSeconds" to fileSeconds,
            // True only when the decoder reached End-Of-Stream inside this
            // window. A capped tail window can be full yet still stop before
            // the real file end when container duration metadata is stale.
            "reachedEof" to reachedEof,
            "decodedSeconds" to collected.size.toDouble() / analysisRate,
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
