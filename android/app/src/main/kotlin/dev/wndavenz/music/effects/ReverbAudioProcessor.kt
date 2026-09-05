package dev.wndavenz.music.effects

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import kotlin.math.abs
import kotlin.math.tanh

private const val LOG_TAG = "ReverbProc"

/**
 * Software Schroeder-style reverb.
 *
 * Reverb is mixed with explicit dry/wet gain staging instead of relying on
 * a limiter as the normal operating level control. The limiter remains only
 * as a final safety ceiling for exceptional peaks.
 */
@UnstableApi
class ReverbAudioProcessor : BaseAudioProcessor() {

    companion object {
        private val COMB_DELAYS_L = intArrayOf(1116, 1188, 1277, 1356)
        private val COMB_DELAYS_R = intArrayOf(1139, 1211, 1300, 1379)
        private val ALLPASS_DELAYS_L = intArrayOf(556, 441)
        private val ALLPASS_DELAYS_R = intArrayOf(579, 464)
        private const val MAX_FEEDBACK = 0.76f
        private const val DAMPING = 0.4f
        private const val ALLPASS_COEFF = 0.5f
        private const val WET_MAX = 0.30f
        private const val DRY_MIN = 0.70f
        private const val REF_SAMPLE_RATE = 44100

        private const val LIMIT_CEILING = 0.98
        private const val LIMIT_RANGE = 0.02

        private fun limitSample(x: Double): Double {
            val ax = abs(x)
            if (!ax.isFinite()) return 0.0
            if (ax <= LIMIT_CEILING) return x
            val compressed = LIMIT_CEILING + LIMIT_RANGE * tanh((ax - LIMIT_CEILING) / LIMIT_RANGE)
            return if (x < 0.0) -compressed else compressed
        }
    }

    @Volatile private var intensity: Float = 0f
    private var sampleRate = -1

    private var combL: Array<FloatArray>? = null
    private var combR: Array<FloatArray>? = null
    private var combPosL: IntArray? = null
    private var combPosR: IntArray? = null
    private var combFilterL: DoubleArray? = null
    private var combFilterR: DoubleArray? = null
    private var allpassL: Array<FloatArray>? = null
    private var allpassR: Array<FloatArray>? = null
    private var allpassPosL: IntArray? = null
    private var allpassPosR: IntArray? = null
    private var combSizesL: IntArray? = null
    private var allpassSizesL: IntArray? = null

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
        this.intensity = if (enabled && intensity.isFinite()) intensity.coerceIn(0f, 1f) else 0f
    }

    override fun onFlush() = clearState()
    override fun onReset() = clearState()

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val supported = inputAudioFormat.channelCount == 2 && (
            inputAudioFormat.encoding == C.ENCODING_PCM_16BIT ||
            inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        )
        Log.i(LOG_TAG, "onConfigure encoding=${inputAudioFormat.encoding} channels=${inputAudioFormat.channelCount} supported=$supported")
        return if (supported) inputAudioFormat else AudioProcessor.AudioFormat.NOT_SET
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining == 0) return
        val inten = intensity
        if (inten <= 0f) {
            val pass = replaceOutputBuffer(remaining)
            pass.put(inputBuffer)
            pass.flip()
            return
        }
        val output = replaceOutputBuffer(remaining)
        if (inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT) processFloat(inputBuffer, output, inten)
        else processPcm16(inputBuffer, output, inten)
        while (inputBuffer.hasRemaining()) output.put(inputBuffer.get())
        output.flip()
    }

    private fun scaledDelay(refSamples: Int, sr: Int): Int =
        (refSamples.toLong() * sr / REF_SAMPLE_RATE).toInt().coerceAtLeast(1) + 1

    private fun dryGain(inten: Float): Double = 1.0 - (1.0 - DRY_MIN) * inten

    private fun processFloat(inputBuffer: ByteBuffer, output: ByteBuffer, inten: Float) {
        val sr = inputAudioFormat.sampleRate
        ensureFloatState(sr)
        val cbL = combL!!; val cbR = combR!!
        val cpL = combPosL!!; val cpR = combPosR!!
        val cfL = combFilterL!!; val cfR = combFilterR!!
        val apL = allpassL!!; val apR = allpassR!!
        val apPL = allpassPosL!!; val apPR = allpassPosR!!
        val cSizeL = combSizesL!!
        val numCombs = cbL.size; val numAllpass = apL.size
        val fb = MAX_FEEDBACK * inten.toDouble()
        val wet = WET_MAX * inten.toDouble()
        val dry = dryGain(inten)
        val damp = DAMPING.toDouble(); val apCoeff = ALLPASS_COEFF.toDouble()
        val combScale = 1.0 / numCombs

        repeat(inputBuffer.remaining() / 8) {
            val lIn = inputBuffer.float.toDouble(); val rIn = inputBuffer.float.toDouble()
            var acc = 0.0
            for (i in 0 until numCombs) {
                val pos = cpL[i]; val buf = cbL[i]; val delayOut = buf[pos].toDouble()
                val filtered = delayOut * damp + cfL[i] * (1.0 - damp)
                buf[pos] = (lIn + filtered * fb).toFloat(); cfL[i] = filtered; acc += delayOut
                cpL[i] = (pos + 1) % cSizeL[i]
            }
            acc *= combScale
            for (i in 0 until numAllpass) {
                val pos = apPL[i]; val buf = apL[i]; val bufOut = buf[pos].toDouble()
                buf[pos] = (acc + apCoeff * bufOut).toFloat(); acc = bufOut - apCoeff * acc
                apPL[i] = (pos + 1) % buf.size
            }
            val outL = limitSample(dry * lIn + wet * acc)

            var accR = 0.0
            for (i in 0 until numCombs) {
                val pos = cpR[i]; val buf = cbR[i]; val delayOut = buf[pos].toDouble()
                val filtered = delayOut * damp + cfR[i] * (1.0 - damp)
                buf[pos] = (rIn + filtered * fb).toFloat(); cfR[i] = filtered; accR += delayOut
                cpR[i] = (pos + 1) % buf.size
            }
            accR *= combScale
            for (i in 0 until numAllpass) {
                val pos = apPR[i]; val buf = apR[i]; val bufOut = buf[pos].toDouble()
                buf[pos] = (accR + apCoeff * bufOut).toFloat(); accR = bufOut - apCoeff * accR
                apPR[i] = (pos + 1) % buf.size
            }
            val outR = limitSample(dry * rIn + wet * accR)
            output.putFloat(outL.toFloat()); output.putFloat(outR.toFloat())
        }
    }

    private fun processPcm16(inputBuffer: ByteBuffer, output: ByteBuffer, inten: Float) {
        val sr = inputAudioFormat.sampleRate
        ensureShortState(sr)
        val cbL = combL16!!; val cbR = combR16!!
        val cpL = combPosL16!!; val cpR = combPosR16!!
        val cfL = combFilterL16!!; val cfR = combFilterR16!!
        val apL = allpassL16!!; val apR = allpassR16!!
        val apPL = allpassPosL16!!; val apPR = allpassPosR16!!
        val cSizeL = combSizesL16!!
        val numCombs = cbL.size; val numAllpass = apL.size
        val fb = MAX_FEEDBACK * inten.toDouble(); val wet = WET_MAX * inten.toDouble()
        val dry = dryGain(inten)
        val damp = DAMPING.toDouble(); val apCoeff = ALLPASS_COEFF.toDouble()
        val combScale = 1.0 / numCombs

        repeat(inputBuffer.remaining() / 4) {
            val lIn = inputBuffer.short.toDouble(); val rIn = inputBuffer.short.toDouble()
            var acc = 0.0
            for (i in 0 until numCombs) {
                val pos = cpL[i]; val buf = cbL[i]; val delayOut = buf[pos].toDouble()
                val filtered = delayOut * damp + cfL[i] * (1.0 - damp)
                buf[pos] = (lIn + filtered * fb).coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble()).toInt().toShort()
                cfL[i] = filtered; acc += delayOut; cpL[i] = (pos + 1) % cSizeL[i]
            }
            acc *= combScale
            for (i in 0 until numAllpass) {
                val pos = apPL[i]; val buf = apL[i]; val bufOut = buf[pos].toDouble()
                buf[pos] = (acc + apCoeff * bufOut).coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble()).toInt().toShort()
                acc = bufOut - apCoeff * acc; apPL[i] = (pos + 1) % buf.size
            }
            val outL = limitSample((dry * lIn + wet * acc) / Short.MAX_VALUE) * Short.MAX_VALUE

            var accR = 0.0
            for (i in 0 until numCombs) {
                val pos = cpR[i]; val buf = cbR[i]; val delayOut = buf[pos].toDouble()
                val filtered = delayOut * damp + cfR[i] * (1.0 - damp)
                buf[pos] = (rIn + filtered * fb).coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble()).toInt().toShort()
                cfR[i] = filtered; accR += delayOut; cpR[i] = (pos + 1) % buf.size
            }
            accR *= combScale
            for (i in 0 until numAllpass) {
                val pos = apPR[i]; val buf = apR[i]; val bufOut = buf[pos].toDouble()
                buf[pos] = (accR + apCoeff * bufOut).coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble()).toInt().toShort()
                accR = bufOut - apCoeff * accR; apPR[i] = (pos + 1) % buf.size
            }
            val outR = limitSample((dry * rIn + wet * accR) / Short.MAX_VALUE) * Short.MAX_VALUE
            output.putShort(outL.coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble()).toInt().toShort())
            output.putShort(outR.coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble()).toInt().toShort())
        }
    }

    private fun ensureFloatState(sr: Int) {
        if (sampleRate == sr && combL != null) return
        sampleRate = sr
        combSizesL = IntArray(COMB_DELAYS_L.size) { scaledDelay(COMB_DELAYS_L[it], sr) }
        val cSizeR = IntArray(COMB_DELAYS_R.size) { scaledDelay(COMB_DELAYS_R[it], sr) }
        allpassSizesL = IntArray(ALLPASS_DELAYS_L.size) { scaledDelay(ALLPASS_DELAYS_L[it], sr) }
        val aSizeR = IntArray(ALLPASS_DELAYS_R.size) { scaledDelay(ALLPASS_DELAYS_R[it], sr) }
        combL = Array(combSizesL!!.size) { FloatArray(combSizesL!![it]) }
        combR = Array(cSizeR.size) { FloatArray(cSizeR[it]) }
        combPosL = IntArray(combL!!.size); combPosR = IntArray(combR!!.size)
        combFilterL = DoubleArray(combL!!.size); combFilterR = DoubleArray(combR!!.size)
        allpassL = Array(allpassSizesL!!.size) { FloatArray(allpassSizesL!![it]) }
        allpassR = Array(aSizeR.size) { FloatArray(aSizeR[it]) }
        allpassPosL = IntArray(allpassL!!.size); allpassPosR = IntArray(allpassR!!.size)
    }

    private fun ensureShortState(sr: Int) {
        if (sampleRate == sr && combL16 != null) return
        sampleRate = sr
        combSizesL16 = IntArray(COMB_DELAYS_L.size) { scaledDelay(COMB_DELAYS_L[it], sr) }
        val cSizeR = IntArray(COMB_DELAYS_R.size) { scaledDelay(COMB_DELAYS_R[it], sr) }
        allpassSizesL16 = IntArray(ALLPASS_DELAYS_L.size) { scaledDelay(ALLPASS_DELAYS_L[it], sr) }
        val aSizeR = IntArray(ALLPASS_DELAYS_R.size) { scaledDelay(ALLPASS_DELAYS_R[it], sr) }
        combL16 = Array(combSizesL16!!.size) { ShortArray(combSizesL16!![it]) }
        combR16 = Array(cSizeR.size) { ShortArray(cSizeR[it]) }
        combPosL16 = IntArray(combL16!!.size); combPosR16 = IntArray(combR16!!.size)
        combFilterL16 = DoubleArray(combL16!!.size); combFilterR16 = DoubleArray(combR16!!.size)
        allpassL16 = Array(allpassSizesL16!!.size) { ShortArray(allpassSizesL16!![it]) }
        allpassR16 = Array(aSizeR.size) { ShortArray(aSizeR.size) { 0 }.toShortArray() }
        allpassPosL16 = IntArray(allpassL16!!.size); allpassPosR16 = IntArray(allpassR16!!.size)
    }

    private fun clearState() {
        sampleRate = -1
        combL = null; combR = null; combPosL = null; combPosR = null
        combFilterL = null; combFilterR = null; allpassL = null; allpassR = null
        allpassPosL = null; allpassPosR = null; combSizesL = null; allpassSizesL = null
        combL16 = null; combR16 = null; combPosL16 = null; combPosR16 = null
        combFilterL16 = null; combFilterR16 = null; allpassL16 = null; allpassR16 = null
        allpassPosL16 = null; allpassPosR16 = null; combSizesL16 = null; allpassSizesL16 = null
    }
}
