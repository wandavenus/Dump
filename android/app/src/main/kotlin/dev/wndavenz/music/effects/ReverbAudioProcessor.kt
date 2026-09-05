package dev.wndavenz.music.effects

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer

private const val LOG_TAG = "ReverbProc"

/**
 * Custom AudioProcessor implementing a software **reverb** effect.
 *
 * A Schroeder-style room reverb: four parallel damped comb filters per channel
 * feed two series all-pass filters, producing a dense, smooth, natural tail
 * that sounds like the music is playing inside a warm room — no audible
 * discrete repeats.
 *
 *  - COMBS: four parallel delay lines per channel, incommensurate lengths
 *    (1116/1188/1277/1356 samples @ 44.1 kHz, ±23-sample stereo offsets on
 *    the right channel for width). The low-pass damping inside every comb
 *    makes the tail decay in brightness — warm/dark, never metallic.
 *  - ALLPASS: two series all-pass filters per channel (556/441 samples,
 *    ±23 offset) which smear the comb density into a continuous wash.
 *  - FEEDBACK: intensity × [MAX_FEEDBACK] (max ≈ 0.82, always < 1 → stable).
 *  - WET MIX: intensity × [WET_MAX]; the dry signal always passes at unity.
 *
 *  [intensity] ∈ [0, 1] scales BOTH the feedback depth and the wet mix.
 *  intensity = 0 is a perfect identity (no feedback, no wet, no gain change) —
 *  this is what makes the settings slider behave like an off/on control at its
 *  zero position.
 *
 * Thread safety: [setParams] runs on the main thread; [queueInput] runs on
 * ExoPlayer's audio rendering thread. The intensity field is volatile; all DSP
 * state (delay buffers, indices, filter states) is owned exclusively by the
 * audio thread, so no synchronisation is needed.
 *
 * MONO / multi-channel / other encodings: [onConfigure] returns NOT_SET
 * (transparent bypass).
 */
@UnstableApi
class ReverbAudioProcessor : BaseAudioProcessor() {

    companion object {
        /** Comb delay lengths in samples at the 44.1 kHz reference rate (Freeverb-derived). */
        private val COMB_DELAYS_L = intArrayOf(1116, 1188, 1277, 1356)
        private val COMB_DELAYS_R = intArrayOf(1139, 1211, 1300, 1379)

        /** All-pass delay lengths in samples at the 44.1 kHz reference rate. */
        private val ALLPASS_DELAYS_L = intArrayOf(556, 441)
        private val ALLPASS_DELAYS_R = intArrayOf(579, 464)

        /** Max comb feedback gain applied at full intensity (always < 1 → stable). */
        private const val MAX_FEEDBACK = 0.82f

        /** One-pole low-pass smoothing on the comb feedback (darker, warmer tail). */
        private const val DAMPING = 0.4f

        /** Fixed all-pass coefficient in (0, 1). */
        private const val ALLPASS_COEFF = 0.5f

        /** Max wet mix at full intensity; the dry signal always passes at unity. */
        private const val WET_MAX = 0.55f

        /** Reference sample rate the delay tables above are tuned for. */
        private const val REF_SAMPLE_RATE = 44100
    }

    @Volatile private var intensity: Float = 0f

    // ── Per-format DSP state (audio thread only) ────────────────────────────
    private var sampleRate = -1

    // Float path (the real one — ToFloatPcmAudioProcessor guarantees it).
    private var combL: Array<FloatArray>? = null   // one buffer per comb
    private var combR: Array<FloatArray>? = null
    private var combPosL: IntArray? = null          // circular write position per comb
    private var combPosR: IntArray? = null
    private var combFilterL: DoubleArray? = null    // per-comb low-pass state
    private var combFilterR: DoubleArray? = null
    private var allpassL: Array<FloatArray>? = null
    private var allpassR: Array<FloatArray>? = null
    private var allpassPosL: IntArray? = null
    private var allpassPosR: IntArray? = null
    private var combSizesL: IntArray? = null        // scaled delay lengths
    private var allpassSizesL: IntArray? = null

    // PCM-16 path (defensive; the chain forces float in practice).
    private var combL16: Array<ShortArray>? = null
    private var combR16: Array<ShortArray>? = null
    private var combPosL16: IntArray? = null
    private var combPosR16: IntArray? = null
    private var combFilterL16: DoubleArray? = null
    private var combFilterR16: DoubleArray? = null
    private var allpassL16: Array<ShortArray>? = null
    private var allpassR16: Array<ShortArray>? = null
    private var allpassPosL16: IntArray? = null
    private var allpassPosR16: IntArray? = null
    private var combSizesL16: IntArray? = null
    private var allpassSizesL16: IntArray? = null

    fun setParams(enabled: Boolean, intensity: Float) {
        // MethodChannel values are normally finite, but an invalid value must
        // never reach the feedback loop: a single NaN would contaminate the
        // delay lines and produce NaN PCM until the processor is recreated.
        this.intensity = if (enabled && intensity.isFinite()) {
            intensity.coerceIn(0f, 1f)
        } else {
            0f
        }
    }

    /**
     * Drops delayed samples after a seek, track transition, or sink flush.
     *
     * Keeping the old delay lines would leak a previous track's reverb tail
     * into the next track and keeps sizeable buffers allocated after the sink
     * is flushed. State is allocated lazily on the next input buffer.
     */
    override fun onFlush() {
        clearState()
    }

    override fun onReset() {
        clearState()
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val supported = inputAudioFormat.channelCount == 2 && (
            inputAudioFormat.encoding == C.ENCODING_PCM_16BIT ||
            inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        )
        Log.i(
            LOG_TAG,
            "onConfigure encoding=${inputAudioFormat.encoding} " +
                "channels=${inputAudioFormat.channelCount} supported=$supported",
        )
        return if (supported) inputAudioFormat else AudioProcessor.AudioFormat.NOT_SET
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining == 0) return

        val inten = intensity
        if (inten <= 0f) {
            // Identity: drain the buffer untouched (BaseAudioProcessor still
            // requires the output buffer to be produced by replaceOutputBuffer).
            val pass = replaceOutputBuffer(remaining)
            pass.put(inputBuffer)
            pass.flip()
            return
        }

        val output = replaceOutputBuffer(remaining)
        if (inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT) {
            processFloat(inputBuffer, output, inten)
        } else {
            processPcm16(inputBuffer, output, inten)
        }
        while (inputBuffer.hasRemaining()) output.put(inputBuffer.get())
        output.flip()
    }

    // ── Float path (the real one — ToFloatPcmAudioProcessor guarantees it) ──

    private fun scaledDelay(refSamples: Int, sr: Int): Int {
        // Scale the 44.1 kHz-tuned delay tables to the actual sample rate.
        // The +1 guarantees a strictly positive delay (always ≥ 2 samples).
        return (refSamples.toLong() * sr / REF_SAMPLE_RATE).toInt().coerceAtLeast(1) + 1
    }

    private fun processFloat(inputBuffer: ByteBuffer, output: ByteBuffer, inten: Float) {
        val sr = inputAudioFormat.sampleRate
        ensureFloatState(sr)
        val cbL = combL!!
        val cbR = combR!!
        val cpL = combPosL!!
        val cpR = combPosR!!
        val cfL = combFilterL!!
        val cfR = combFilterR!!
        val apL = allpassL!!
        val apR = allpassR!!
        val apPL = allpassPosL!!
        val apPR = allpassPosR!!
        val cSizeL = combSizesL!!

        val numCombs = cbL.size
        val numAllpass = apL.size
        val fb = (MAX_FEEDBACK * inten).toDouble()
        val wet = (WET_MAX * inten).toDouble()
        val damp = DAMPING.toDouble()
        val apCoeff = ALLPASS_COEFF.toDouble()
        val combScale = 1.0 / numCombs

        val frameCount = inputBuffer.remaining() / 8
        repeat(frameCount) {
            val lIn = inputBuffer.float.toDouble()
            val rIn = inputBuffer.float.toDouble()

            // ── Left channel ────────────────────────────────────────────────
            var acc = 0.0
            for (i in 0 until numCombs) {
                val pos = cpL[i]
                val buf = cbL[i]
                val delayOut = buf[pos].toDouble()
                val filtered = delayOut * damp + cfL[i] * (1.0 - damp)
                buf[pos] = (lIn + filtered * fb).toFloat()
                cfL[i] = filtered
                acc += delayOut
                cpL[i] = (pos + 1) % cSizeL[i]
            }
            acc *= combScale
            for (i in 0 until numAllpass) {
                val pos = apPL[i]
                val buf = apL[i]
                val bufOut = buf[pos].toDouble()
                buf[pos] = (acc + apCoeff * bufOut).toFloat()
                acc = bufOut - apCoeff * acc
                apPL[i] = (pos + 1) % buf.size
            }
            val outL = lIn + wet * acc

            // ── Right channel ───────────────────────────────────────────────
            var accR = 0.0
            for (i in 0 until numCombs) {
                val pos = cpR[i]
                val buf = cbR[i]
                val delayOut = buf[pos].toDouble()
                val filtered = delayOut * damp + cfR[i] * (1.0 - damp)
                buf[pos] = (rIn + filtered * fb).toFloat()
                cfR[i] = filtered
                accR += delayOut
                cpR[i] = (pos + 1) % buf.size
            }
            accR *= combScale
            for (i in 0 until numAllpass) {
                val pos = apPR[i]
                val buf = apR[i]
                val bufOut = buf[pos].toDouble()
                buf[pos] = (accR + apCoeff * bufOut).toFloat()
                accR = bufOut - apCoeff * accR
                apPR[i] = (pos + 1) % buf.size
            }
            val outR = rIn + wet * accR

            output.putFloat(outL.toFloat())
            output.putFloat(outR.toFloat())
        }
    }

    // ── PCM-16 path (defensive; the chain forces float in practice) ────────

    private fun processPcm16(inputBuffer: ByteBuffer, output: ByteBuffer, inten: Float) {
        val sr = inputAudioFormat.sampleRate
        ensureShortState(sr)
        val cbL = combL16!!
        val cbR = combR16!!
        val cpL = combPosL16!!
        val cpR = combPosR16!!
        val cfL = combFilterL16!!
        val cfR = combFilterR16!!
        val apL = allpassL16!!
        val apR = allpassR16!!
        val apPL = allpassPosL16!!
        val apPR = allpassPosR16!!
        val cSizeL = combSizesL16!!

        val numCombs = cbL.size
        val numAllpass = apL.size
        val fb = (MAX_FEEDBACK * inten).toDouble()
        val wet = (WET_MAX * inten).toDouble()
        val damp = DAMPING.toDouble()
        val apCoeff = ALLPASS_COEFF.toDouble()
        val combScale = 1.0 / numCombs

        val frameCount = inputBuffer.remaining() / 4
        repeat(frameCount) {
            val lIn = inputBuffer.short.toDouble()
            val rIn = inputBuffer.short.toDouble()

            // ── Left channel ────────────────────────────────────────────────
            var acc = 0.0
            for (i in 0 until numCombs) {
                val pos = cpL[i]
                val buf = cbL[i]
                val delayOut = buf[pos].toDouble()
                val filtered = delayOut * damp + cfL[i] * (1.0 - damp)
                buf[pos] = (lIn + filtered * fb)
                    .coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble())
                    .toInt().toShort()
                cfL[i] = filtered
                acc += delayOut
                cpL[i] = (pos + 1) % cSizeL[i]
            }
            acc *= combScale
            for (i in 0 until numAllpass) {
                val pos = apPL[i]
                val buf = apL[i]
                val bufOut = buf[pos].toDouble()
                buf[pos] = (acc + apCoeff * bufOut)
                    .coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble())
                    .toInt().toShort()
                acc = bufOut - apCoeff * acc
                apPL[i] = (pos + 1) % buf.size
            }
            val outL = lIn + wet * acc

            // ── Right channel ───────────────────────────────────────────────
            var accR = 0.0
            for (i in 0 until numCombs) {
                val pos = cpR[i]
                val buf = cbR[i]
                val delayOut = buf[pos].toDouble()
                val filtered = delayOut * damp + cfR[i] * (1.0 - damp)
                buf[pos] = (rIn + filtered * fb)
                    .coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble())
                    .toInt().toShort()
                cfR[i] = filtered
                accR += delayOut
                cpR[i] = (pos + 1) % buf.size
            }
            accR *= combScale
            for (i in 0 until numAllpass) {
                val pos = apPR[i]
                val buf = apR[i]
                val bufOut = buf[pos].toDouble()
                buf[pos] = (accR + apCoeff * bufOut)
                    .coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble())
                    .toInt().toShort()
                accR = bufOut - apCoeff * accR
                apPR[i] = (pos + 1) % buf.size
            }
            val outR = rIn + wet * accR

            output.putShort(
                outL.coerceIn(
                    Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble(),
                ).toInt().toShort(),
            )
            output.putShort(
                outR.coerceIn(
                    Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble(),
                ).toInt().toShort(),
            )
        }
    }

    // ── State (re)allocation on format change ───────────────────────────────

    private fun ensureFloatState(sr: Int) {
        if (sampleRate == sr && combL != null) return
        sampleRate = sr
        combSizesL = IntArray(COMB_DELAYS_L.size) { i -> scaledDelay(COMB_DELAYS_L[i], sr) }
        val cSizeR = IntArray(COMB_DELAYS_R.size) { i -> scaledDelay(COMB_DELAYS_R[i], sr) }
        allpassSizesL = IntArray(ALLPASS_DELAYS_L.size) { i -> scaledDelay(ALLPASS_DELAYS_L[i], sr) }
        val aSizeR = IntArray(ALLPASS_DELAYS_R.size) { i -> scaledDelay(ALLPASS_DELAYS_R[i], sr) }

        combL = Array(combSizesL!!.size) { i -> FloatArray(combSizesL!![i]) }
        combR = Array(cSizeR.size) { i -> FloatArray(cSizeR[i]) }
        combPosL = IntArray(combSizesL!!.size)
        combPosR = IntArray(cSizeR.size)
        combFilterL = DoubleArray(combSizesL!!.size)
        combFilterR = DoubleArray(cSizeR.size)
        allpassL = Array(allpassSizesL!!.size) { i -> FloatArray(allpassSizesL!![i]) }
        allpassR = Array(aSizeR.size) { i -> FloatArray(aSizeR[i]) }
        allpassPosL = IntArray(allpassSizesL!!.size)
        allpassPosR = IntArray(aSizeR.size)
    }

    private fun ensureShortState(sr: Int) {
        if (sampleRate == sr && combL16 != null) return
        sampleRate = sr
        combSizesL16 = IntArray(COMB_DELAYS_L.size) { i -> scaledDelay(COMB_DELAYS_L[i], sr) }
        val cSizeR = IntArray(COMB_DELAYS_R.size) { i -> scaledDelay(COMB_DELAYS_R[i], sr) }
        val aSizeL = IntArray(ALLPASS_DELAYS_L.size) { i -> scaledDelay(ALLPASS_DELAYS_L[i], sr) }
        val aSizeR = IntArray(ALLPASS_DELAYS_R.size) { i -> scaledDelay(ALLPASS_DELAYS_R[i], sr) }

        combL16 = Array(combSizesL16!!.size) { i -> ShortArray(combSizesL16!![i]) }
        combR16 = Array(cSizeR.size) { i -> ShortArray(cSizeR[i]) }
        combPosL16 = IntArray(combSizesL16!!.size)
        combPosR16 = IntArray(cSizeR.size)
        combFilterL16 = DoubleArray(combSizesL16!!.size)
        combFilterR16 = DoubleArray(cSizeR.size)
        allpassL16 = Array(aSizeL.size) { i -> ShortArray(aSizeL[i]) }
        allpassR16 = Array(aSizeR.size) { i -> ShortArray(aSizeR[i]) }
        allpassPosL16 = IntArray(aSizeL.size)
        allpassPosR16 = IntArray(aSizeR.size)
    }

    private fun clearState() {
        sampleRate = -1
        combL = null
        combR = null
        combPosL = null
        combPosR = null
        combFilterL = null
        combFilterR = null
        allpassL = null
        allpassR = null
        allpassPosL = null
        allpassPosR = null
        combSizesL = null
        allpassSizesL = null
        combL16 = null
        combR16 = null
        combPosL16 = null
        combPosR16 = null
        combFilterL16 = null
        combFilterR16 = null
        allpassL16 = null
        allpassR16 = null
        allpassPosL16 = null
        allpassPosR16 = null
        combSizesL16 = null
        allpassSizesL16 = null
    }
}
