package com.example.musicplayer.replay_gain

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteOrder
import kotlin.math.*

/**
 * Standalone EBU R128 loudness scanner.
 *
 * Algorithm:
 *  1. Decode PCM via MediaExtractor + MediaCodec (fully native, no third-party libs).
 *  2. Apply K-weighting filter (two biquad stages per ITU-R BS.1770-4).
 *  3. Compute mean-square power in non-overlapping 400 ms blocks.
 *  4. Apply absolute gate (−70 LUFS) then relative gate (−10 LU) per EBU R128.
 *  5. Integrated loudness → trackGain = TARGET_LUFS − integratedLufs.
 *
 * Scan results are returned to the caller and stored in the native
 * [com.example.musicplayer.metadata.MetadataCacheDb] instead of being
 * written back into the audio file.  This approach is reliable on
 * Android 10+ (including MIUI 11+) where direct file-tag writes often
 * fail due to scoped storage restrictions.
 */
object ReplayGainScanner {

    data class ScanResult(
        val integratedLufs: Double,
        val trackGainDb: Double,
        val trackPeak: Double,
    )

    private const val TARGET_LUFS   = -18.0
    private const val GATE_ABS      = -70.0
    private const val GATE_REL_OFFS = -10.0
    private const val BLOCK_MS      = 400

    // ── K-weighting biquad coefficients ────────────────────────────────────────

    private data class BiquadCoeffs(val b0: Double, val b1: Double, val b2: Double,
                                     val a1: Double, val a2: Double)
    private data class BiquadState(var x1: Double = 0.0, var x2: Double = 0.0,
                                    var y1: Double = 0.0, var y2: Double = 0.0)

    private fun kWeightingCoeffs(sampleRate: Int): Pair<BiquadCoeffs, BiquadCoeffs> {
        val fs = sampleRate.toDouble()
        val pi = Math.PI

        val f0Pre = 1681.974450955533
        val G     = 3.999843853973347
        val qPre  = 0.7071752369554196
        val k1    = tan(pi * f0Pre / fs)
        val vh    = 10.0.pow(G / 20.0)
        val vb    = vh.pow(0.4845)
        val n1    = 1.0 / (1.0 + k1 / qPre + k1 * k1)
        val pre   = BiquadCoeffs(
            b0 = (vh + vb * k1 / qPre + k1 * k1) * n1,
            b1 = 2.0 * (k1 * k1 - vh) * n1,
            b2 = (vh - vb * k1 / qPre + k1 * k1) * n1,
            a1 = 2.0 * (k1 * k1 - 1.0) * n1,
            a2 = (1.0 - k1 / qPre + k1 * k1) * n1,
        )

        val f0Rlb = 38.13547087602444
        val qRlb  = 0.5003270373238773
        val k2    = tan(pi * f0Rlb / fs)
        val n2    = 1.0 / (1.0 + k2 / qRlb + k2 * k2)
        val rlb   = BiquadCoeffs(
            b0 = n2,
            b1 = -2.0 * n2,
            b2 = n2,
            a1 = 2.0 * (k2 * k2 - 1.0) * n2,
            a2 = (1.0 - k2 / qRlb + k2 * k2) * n2,
        )
        return Pair(pre, rlb)
    }

    private fun applyBiquad(x: Double, c: BiquadCoeffs, s: BiquadState): Double {
        val y = c.b0 * x + c.b1 * s.x1 + c.b2 * s.x2 - c.a1 * s.y1 - c.a2 * s.y2
        s.x2 = s.x1; s.x1 = x
        s.y2 = s.y1; s.y1 = y
        return y
    }

    // ── Main entry point ───────────────────────────────────────────────────────

    /**
     * Decodes [path], measures integrated loudness (EBU R128), and returns a
     * [ScanResult].  [onProgress] is called with 0.0–1.0 on the calling thread.
     * Returns null if the file cannot be decoded.
     */
    fun scan(path: String, onProgress: (Float) -> Unit): ScanResult? {
        val file = File(path)
        if (!file.exists()) return null

        val extractor = MediaExtractor()
        try { extractor.setDataSource(path) }
        catch (_: Exception) { extractor.release(); return null }

        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                trackIndex = i; format = f; break
            }
        }
        if (trackIndex < 0 || format == null) { extractor.release(); return null }

        val mime       = format.getString(MediaFormat.KEY_MIME) ?: ""
        val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channels   = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceIn(1, 8)
        val durationUs = runCatching { format.getLong(MediaFormat.KEY_DURATION) }.getOrDefault(-1L)

        extractor.selectTrack(trackIndex)

        val codec = try {
            MediaCodec.createDecoderByType(mime).also {
                it.configure(format, null, null, 0)
                it.start()
            }
        } catch (_: Exception) { extractor.release(); return null }

        val (preCoeffs, rlbCoeffs) = kWeightingCoeffs(sampleRate)
        val preStates = Array(channels) { BiquadState() }
        val rlbStates = Array(channels) { BiquadState() }

        val blockSizeSamples = (sampleRate * BLOCK_MS / 1000).coerceAtLeast(1)
        val blockMeanSquares = mutableListOf<Double>()

        var blockMsAcc   = 0.0
        var blockSamples = 0
        var peakAbs      = 0.0

        val info = MediaCodec.BufferInfo()
        var eos  = false

        try {
            while (!eos) {
                val inIdx = codec.dequeueInputBuffer(8_000L)
                if (inIdx >= 0) {
                    val inBuf = codec.getInputBuffer(inIdx)
                    if (inBuf != null) {
                        val n = extractor.readSampleData(inBuf, 0)
                        if (n <= 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            eos = true
                        } else {
                            val ts = extractor.sampleTime
                            codec.queueInputBuffer(inIdx, 0, n, ts, 0)
                            extractor.advance()
                            if (durationUs > 0L)
                                onProgress((ts.toFloat() / durationUs).coerceIn(0f, 0.99f))
                        }
                    }
                }

                val outIdx = codec.dequeueOutputBuffer(info, 8_000L)
                if (outIdx >= 0) {
                    val outBuf = codec.getOutputBuffer(outIdx)
                    if (outBuf != null && info.size > 0) {
                        outBuf.position(info.offset)
                        outBuf.limit(info.offset + info.size)
                        outBuf.order(ByteOrder.LITTLE_ENDIAN)
                        val sb = outBuf.asShortBuffer()

                        while (sb.hasRemaining()) {
                            var frameMsSum = 0.0
                            for (ch in 0 until channels) {
                                val raw = if (sb.hasRemaining()) sb.get().toDouble() / 32768.0 else 0.0
                                if (abs(raw) > peakAbs) peakAbs = abs(raw)
                                val s1 = applyBiquad(raw, preCoeffs, preStates[ch])
                                val s2 = applyBiquad(s1,  rlbCoeffs, rlbStates[ch])
                                frameMsSum += s2 * s2
                            }
                            blockMsAcc += frameMsSum / channels
                            blockSamples++

                            if (blockSamples >= blockSizeSamples) {
                                blockMeanSquares.add(blockMsAcc / blockSizeSamples)
                                blockMsAcc   = 0.0
                                blockSamples = 0
                            }
                        }
                    }
                    codec.releaseOutputBuffer(outIdx, false)
                }
                if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
            }
        } finally {
            runCatching { codec.stop() }
            runCatching { codec.release() }
            runCatching { extractor.release() }
        }

        onProgress(1.0f)
        if (blockMeanSquares.isEmpty()) return null

        val eps = 1e-10

        val absThreshLinear = 10.0.pow((GATE_ABS + 0.691) / 10.0)
        val passAbs = blockMeanSquares.filter { it >= absThreshLinear }
        if (passAbs.isEmpty()) {
            val lufs = GATE_ABS
            return ScanResult(lufs, TARGET_LUFS - lufs, peakAbs)
        }

        val relThreshLinear = (passAbs.sum() / passAbs.size) * 10.0.pow(GATE_REL_OFFS / 10.0)
        val passRel = passAbs.filter { it >= relThreshLinear }
        if (passRel.isEmpty()) {
            val lufs = GATE_ABS
            return ScanResult(lufs, TARGET_LUFS - lufs, peakAbs)
        }

        val integratedLinear = passRel.sum() / passRel.size
        val integratedLufs   = -0.691 + 10.0 * log10(integratedLinear + eps)
        val trackGainDb      = TARGET_LUFS - integratedLufs

        return ScanResult(integratedLufs, trackGainDb, peakAbs)
    }
}
