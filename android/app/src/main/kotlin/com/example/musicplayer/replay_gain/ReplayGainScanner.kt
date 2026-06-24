package com.example.musicplayer.replay_gain

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteOrder
import kotlin.math.*

/**
 * Standalone EBU R128 loudness scanner + ReplayGain tag writer.
 *
 * Algorithm:
 *  1. Decode PCM via MediaExtractor + MediaCodec.
 *  2. Apply K-weighting filter (two biquad stages per ITU-R BS.1770-4).
 *  3. Compute mean-square power in non-overlapping 400 ms blocks.
 *  4. Apply absolute gate (−70 LUFS) then relative gate (−10 LU) per EBU R128.
 *  5. Integrated loudness → trackGain = TARGET_LUFS − integratedLufs.
 *  6. Write REPLAYGAIN_TRACK_GAIN / REPLAYGAIN_TRACK_PEAK via jaudiotagger.
 */
object ReplayGainScanner {

    data class ScanResult(
        val integratedLufs: Double,
        val trackGainDb: Double,
        val trackPeak: Double,
    )

    private const val TARGET_LUFS   = -18.0   // ReplayGain reference (−18 LUFS = 89 dB SPL)
    private const val GATE_ABS      = -70.0   // EBU R128 absolute gate threshold
    private const val GATE_REL_OFFS = -10.0   // EBU R128 relative gate offset (LU)
    private const val BLOCK_MS      = 400     // gating block duration (ms)

    // ── K-weighting biquad coefficients ────────────────────────────────────────

    private data class BiquadCoeffs(val b0: Double, val b1: Double, val b2: Double,
                                     val a1: Double, val a2: Double)
    private data class BiquadState(var x1: Double = 0.0, var x2: Double = 0.0,
                                    var y1: Double = 0.0, var y2: Double = 0.0)

    /**
     * Computes K-weighting filter coefficients at the given sample rate.
     * Returns (stage1_preFilter, stage2_rlbHighPass).
     */
    private fun kWeightingCoeffs(sampleRate: Int): Pair<BiquadCoeffs, BiquadCoeffs> {
        val fs = sampleRate.toDouble()
        val pi = Math.PI

        // Stage 1 — Pre-filter (high-shelf, f0 ≈ 1682 Hz, G ≈ +4 dB)
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

        // Stage 2 — RLB high-pass (f0 ≈ 38 Hz)
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
     */
    fun scan(path: String, onProgress: (Float) -> Unit): ScanResult? {
        val file = File(path)
        if (!file.exists()) return null

        val extractor = MediaExtractor()
        try { extractor.setDataSource(path) }
        catch (_: Exception) { extractor.release(); return null }

        // Locate first audio track
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

        // Per-block accumulators
        var blockMsAcc   = 0.0
        var blockSamples = 0
        var peakAbs      = 0.0

        val info = MediaCodec.BufferInfo()
        var eos  = false

        try {
            while (!eos) {
                // ── Feed input ─────────────────────────────────────────────────
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

                // ── Drain output ───────────────────────────────────────────────
                val outIdx = codec.dequeueOutputBuffer(info, 8_000L)
                if (outIdx >= 0) {
                    val outBuf = codec.getOutputBuffer(outIdx)
                    if (outBuf != null && info.size > 0) {
                        outBuf.position(info.offset)
                        outBuf.limit(info.offset + info.size)
                        outBuf.order(ByteOrder.LITTLE_ENDIAN)
                        val sb = outBuf.asShortBuffer()

                        while (sb.hasRemaining()) {
                            // One interleaved frame across all channels
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

        // ── EBU R128 gating ────────────────────────────────────────────────────
        val eps = 1e-10

        // Absolute gate: discard blocks below −70 LUFS
        val absThreshLinear = 10.0.pow((GATE_ABS + 0.691) / 10.0)
        val passAbs = blockMeanSquares.filter { it >= absThreshLinear }
        if (passAbs.isEmpty()) {
            val lufs = GATE_ABS
            return ScanResult(lufs, TARGET_LUFS - lufs, peakAbs)
        }

        // Relative gate: mean of abs-gated blocks − 10 LU
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

    // ── Tag writing ─────────────────────────────────────────────────────────────

    /**
     * Writes REPLAYGAIN_TRACK_GAIN and REPLAYGAIN_TRACK_PEAK tags to [path].
     * Returns true on success.  May fail on Android 10+ if the file is not
     * in the app sandbox and no write permission is granted.
     */
    fun writeTags(path: String, result: ScanResult): Boolean {
        return try {
            val file      = File(path)
            val audioFile = org.jaudiotagger.audio.AudioFileIO.read(file)
            var tag       = audioFile.tag
            if (tag == null) { audioFile.createDefaultTag(); tag = audioFile.tag }

            val gainStr = "%+.2f dB".format(result.trackGainDb)
            val peakStr = "%.6f".format(result.trackPeak.coerceAtMost(1.0))

            when (tag) {
                is org.jaudiotagger.tag.id3.AbstractID3v2Tag -> {
                    // MP3 — TXXX frames (same as existing reader expects)
                    writeTxxx(tag, "REPLAYGAIN_TRACK_GAIN", gainStr)
                    writeTxxx(tag, "REPLAYGAIN_TRACK_PEAK", peakStr)
                }
                is org.jaudiotagger.tag.vorbiscomment.VorbisCommentTag -> {
                    // OGG / FLAC — raw Vorbis comment string fields
                    writeVorbisField(tag, "REPLAYGAIN_TRACK_GAIN", gainStr)
                    writeVorbisField(tag, "REPLAYGAIN_TRACK_PEAK", peakStr)
                }
                else -> {
                    // M4A / other — generic FieldKey (may throw for unsupported formats)
                    tag.setField(org.jaudiotagger.tag.FieldKey.REPLAYGAIN_TRACK_GAIN, gainStr)
                    tag.setField(org.jaudiotagger.tag.FieldKey.REPLAYGAIN_TRACK_PEAK, peakStr)
                }
            }

            org.jaudiotagger.audio.AudioFileIO.write(audioFile)
            true
        } catch (_: Exception) { false }
    }

    private fun writeVorbisField(
        tag: org.jaudiotagger.tag.vorbiscomment.VorbisCommentTag,
        key: String,
        value: String,
    ) {
        runCatching { tag.deleteField(key) }
        runCatching {
            // VorbisCommentTagField accepts a raw key=value string pair
            val field = org.jaudiotagger.tag.vorbiscomment.VorbisCommentTagField(key, value)
            tag.setField(field)
        }
    }

    private fun writeTxxx(tag: org.jaudiotagger.tag.id3.AbstractID3v2Tag,
                          description: String, value: String) {
        // Remove existing TXXX frame(s) with matching description
        runCatching {
            val raw = tag.getFrame("TXXX")
            val frames = when (raw) { is List<*> -> raw; null -> emptyList<Any>(); else -> listOf(raw) }
            frames.filterIsInstance<org.jaudiotagger.tag.id3.AbstractTagFrame>()
                .filter {
                    (it.body as? org.jaudiotagger.tag.id3.framebody.FrameBodyTXXX)
                        ?.description.equals(description, ignoreCase = true)
                }
                .forEach { tag.removeFrame(it) }
        }
        // Write new TXXX frame
        runCatching {
            val body = org.jaudiotagger.tag.id3.framebody.FrameBodyTXXX().apply {
                this.description      = description
                this.userFriendlyValue = value
            }
            // Use ID3v24Frame or ID3v23Frame depending on tag version
            val frame: org.jaudiotagger.tag.id3.AbstractTagFrame =
                if (tag is org.jaudiotagger.tag.id3.ID3v24Tag)
                    org.jaudiotagger.tag.id3.ID3v24Frame("TXXX").also { it.body = body }
                else
                    org.jaudiotagger.tag.id3.ID3v23Frame("TXXX").also { it.body = body }
            tag.setFrame(frame)
        }
    }
}
