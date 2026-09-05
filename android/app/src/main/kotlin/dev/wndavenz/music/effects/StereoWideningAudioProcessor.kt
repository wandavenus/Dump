package dev.wndavenz.music.effects

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import kotlin.math.abs
import kotlin.math.tanh

private const val LOG_TAG = "StereoWideningProc"

/**
 * Custom AudioProcessor implementing stereo widening via a 2×2 mixing matrix.
 *
 * The matrix is peak-safe for float and PCM16 paths. Active widening reserves
 * headroom and applies a final soft limiter so correlated/full-scale material
 * cannot clip when this processor follows another DSP stage.
 */
@UnstableApi
class StereoWideningAudioProcessor : BaseAudioProcessor() {

    companion object {
        private const val HEADROOM = 0.80f
        private const val LIMIT_CEILING = 0.94
        private const val LIMIT_RANGE = 0.06

        private fun limitSample(x: Double): Double {
            val ax = abs(x)
            if (!ax.isFinite()) return 0.0
            if (ax <= LIMIT_CEILING) return x
            val compressed = LIMIT_CEILING + LIMIT_RANGE * tanh((ax - LIMIT_CEILING) / LIMIT_RANGE)
            return if (x < 0.0) -compressed else compressed
        }
    }

    @Volatile private var diag: Float = 1f
    @Volatile private var cross: Float = 0f

    fun setMatrix(enabled: Boolean, strength: Float) {
        val s = if (strength.isFinite()) strength.coerceIn(0f, 1f) else 0f
        if (!enabled || s <= 0f) {
            diag = 1f
            cross = 0f
        } else {
            val w = 1f + s * 0.5f
            diag = ((1f + w) / 2f) * HEADROOM
            cross = ((1f - w) / 2f) * HEADROOM
        }
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val supported = inputAudioFormat.channelCount == 2 && (
            inputAudioFormat.encoding == C.ENCODING_PCM_16BIT ||
            inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        )
        Log.i(
            LOG_TAG,
            "onConfigure encoding=${inputAudioFormat.encoding} (PCM_FLOAT=${C.ENCODING_PCM_FLOAT}) " +
                "channels=${inputAudioFormat.channelCount} supported=$supported",
        )
        return if (supported) inputAudioFormat else AudioProcessor.AudioFormat.NOT_SET
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining == 0) return

        val d = diag
        val c = cross
        val output = replaceOutputBuffer(remaining)

        if (inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT) {
            val frameCount = remaining / 8
            repeat(frameCount) {
                val l = inputBuffer.float.toDouble()
                val r = inputBuffer.float.toDouble()
                val lOut = limitSample(d * l + c * r)
                val rOut = limitSample(c * l + d * r)
                output.putFloat(lOut.toFloat())
                output.putFloat(rOut.toFloat())
            }
        } else {
            val frameCount = remaining / 4
            repeat(frameCount) {
                val l = inputBuffer.short.toDouble()
                val r = inputBuffer.short.toDouble()
                val lOut = (limitSample((d * l + c * r) / Short.MAX_VALUE) * Short.MAX_VALUE)
                    .toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                val rOut = (limitSample((c * l + d * r) / Short.MAX_VALUE) * Short.MAX_VALUE)
                    .toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                output.putShort(lOut)
                output.putShort(rOut)
            }
        }

        while (inputBuffer.hasRemaining()) output.put(inputBuffer.get())
        output.flip()
    }
}
