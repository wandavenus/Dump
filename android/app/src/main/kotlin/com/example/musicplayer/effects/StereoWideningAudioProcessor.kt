package com.example.musicplayer.effects

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer

/**
 * Custom AudioProcessor implementing stereo widening via a 2×2 mixing matrix.
 *
 * Preferred over ChannelMixingAudioProcessor (moved to androidx.media3.common.audio in 1.10.1)
 * because ChannelMixingAudioProcessor only handles PCM-16 and throws UnhandledAudioFormatException
 * for other formats, while this processor gracefully returns NOT_SET (bypass) for unsupported
 * formats and also handles PCM-float (used when DefaultRenderersFactory float output is enabled).
 *
 * Matrix math (identical to the original ChannelMixingAudioProcessor approach):
 *   w      = 1.0 + strength × 0.5          (maps [0, 1] → [1.0, 1.5])
 *   diag   = (1 + w) / 2
 *   cross  = (1 − w) / 2
 *   L_out  = diag × L_in + cross × R_in
 *   R_out  = cross × L_in + diag × R_in
 *
 *   strength = 0.0 → identity (diag=1, cross=0, transparent)
 *   strength = 1.0 → diag=1.25, cross=−0.25 (25 % separation increase)
 *
 * Thread safety: [setMatrix] is called from the main thread; [queueInput] is called from
 * ExoPlayer's audio rendering thread.  The two volatile fields provide visibility without
 * requiring a lock — a torn read is harmless (results in one slightly-off frame).
 */
@UnstableApi
class StereoWideningAudioProcessor : BaseAudioProcessor() {

    @Volatile private var diag:  Float = 1f
    @Volatile private var cross: Float = 0f

    fun setMatrix(enabled: Boolean, strength: Float) {
        if (!enabled) {
            diag  = 1f
            cross = 0f
        } else {
            val w = 1f + strength.coerceIn(0f, 1f) * 0.5f
            diag  = (1f + w) / 2f
            cross = (1f - w) / 2f
        }
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val supported = inputAudioFormat.channelCount == 2 && (
            inputAudioFormat.encoding == C.ENCODING_PCM_16BIT ||
            inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
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
