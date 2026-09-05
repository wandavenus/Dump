package dev.wndavenz.music.effects

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer

private const val LOG_TAG = "StereoWideningProc"

/**
 * Custom AudioProcessor implementing stereo widening via a 2×2 mixing matrix.
 *
 * The widening curve remains unchanged, with constant headroom compensation
 * while the effect is active so the matrix cannot add unnecessary peak level.
 */
@UnstableApi
class StereoWideningAudioProcessor : BaseAudioProcessor() {

    companion object {
        /** Peak headroom reserved for the widening matrix. */
        private const val HEADROOM = 0.80f
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
                val l = inputBuffer.float
                val r = inputBuffer.float
                output.putFloat(d * l + c * r)
                output.putFloat(c * l + d * r)
            }
        } else {
            val frameCount = remaining / 4
            repeat(frameCount) {
                val l = inputBuffer.short.toFloat()
                val r = inputBuffer.short.toFloat()
                val lOut = (d * l + c * r).toInt()
                    .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                val rOut = (c * l + d * r).toInt()
                    .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                output.putShort(lOut)
                output.putShort(rOut)
            }
        }

        while (inputBuffer.hasRemaining()) output.put(inputBuffer.get())
        output.flip()
    }
}
