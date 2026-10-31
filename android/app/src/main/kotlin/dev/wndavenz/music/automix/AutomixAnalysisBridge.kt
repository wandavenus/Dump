package dev.wndavenz.music.automix

import dev.wndavenz.music.replaygain.PcmDecoder
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToInt
import kotlin.math.roundToLong

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
        return analyzeSamples(
            collected.toFloatArray(),
            analysisRate,
            downsampler?.centerChannelRatio ?: Double.NaN,
            safeStartSeconds,
            fileSeconds,
            reachedEof,
        )
    }

    /**
     * Decodes a file once, capturing the windows AutoMix needs while the audio
     * streams past. The head and any middle windows are analysed as soon as
     * their sample buffers fill; a bounded ring buffer holds the actual tail
     * even when the container duration is stale. This replaces one decoder
     * open/seek per window with one sequential decode session.
     */
    fun analyzeAll(
        filePath: String,
        segmentSeconds: Double = 120.0,
        veryLongFileSeconds: Double = 300.0,
    ): Map<String, Any?> {
        val segment = segmentSeconds.takeIf {
            it.isFinite() && it in 1.0..MAX_ANALYZE_SECONDS.toDouble()
        } ?: 120.0
        val veryLong = veryLongFileSeconds.takeIf {
            it.isFinite() && it >= segment
        } ?: 300.0

        var sampleRate = 0
        var channels = 0
        var analysisRate = 0
        var downsampler: AutomixPcmDownsampler? = null
        var formatSeconds = 0.0
        var ring = FloatArray(0)
        var windowSeconds = segment
        var captures: List<WindowCapture> = emptyList()
        var totalSamples = 0L
        var reachedEof = false
        val results = mutableListOf<MutableMap<String, Any?>>()

        fun finishCapture(capture: WindowCapture) {
            val buffer = capture.buffer ?: return
            capture.release()
            if (buffer.size < analysisRate) return
            val map = analyzeSamples(
                buffer,
                analysisRate,
                downsampler?.centerChannelRatio ?: Double.NaN,
                capture.startSeconds,
                0.0,
                false,
            ) ?: return
            results.add(map)
        }

        val decoded = PcmDecoder.decode(
            path = filePath,
            onFormat = { fmt ->
                sampleRate = fmt.sampleRate
                channels = fmt.channels
                if (fmt.durationUs > 0) formatSeconds = fmt.durationUs / 1_000_000.0
                downsampler = AutomixPcmDownsampler(
                    sourceRateHz = sampleRate,
                    channels = channels,
                    targetRateHz = TARGET_RATE_HZ,
                    channelMask = fmt.channelMask,
                )
                analysisRate = downsampler!!.outputRateHz
                windowSeconds = planWindowSeconds(formatSeconds, segment, veryLong)
                val ringSeconds = if (formatSeconds.isFinite() && formatSeconds > 0.0) {
                    minOf(windowSeconds, formatSeconds).coerceAtLeast(1.0)
                } else {
                    windowSeconds
                }
                ring = FloatArray(
                    (analysisRate * ringSeconds).roundToInt().coerceAtLeast(1),
                )
                captures = planWindowStarts(formatSeconds, windowSeconds, veryLong).map {
                    WindowCapture(it, windowSeconds, analysisRate)
                }
            },
            feed = { buf, frameCount ->
                val rate = analysisRate
                val resampler = downsampler
                if (rate <= 0 || resampler == null) return@decode false
                for (frame in 0 until frameCount) {
                    val mono = resampler.processFrame(buf, frame) ?: continue
                    val position = totalSamples
                    if (ring.isNotEmpty()) {
                        ring[(position % ring.size.toLong()).toInt()] = mono
                    }
                    for (capture in captures) {
                        if (capture.append(position, mono)) finishCapture(capture)
                    }
                    totalSamples++
                }
                true
            },
            onProgress = { /* single sequential pass; progress not consumed */ },
            onEos = { reachedEof = true },
        )

        if (sampleRate <= 0 || analysisRate <= 0 || totalSamples <= 0L) {
            return mapOf("success" to false, "error" to "analysis_failed")
        }
        val actualSeconds = totalSamples.toDouble() / analysisRate
        if (actualSeconds < 1.0) {
            return mapOf("success" to false, "error" to "analysis_failed")
        }

        // The tail comes from the ring, not from a predicted start offset: a
        // stale container duration must not hide the real end of the file.
        val ringCount = minOf(totalSamples, ring.size.toLong()).toInt()
        if (ringCount >= analysisRate) {
            val tailPcm = FloatArray(ringCount)
            val startIndex = if (totalSamples >= ring.size.toLong()) {
                (totalSamples % ring.size.toLong()).toInt()
            } else {
                0
            }
            for (index in 0 until ringCount) {
                tailPcm[index] = ring[(startIndex + index) % ring.size]
            }
            // A file shorter than one window has no head/tail split; the ring
            // is the whole track and the partial captures are discarded.
            if (totalSamples <= (captures.firstOrNull()?.sampleCount ?: 0).toLong()) {
                results.clear()
            }
            val tailStartSeconds =
                (totalSamples - ringCount).toDouble() / analysisRate
            val tail = analyzeSamples(
                tailPcm,
                analysisRate,
                downsampler?.centerChannelRatio ?: Double.NaN,
                tailStartSeconds,
                actualSeconds,
                reachedEof,
            )
            if (tail != null) results.add(tail)
        }
        for (capture in captures) capture.release()
        if (results.isEmpty()) {
            return mapOf("success" to false, "error" to "analysis_failed")
        }

        // The decoder only reports the real length after the pass, so patch
        // the bookkeeping fields that were built while it was still unknown.
        for (map in results) {
            map["fileSeconds"] = actualSeconds
            val start = (map["segmentStartSeconds"] as? Number)?.toDouble() ?: 0.0
            val seconds = (map["segmentSeconds"] as? Number)?.toDouble() ?: 0.0
            map["reachedEof"] = reachedEof && start + seconds >= actualSeconds - 0.05
        }
        results.sortBy { (it["segmentStartSeconds"] as? Number)?.toDouble() ?: 0.0 }
        val windows = mutableListOf<MutableMap<String, Any?>>()
        for (map in results) {
            val start = (map["segmentStartSeconds"] as? Number)?.toDouble() ?: 0.0
            val previous = windows.lastOrNull()
            val previousStart = (previous?.get("segmentStartSeconds") as? Number)
                ?.toDouble() ?: -1.0
            if (previous != null && abs(start - previousStart) < 0.5) {
                if (map["reachedEof"] == true) {
                    windows[windows.lastIndex] = map
                }
            } else {
                windows.add(map)
            }
        }
        return mapOf(
            "success" to true,
            "windows" to windows,
            "fileSeconds" to actualSeconds,
            "reachedEof" to reachedEof,
            "decoded" to decoded,
        )
    }

    private fun planWindowSeconds(
        durationSeconds: Double,
        segmentSeconds: Double,
        veryLongFileSeconds: Double,
    ): Double {
        if (!durationSeconds.isFinite() || durationSeconds <= 0.0) return segmentSeconds
        if (durationSeconds > segmentSeconds &&
            durationSeconds < segmentSeconds * 2.0
        ) {
            return floor(durationSeconds / 2.0).coerceAtLeast(1.0)
        }
        return segmentSeconds
    }

    private fun planWindowStarts(
        durationSeconds: Double,
        windowSeconds: Double,
        veryLongFileSeconds: Double,
    ): List<Double> {
        val starts = mutableListOf(0.0)
        if (!durationSeconds.isFinite() || durationSeconds <= windowSeconds) {
            return starts
        }
        val tailStart = durationSeconds - windowSeconds
        if (durationSeconds <= veryLongFileSeconds) {
            // 241-300 s: one centred window closes the head/tail gap, even
            // though it overlaps both edges (the old coverage fix).
            if (tailStart - windowSeconds > 30.0) {
                starts.add((durationSeconds / 2.0 - windowSeconds / 2.0)
                    .coerceIn(0.0, durationSeconds - windowSeconds))
            }
        } else {
            fun addCentered(centerSeconds: Double) {
                val start = (centerSeconds - windowSeconds / 2.0)
                    .coerceIn(0.0, durationSeconds - windowSeconds)
                // Keep the head/tail edges exclusive for very long files; the
                // existing analyser already avoids duplicated windows here.
                if (start < windowSeconds) return
                if (durationSeconds - (start + windowSeconds) < windowSeconds) return
                if (starts.any { abs(it - start) < windowSeconds }) return
                starts.add(start)
            }
            if (durationSeconds > veryLongFileSeconds * 2.0) {
                addCentered(durationSeconds / 4.0)
                addCentered(durationSeconds / 2.0)
                addCentered(durationSeconds * 3.0 / 4.0)
            } else {
                addCentered(durationSeconds / 2.0)
            }
        }
        return starts
    }

    private class WindowCapture(
        val startSeconds: Double,
        seconds: Double,
        rate: Int,
    ) {
        val startSample: Long = (startSeconds * rate).roundToLong()
        val sampleCount: Int = (seconds * rate).roundToInt().coerceAtLeast(1)
        // Grow like FloatSampleBuffer: a short file must not allocate a full
        // 120 s window just because its container duration was unknown or stale.
        private var target = FloatArray(minOf(16 * 1024, sampleCount).coerceAtLeast(1))
        var buffer: FloatArray? = target
        private var fill = 0
        private var completed = false

        fun release() {
            completed = true
            buffer = null
            target = FloatArray(0)
        }

        /** Returns true exactly once, when this window's last sample arrives. */
        fun append(position: Long, sample: Float): Boolean {
            if (completed) return false
            val offset = position - startSample
            if (offset < 0L) return false
            if (offset >= sampleCount.toLong()) {
                completed = true
                return false
            }
            if (fill >= target.size) {
                target = target.copyOf(minOf(sampleCount, target.size * 2))
                buffer = target
            }
            target[fill++] = sample
            if (fill == sampleCount) {
                completed = true
                buffer = target.copyOf(fill)
                target = FloatArray(0)
                return true
            }
            return false
        }
    }

    private fun analyzeSamples(
        monoPcm: FloatArray,
        analysisRate: Int,
        centerRatio: Double,
        startSeconds: Double,
        fileSeconds: Double,
        reachedEof: Boolean,
    ): MutableMap<String, Any?>? {
        if (monoPcm.size < analysisRate) return null
        if (!AutomixNative.ensureLoaded()) return null
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
                    "startMs" to (startSeconds * 1000.0 + startMs),
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

        return mutableMapOf(
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
            // Seam-edge stats appended to the ABI. Optional reads keep an older
            // native library from invalidating otherwise usable analysis.
            "introEdgeRmsDb" to optional(35),
            "outroEdgeRmsDb" to optional(36),
            "introEdgeLufs" to optional(37),
            "outroEdgeLufs" to optional(38),
            "introEdgeOnsetRate" to optional(39),
            "outroEdgeOnsetRate" to optional(40),
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
            "segmentStartSeconds" to startSeconds,
            "segmentSeconds" to analysis[10],
            "fileSeconds" to fileSeconds,
            // True only when the decoder reached End-Of-Stream inside this
            // window. A capped tail window can be full yet still stop before
            // the real file end when container duration metadata is stale.
            "reachedEof" to reachedEof,
            "decodedSeconds" to monoPcm.size.toDouble() / analysisRate,
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
