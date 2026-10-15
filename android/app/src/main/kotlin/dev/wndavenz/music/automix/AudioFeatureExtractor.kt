package dev.wndavenz.music.automix

import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Offline, algorithmic (no-ML) audio feature extraction for Automix.
 *
 * Pure Kotlin DSP on decoded mono PCM:
 *  - Radix-2 FFT → per-frame magnitude spectra (Hann window, 2048/512 @ ~22 kHz)
 *  - Half-wave-rectified spectral-flux onset envelope → autocorrelation +
 *    comb-filter tempo candidate search (60..200 BPM, soft 80–160 genre prior,
 *    half/double-time folding via the reported alternate tempo)
 *  - Chroma accumulation (fractional pitch-class interpolation) →
 *    Krumhansl–Schmuckler major/minor profile correlation
 *    over all 24 keys → tonic + mode + confidence (runner-up margin)
 *  - Energy raw stats: frame RMS dBFS median, spectral centroid median,
 *    onset density (peaks/second)
 *
 * The Dart side ([AutomixService]) gates confidence thresholds and maps the
 * (tonic, isMinor) pair through the Camelot wheel (see `automixKeyToCamelot`
 * in `lib/services/automix_service/engine.dart` — the tables there mirror the
 * constants below, change both together).
 */
object AudioFeatureExtractor {

    // ── Tuning constants ─────────────────────────────────────────────────────

    private const val FFT_SIZE = 2048
    private const val HOP = 512

    private data class TwiddleTable(
        val real: FloatArray,
        val imaginary: FloatArray,
    )

    // FFT_SIZE is fixed for every analysis frame. Cache stage twiddles once
    // per process instead of recomputing trig functions and allocating arrays
    // for every frame of every song.
    private val TWIDDLE_TABLES: Map<Int, TwiddleTable> = buildTwiddleTables()

    private fun buildTwiddleTables(): Map<Int, TwiddleTable> {
        val tables = HashMap<Int, TwiddleTable>()
        var len = 2
        while (len <= FFT_SIZE) {
            val half = len / 2
            val step = 2.0 * Math.PI / len
            val real = FloatArray(half)
            val imaginary = FloatArray(half)
            for (k in 0 until half) {
                val angle = step * k
                real[k] = kotlin.math.cos(angle).toFloat()
                imaginary[k] = (-kotlin.math.sin(angle)).toFloat()
            }
            tables[len] = TwiddleTable(real, imaginary)
            len = len shl 1
        }
        return tables
    }

    /// Tempo search range (BPM).
    private const val BPM_MIN = 60.0
    private const val BPM_MAX = 200.0

    /// Soft genre prior center/width (log2 octaves). Mild, so real slow or
    /// fast material is still discoverable.
    private const val BPM_PRIOR_CENTER = 115.0
    private const val BPM_PRIOR_LOG2_WIDTH = 0.55

    /// Comb-filter weights for the tempo score: reward candidates whose
    /// multiples also explain recurring onsets (mixed-in-tempo suppression).
    private const val COMB_W2 = 0.5
    private const val COMB_W3 = 0.25
    private const val COMB_W4 = 0.125

    /// Key decision margin below which the key is reported as still
    /// confident-enough-only-through [KeyResult.confidence] = 0.
    private const val KEY_MIN_MARGIN = 0.02

    /** Pitch range considered for chroma binning (bins outside are noise). */
    private const val CHROMA_MIN_FREQ = 55.0   // A1
    private const val CHROMA_MAX_FREQ = 5000.0 // plenty for tonal content

    // ── Result model ─────────────────────────────────────────────────────────

    data class Result(
        val bpm: Double?,
        /** 0..1, autocorrelation peak prominence. */
        val bpmConfidence: Double,
        /** Half or double-time alternative of [bpm] (or null). */
        val alternateBpm: Double?,
        /** Estimated phase of the dominant beat grid relative to file start. */
        val beatOffsetMs: Double?,
        /** Tonic pitch class 0..11 (0 = C), or -1 when key uncertain. */
        val tonicPc: Int,
        /** true = minor scale, false = major scale. */
        val isMinor: Boolean,
        /** 0..1, correlation margin between best and runner-up key. */
        val keyConfidence: Double,
        /** Active-frame median of per-frame RMS in dBFS. */
        val rmsDb: Double?,
        /** Median spectral centroid in Hz. */
        val centroidHz: Double?,
        /** Detected onsets per second. */
        val onsetRate: Double?,
        /** Seconds of audio actually analyzed (after any cap). */
        val analyzedSeconds: Double,
    )

    // ── Entry point ──────────────────────────────────────────────────────────

    /**
     * [mono] must be ≥1 s of audio at any sample rate (already any cap /
     * downmix handled by the caller). Returns null when the audio is too
     * short or degenerate for meaningful analysis.
     */
    fun analyze(mono: FloatArray, sampleRate: Int): Result? {
        if (sampleRate <= 0 || mono.size < sampleRate) return null

        // Integer decimation to ~22 kHz working rate (cheap anti-aliasing via
        // a box filter one decimation period wide).
        val factor = max(1, (sampleRate / 22050.0).roundToInt())
        val workingRate = sampleRate / factor
        val work = if (factor > 1) decimate(mono, factor) else mono
        val analyzedSeconds = work.size.toDouble() / workingRate

        // ── STFT frame pass ───────────────────────────────────────────────
        val frameCount = (work.size - FFT_SIZE) / HOP + 1
        if (frameCount < 8) return null

        val window = hann(FFT_SIZE)
        val bins = FFT_SIZE / 2
        val re = FloatArray(FFT_SIZE)
        val im = FloatArray(FFT_SIZE)
        var prevMag = FloatArray(bins)
        val mag = FloatArray(bins)

        val odf = FloatArray(frameCount)          // spectral flux envelope
        val rmsList = ArrayList<Float>(frameCount)  // kept for median
        val centroidList = ArrayList<Float>(frameCount)
        val chroma = FloatArray(12)

        for (f in 0 until frameCount) {
            val offset = f * HOP
            var frameSumSq = 0.0
            for (i in 0 until FFT_SIZE) {
                val sample = work[offset + i]
                re[i] = sample * window[i]
                im[i] = 0f
                frameSumSq += sample.toDouble() * sample.toDouble()
            }
            fftRadix2(re, im)

            var flux = 0f
            var wSum = 0.0
            var fSum = 0.0
            for (k in 0 until bins) {
                val m = sqrt(re[k] * re[k] + im[k] * im[k])
                mag[k] = m
                val logM = ln(m + 1f)
                val diff = logM - prevMag[k]
                if (diff > 0f) flux += diff
                prevMag[k] = logM

                val freq = k * workingRate.toDouble() / FFT_SIZE
                if (freq in CHROMA_MIN_FREQ..CHROMA_MAX_FREQ) {
                    wSum += m.toDouble()
                    fSum += m.toDouble() * freq
                }
            }
            odf[f] = flux
            // RMS is computed from the original PCM frame, not the unnormalised
            // FFT magnitudes, so the result is genuine dBFS and sample-rate agnostic.
            val rms = sqrt(frameSumSq / FFT_SIZE)
            if (rms > 1e-6) {
                rmsList.add((20.0 * ln(rms) / LN10.toDouble()).toFloat())
            }
            if (wSum > 1e-9) centroidList.add((fSum / wSum).toFloat())

            accumulateChroma(chroma, mag, workingRate)
        }

        // ── Tempo ─────────────────────────────────────────────────────────
        val tempo = estimateTempo(odf, workingRate)
        var alternateBpm: Double? = null
        if (tempo != null) {
            val double = tempo.bpm * 2.0
            val half = tempo.bpm / 2.0
            // Keep the closest-to-dance-range fold as alternate; the engine
            // tests both variants automatically when matching neighbors.
            alternateBpm = if (tempo.bpm < 90) double
            else if (tempo.bpm > 140) half
            else null
        }

        // Estimate the dominant periodic-onset phase relative to the start of
        // the file. This is an onset-grid phase, not a guaranteed musical
        // downbeat; callers must confidence-gate it and fall back gracefully.
        val beatOffsetMs = tempo
            ?.takeIf { it.confidence >= 0.20 }
            ?.let { estimateBeatPhaseMs(odf, workingRate, it.bpm) }

        // ── Key ───────────────────────────────────────────────────────────
        val key = estimateKey(chroma)

        // ── Energy stats ──────────────────────────────────────────────────
        val fps = workingRate.toDouble() / HOP
        val onsetRate = estimateOnsetRate(odf, fps)

        return Result(
            bpm = tempo?.bpm,
            bpmConfidence = tempo?.confidence ?: 0.0,
            alternateBpm = alternateBpm,
            beatOffsetMs = beatOffsetMs,
            tonicPc = key?.first ?: -1,
            isMinor = key?.second?.let { !it } ?: false, // key.second: isMajor
            keyConfidence = key?.third ?: 0.0,
            rmsDb = median(rmsList)?.toDouble(),
            centroidHz = median(centroidList)?.toDouble(),
            onsetRate = onsetRate,
            analyzedSeconds = analyzedSeconds,
        )
    }

    // ── Spectral helpers ──────────────────────────────────────────────────────

    private val LN10 = kotlin.math.ln(10.0).toFloat()

    private fun hann(size: Int): FloatArray {
        val w = FloatArray(size)
        for (i in 0 until size) {
            w[i] = (0.5 - 0.5 * kotlin.math.cos(2.0 * Math.PI * i / size)).toFloat()
        }
        return w
    }

    /** In-place iterative radix-2 FFT (destructive on [re]/[im]). */
    fun fftRadix2(re: FloatArray, im: FloatArray) {
        val n = re.size
        require(n and (n - 1) == 0 && n >= 2) { "FFT size must be a power of two ≥ 2" }
        // Bit-reversal permutation.
        var j = 0
        for (i in 0 until n) {
            if (i < j) {
                var t = re[i]; re[i] = re[j]; re[j] = t
                t = im[i]; im[i] = im[j]; im[j] = t
            }
            var m = n shr 1
            while (m >= 1 && j >= m) {
                j -= m
                m = m shr 1
            }
            j += m
        }
        // Calculate each stage's twiddles once, then reuse them for every group.
        var len = 2
        while (len <= n) {
            val half = len / 2
            val cached = TWIDDLE_TABLES[len]
            val twiddleRe: FloatArray
            val twiddleIm: FloatArray
            if (cached != null) {
                twiddleRe = cached.real
                twiddleIm = cached.imaginary
            } else {
                // Keep the helper generic for transforms larger than the
                // analysis FFT while the production 2048-point path is cached.
                val step = 2.0 * Math.PI / len
                twiddleRe = FloatArray(half)
                twiddleIm = FloatArray(half)
                for (k in 0 until half) {
                    val angle = step * k
                    twiddleRe[k] = kotlin.math.cos(angle).toFloat()
                    twiddleIm[k] = (-kotlin.math.sin(angle)).toFloat()
                }
            }
            var base = 0
            while (base < n) {
                var k = 0
                while (k < half) {
                    val wr = twiddleRe[k]
                    val wi = twiddleIm[k]
                    val a = base + k
                    val b = a + half
                    val xr = re[b] * wr - im[b] * wi
                    val xi = re[b] * wi + im[b] * wr
                    re[b] = re[a] - xr
                    im[b] = im[a] - xi
                    re[a] += xr
                    im[a] += xi
                    k++
                }
                base += len
            }
            len = len shl 1
        }
    }

    /** Mean-preserve decimation with a length-[factor] box anti-alias filter. */
    fun decimate(input: FloatArray, factor: Int): FloatArray {
        if (factor <= 1) return input
        val outSize = input.size / factor
        val out = FloatArray(outSize)
        for (o in 0 until outSize) {
            var acc = 0f
            val start = o * factor
            for (i in 0 until factor) acc += input[start + i]
            out[o] = acc / factor
        }
        return out
    }

    /**
     * Chroma accumulation by fractional pitch-class interpolation. FFT bins
     * between semitone centers contribute proportionally to both neighbors;
     * octave harmonics naturally map back to the same pitch class.
     */
    private fun accumulateChroma(chroma: FloatArray, mag: FloatArray, sampleRate: Int) {
        val bins = mag.size
        for (k in 1 until bins) {
            val freq = k * sampleRate.toDouble() / FFT_SIZE
            if (freq < CHROMA_MIN_FREQ || freq > CHROMA_MAX_FREQ) continue
            val magnitude = mag[k]
            if (magnitude < 1e-6f) continue
            val pitch = 12.0 * log2(freq / 440.0) + 69.0 // MIDI-ish
            val lowerSemitone = kotlin.math.floor(pitch).toInt()
            val pc = ((lowerSemitone % 12) + 12) % 12
            val frac = (pitch - lowerSemitone).coerceIn(0.0, 1.0)
            // Interpolate toward the next pitch class. An octave harmonic maps
            // to the same class, never to an unrelated +10-semitone class.
            chroma[pc] += (magnitude.toDouble() * (1.0 - frac)).toFloat()
            chroma[(pc + 1) % 12] += (magnitude.toDouble() * frac).toFloat()
        }
    }

    private fun log2(x: Double): Double = ln(x) / kotlin.math.ln(2.0)

    // ── Tempo ────────────────────────────────────────────────────────────────

    data class Tempo(val bpm: Double, val confidence: Double)

    /**
     * Autocorrelation of the mean-removed onset envelope + comb scoring
     * across the 60..200 BPM lag range, weighted by a soft log-normal prior.
     */
    fun estimateTempo(odf: FloatArray, workingRate: Int): Tempo? {
        val n = odf.size
        if (workingRate <= 0) return null
        val fps = workingRate.toDouble() / HOP
        if (n < fps.roundToInt()) return null // fewer than ~1 s of onset frames

        // Mean-removal (tightens the autocorrelation peak).
        var mean = 0f
        for (v in odf) mean += v
        mean /= n
        val env = FloatArray(n)
        var energy0 = 0.0
        for (i in 0 until n) {
            env[i] = odf[i] - mean
            energy0 += env[i].toDouble() * env[i]
        }
        if (energy0 < 1e-12) return null

        val lagMin = max(1, (fps * 60.0 / BPM_MAX).roundToInt())
        val lagMax = min(n / 2, (fps * 60.0 / BPM_MIN).roundToInt())
        if (lagMax <= lagMin + 1) return null

        // Regular (biased) autocorrelation for each candidate lag.
        val score = DoubleArray(lagMax + 1)
        for (lag in lagMin..lagMax) {
            var acc = 0.0
            val lim = n - lag
            for (i in 0 until lim) {
                acc += env[i] * env[i + lag]
            }
            score[lag] = acc / lim
        }

        // Comb-filter score — beat period plus its multiples must also line up.
        val comb = DoubleArray(lagMax + 1)
        var best = -1
        var bestScore = -Double.MAX_VALUE
        var sumScore = 0.0
        var minScore = Double.MAX_VALUE
        var maxScore = -Double.MAX_VALUE
        for (lag in lagMin..lagMax) {
            val s = score[lag] +
                COMB_W2 * getLag(score, lag * 2, lagMax) +
                COMB_W3 * getLag(score, lag * 3, lagMax) +
                COMB_W4 * getLag(score, lag * 4, lagMax)
            comb[lag] = s
            val bpm = 60.0 * fps / lag
            val prior = exp(-0.5 * sqr(log2(bpm / BPM_PRIOR_CENTER) / BPM_PRIOR_LOG2_WIDTH))
            val w = s * prior
            sumScore += s
            if (s < minScore) minScore = s
            if (s > maxScore) maxScore = s
            if (w > bestScore) {
                bestScore = w
                best = lag
            }
        }
        if (best <= 0) return null

        val bpm = 60.0 * fps / best
        val meanScore = sumScore / (lagMax - lagMin + 1)
        val spread = (maxScore - minScore).coerceAtLeast(1e-12)
        // Prominence of the winner relative to the score spread, times the
        // raw periodicity strength (0..1 from the A(best)/A(0) ratio).
        val periodicity = max(0.0, score[best] / energy0 * n)
        val prominence = ((comb[best] - meanScore) / spread).coerceIn(0.0, 1.0)
        val confidence = (0.55 * prominence + 0.45 * periodicity.coerceIn(0.0, 1.0))
            .coerceIn(0.0, 1.0)

        return Tempo(bpm, confidence)
    }

    private fun getLag(score: DoubleArray, lag: Int, lagMax: Int): Double =
        if (lag in 1..lagMax) score[lag] else 0.0

    /**
     * Estimates the onset-envelope phase that best repeats at the detected
     * beat period. The result is deliberately nullable: diffuse or weak
     * rhythmic material must use an ordinary crossfade rather than a guessed
     * alignment. Resolution is one STFT hop (about 23 ms at 22.05 kHz).
     */
    private fun estimateBeatPhaseMs(
        odf: FloatArray,
        workingRate: Int,
        bpm: Double,
    ): Double? {
        if (!bpm.isFinite() || bpm !in BPM_MIN..BPM_MAX || workingRate <= 0) return null
        val fps = workingRate.toDouble() / HOP
        val periodFrames = (fps * 60.0 / bpm).roundToInt()
        if (periodFrames < 2 || odf.size < periodFrames * 4) return null

        var mean = 0.0
        for (value in odf) mean += value.toDouble()
        mean /= odf.size

        val phaseScores = DoubleArray(periodFrames)
        var peakCount = 0
        var peakEnergy = 0.0
        for (i in 1 until odf.size - 1) {
            val value = odf[i].toDouble()
            if (value > odf[i - 1] && value >= odf[i + 1] && value > mean) {
                val weight = value - mean
                phaseScores[i % periodFrames] += weight
                peakEnergy += weight
                peakCount++
            }
        }
        if (peakCount < 8 || peakEnergy <= 1e-9) return null

        // Circular smoothing reduces one-hop jitter without changing the
        // phase epoch; beat periods need not land on an integer frame boundary.
        val smoothed = DoubleArray(periodFrames)
        for (phase in 0 until periodFrames) {
            val previous = phaseScores[(phase - 1 + periodFrames) % periodFrames]
            val current = phaseScores[phase]
            val next = phaseScores[(phase + 1) % periodFrames]
            smoothed[phase] = previous * 0.25 + current * 0.5 + next * 0.25
        }

        var bestPhase = 0
        var bestScore = -Double.MAX_VALUE
        var secondScore = -Double.MAX_VALUE
        for (phase in smoothed.indices) {
            val score = smoothed[phase]
            if (score > bestScore) {
                secondScore = bestScore
                bestScore = score
                bestPhase = phase
            } else if (score > secondScore) {
                secondScore = score
            }
        }
        val average = peakEnergy / periodFrames
        if (bestScore <= 0.0 || bestScore < average * 1.03) return null
        if (secondScore > 0.0 && bestScore / secondScore < 1.005) return null
        return bestPhase * HOP * 1000.0 / workingRate
    }

    private fun sqr(x: Double): Double = x * x

    // ── Key ──────────────────────────────────────────────────────────────────

    /** Krumhansl–Schmuckler profiles (Dart's `automixKs*Profile` mirrors these). */
    val KS_MAJOR = doubleArrayOf(
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    )
    val KS_MINOR = doubleArrayOf(
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    )

    /**
     * Returns (tonicPc, isMajor, confidence) — confidence is the Pearson
     * margin between the best and runner-up key (0 when below
     * [KEY_MIN_MARGIN]); null when the chroma is too flat to judge.
     */
    fun estimateKey(chroma: FloatArray): Triple<Int, Boolean, Double>? {
        var total = 0.0
        for (v in chroma) total += v.toDouble()
        if (total < 1e-6) return null

        val c = DoubleArray(12)
        for (i in 0 until 12) c[i] = chroma[i].toDouble()
        normalize(c)

        var bestPc = -1
        var bestMajor = true
        var bestCorr = -Double.MAX_VALUE
        var secondCorr = -Double.MAX_VALUE
        for (mode in 0 until 2) {
            val profile = if (mode == 0) KS_MAJOR else KS_MINOR
            for (shift in 0 until 12) {
                val rotated = DoubleArray(12)
                // Candidate tonic [shift] must align its profile's tonic bin
                // (index 0) with chroma pitch class [shift].
                for (i in 0 until 12) rotated[i] = profile[(i - shift + 12) % 12]
                val r = pearson(c, rotated)
                if (r > bestCorr) {
                    secondCorr = bestCorr
                    bestCorr = r
                    bestPc = shift
                    bestMajor = mode == 0
                } else if (r > secondCorr) {
                    secondCorr = r
                }
            }
        }
        val margin = (bestCorr - secondCorr).coerceAtLeast(0.0)
        val confidence = if (margin < KEY_MIN_MARGIN) 0.0
        else (margin / 0.12).coerceIn(0.0, 1.0)
        return Triple(bestPc, bestMajor, confidence)
    }

    private fun normalize(v: DoubleArray) {
        var sum = 0.0
        for (x in v) sum += x
        if (sum <= 1e-12) return
        for (i in v.indices) v[i] /= sum
    }

    private fun pearson(a: DoubleArray, b: DoubleArray): Double {
        val n = a.size
        var ma = 0.0; var mb = 0.0
        for (i in 0 until n) { ma += a[i]; mb += b[i] }
        ma /= n; mb /= n
        var num = 0.0; var da = 0.0; var db = 0.0
        for (i in 0 until n) {
            val xa = a[i] - ma
            val xb = b[i] - mb
            num += xa * xb
            da += xa * xa
            db += xb * xb
        }
        val den = sqrt(da * db)
        return if (den < 1e-12) 0.0 else num / den
    }

    // ── Misc stats ────────────────────────────────────────────────────────────

    fun median(list: List<Float>): Float? {
        if (list.isEmpty()) return null
        val sorted = list.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 1) sorted[mid]
        else (sorted[mid - 1] + sorted[mid]) / 2f
    }

    /**
     * Count of local maxima of the smoothed onset envelope that stand at
     /// least 0.4× the envelope's standard deviation above its mean,
     * reported per second.
     */
    fun estimateOnsetRate(odf: FloatArray, fps: Double): Double {
        val n = odf.size
        if (n < 4 || fps <= 0) return 0.0
        var mean = 0.0
        for (v in odf) mean += v.toDouble()
        mean /= n
        var varr = 0.0
        for (v in odf) varr += sqr(v.toDouble() - mean)
        val std = sqrt(varr / n).coerceAtLeast(1e-12)
        val thr = mean + 0.4 * std

        // Local maxima strictly above the threshold; a peak must exceed both
        // neighbors so jittered plateau frames don't double-count.
        var count = 0
        for (i in 1 until n - 1) {
            val v = odf[i]
            if (v > odf[i - 1] && v >= odf[i + 1] && v > thr) count++
        }
        return count.toDouble() * fps / n
    }
}
