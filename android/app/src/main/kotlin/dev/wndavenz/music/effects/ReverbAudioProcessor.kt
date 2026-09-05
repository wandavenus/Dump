package dev.wndavenz.music.effects

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.tanh

private const val LOG_TAG = "ReverbProc"

/** Software Schroeder-style reverb with float internal state and smooth peak control. */
@UnstableApi
class ReverbAudioProcessor : BaseAudioProcessor() {
    companion object {
        private val COMB_DELAYS_L = intArrayOf(1116, 1188, 1277, 1356)
        private val COMB_DELAYS_R = intArrayOf(1139, 1211, 1300, 1379)
        private val ALLPASS_DELAYS_L = intArrayOf(556, 441)
        private val ALLPASS_DELAYS_R = intArrayOf(579, 464)
        private const val MAX_FEEDBACK = 0.82f
        private const val DAMPING = 0.4f
        private const val ALLPASS_COEFF = 0.5f
        private const val WET_MAX = 0.55f
        private const val DRY_MIN = 0.70f
        private const val REF_SAMPLE_RATE = 44100
        private const val OUTPUT_CEILING = 0.98
        private const val LIMIT_CEILING = 0.98
        private const val LIMIT_RANGE = 0.02
        private const val GAIN_ATTACK = 0.15
        private const val GAIN_RELEASE = 0.005

        private fun limitSample(x: Double): Double {
            val ax = abs(x)
            if (!ax.isFinite()) return 0.0
            if (ax <= LIMIT_CEILING) return x
            val compressed = LIMIT_CEILING + LIMIT_RANGE * tanh((ax - LIMIT_CEILING) / LIMIT_RANGE)
            return if (x < 0.0) -compressed else compressed
        }
    }

    @Volatile private var intensity = 0f
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
    private var outputGain = 1.0

    fun setParams(enabled: Boolean, intensity: Float) {
        this.intensity = if (enabled && intensity.isFinite()) intensity.coerceIn(0f, 1f) else 0f
    }

    override fun onFlush() = clearState()
    override fun onReset() = clearState()

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val supported = inputAudioFormat.channelCount == 2 &&
            (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT || inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT)
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
        val sampleCount = if (inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT) remaining / 8 else remaining / 4
        val frames = sampleCount
        val values = DoubleArray(frames * 2)
        if (inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT) {
            repeat(frames * 2) { values[it] = inputBuffer.float.toDouble() }
        } else {
            repeat(frames * 2) { values[it] = inputBuffer.short.toDouble() / Short.MAX_VALUE }
        }
        processNormalized(values, inten, inputAudioFormat.sampleRate)
        if (inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT) {
            repeat(values.size) { output.putFloat(values[it].toFloat()) }
        } else {
            repeat(values.size) {
                val pcm = (values[it] * Short.MAX_VALUE).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                output.putShort(pcm.toShort())
            }
        }
        output.flip()
    }

    private fun scaledDelay(refSamples: Int, sr: Int): Int =
        (refSamples.toLong() * sr / REF_SAMPLE_RATE).toInt().coerceAtLeast(1) + 1

    private fun dryGain(inten: Float): Double = 1.0 - (1.0 - DRY_MIN) * inten

    private fun processNormalized(samples: DoubleArray, inten: Float, sr: Int) {
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
        val fb = MAX_FEEDBACK * inten.toDouble()
        val wet = WET_MAX * inten.toDouble()
        val dry = dryGain(inten)
        val damp = DAMPING.toDouble()
        val apCoeff = ALLPASS_COEFF.toDouble()
        val combScale = 1.0 / numCombs

        var peak = 0.0
        var frame = 0
        while (frame < samples.size) {
            val lIn = samples[frame]
            val rIn = samples[frame + 1]
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

            val mixedL = dry * lIn + wet * acc
            val mixedR = dry * rIn + wet * accR
            samples[frame] = mixedL
            samples[frame + 1] = mixedR
            peak = max(peak, max(abs(mixedL), abs(mixedR)))
            frame += 2
        }

        // Use a slow envelope follower for both attack and recovery. This avoids
        // block-to-block gain jumps that can make the reverb tail sound like it
        // is breathing, while still pulling gain down quickly when a peak grows.
        val targetGain = if (peak > OUTPUT_CEILING && peak.isFinite()) OUTPUT_CEILING / peak else 1.0
        outputGain = if (targetGain < outputGain) {
            outputGain + (targetGain - outputGain) * GAIN_ATTACK
        } else {
            outputGain + (targetGain - outputGain) * GAIN_RELEASE
        }
        outputGain = outputGain.coerceIn(0.0, 1.0)

        frame = 0
        while (frame < samples.size) {
            samples[frame] = limitSample(samples[frame] * outputGain)
            samples[frame + 1] = limitSample(samples[frame + 1] * outputGain)
            frame += 2
        }
    }

    private fun ensureFloatState(sr: Int) {
        if (sampleRate == sr && combL != null) return
        sampleRate = sr
        combSizesL = IntArray(COMB_DELAYS_L.size) { scaledDelay(COMB_DELAYS_L[it], sr) }
        val cSizeR = IntArray(COMB_DELAYS_R.size) { scaledDelay(COMB_DELAYS_R[it], sr) }
        val aSizeL = IntArray(ALLPASS_DELAYS_L.size) { scaledDelay(ALLPASS_DELAYS_L[it], sr) }
        val aSizeR = IntArray(ALLPASS_DELAYS_R.size) { scaledDelay(ALLPASS_DELAYS_R[it], sr) }
        combL = Array(combSizesL!!.size) { FloatArray(combSizesL!![it]) }
        combR = Array(cSizeR.size) { FloatArray(cSizeR[it]) }
        combPosL = IntArray(combL!!.size)
        combPosR = IntArray(combR!!.size)
        combFilterL = DoubleArray(combL!!.size)
        combFilterR = DoubleArray(combR!!.size)
        allpassL = Array(aSizeL.size) { FloatArray(aSizeL[it]) }
        allpassR = Array(aSizeR.size) { FloatArray(aSizeR[it]) }
        allpassPosL = IntArray(allpassL!!.size)
        allpassPosR = IntArray(allpassR!!.size)
        outputGain = 1.0
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
        outputGain = 1.0
    }
}
