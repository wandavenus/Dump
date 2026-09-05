package dev.wndavenz.music.effects

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

private const val LOG_TAG = "EightDProc"

/**
 * Custom AudioProcessor implementing the "8D audio" rotating effect.
 *
 * The effect is a slow, continuous rotation of the stereo image around the
 * listener's head, created by combining two classic cues:
 *
 *  1. HAAS-EFFECT DELAY MODULATION — each channel feeds a short fractional
 *     delay line whose delay time is swept in counter-phase by a slow LFO
 *     (left and right delay times oscillate in opposite directions). The ear
 *     localises the source toward whichever channel arrives first, so the
 *     perceived position glides smoothly around the head.
 *
 *  2. CONSTANT-POWER PAN MODULATION — the same LFO drives an equal-power
 *     (sin/cos) pan that follows the delay sweep, reinforcing the rotation.
 *     The pan gains are normalised so the louder channel always peaks at 1.0,
 *     keeping the overall loudness roughly constant during the cycle.
 *
 *  LFO: fixed at 0.09 Hz (one full rotation ≈ 11.1 s), a gentle, hypnotic
 *  speed typical of 8D renders.
 *
 *  [intensity] ∈ [0, 1] scales BOTH the delay sweep depth (0 → 20 ms) and the
 *  pan excursion. intensity = 0 is a perfect identity (no delay, no pan, no
 *  gain change) — this is what makes the settings slider behave like an
 *  off/on control at its zero position.
 *
 * Thread safety: [setParams] is called from the main thread; [queueInput] runs
 * on ExoPlayer's audio rendering thread. The two volatile fields give
 * visibility without a lock; a torn read is harmless (one slightly-off frame).
 * All DSP state (phase, delay buffers) is owned exclusively by the audio
 * thread, so no synchronisation is needed there.
 *
 * MONO / multi-channel / other encodings: [onConfigure] returns NOT_SET
 * (transparent bypass), matching [StereoWideningAudioProcessor].
 */
@UnstableApi
class EightDAudioProcessor : BaseAudioProcessor() {

    companion object {
        /** LFO rotation speed in Hz — one full circle ≈ 11.1 seconds. */
        private const val LFO_FREQ_HZ = 0.09f

        /** Maximum per-channel delay sweep in seconds (Haas range). */
        private const val MAX_DELAY_SEC = 0.020f
    }

    @Volatile private var intensity: Float = 0f

    // ── Per-format DSP state (audio thread only) ────────────────────────────
    private var sampleRate = -1
    private var phase = 0.0
    private var delayL: FloatArray? = null   // circular delay lines (float path)
    private var delayR: FloatArray? = null
    private var delayL16: ShortArray? = null // circular delay lines (PCM-16 path)
    private var delayR16: ShortArray? = null
    private var writeIdx = 0

    fun setParams(enabled: Boolean, intensity: Float) {
        this.intensity = if (enabled) intensity.coerceIn(0f, 1f) else 0f
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

    private fun processFloat(inputBuffer: ByteBuffer, output: ByteBuffer, inten: Float) {
        val sr = inputAudioFormat.sampleRate
        ensureFloatState(sr)
        val bufL = delayL!!
        val bufR = delayR!!
        val cap = bufL.size
        val maxDelayFrames = (MAX_DELAY_SEC * sr).toInt().coerceAtLeast(1)
        val step = 2.0 * PI * LFO_FREQ_HZ / sr

        val frameCount = inputBuffer.remaining() / 8
        repeat(frameCount) {
            val l = inputBuffer.float.toDouble()
            val r = inputBuffer.float.toDouble()

            val sinP = sin(phase)
            // Counter-phase delay sweep in samples (fractional).
            val dL = maxDelayFrames * inten * (0.5 + 0.5 * sinP)
            val dR = maxDelayFrames * inten * (0.5 - 0.5 * sinP)

            val outL = delayRead(bufL, cap, writeIdx, dL) * panGain(+sinP, inten)
            val outR = delayRead(bufR, cap, writeIdx, dR) * panGain(-sinP, inten)

            bufL[writeIdx] = l.toFloat()
            bufR[writeIdx] = r.toFloat()
            writeIdx = (writeIdx + 1) % cap
            phase += step

            output.putFloat(outL.toFloat())
            output.putFloat(outR.toFloat())
        }
    }

    // ── PCM-16 path (defensive; the chain forces float in practice) ────────

    private fun processPcm16(inputBuffer: ByteBuffer, output: ByteBuffer, inten: Float) {
        val sr = inputAudioFormat.sampleRate
        ensureShortState(sr)
        val bufL = delayL16!!
        val bufR = delayR16!!
        val cap = bufL.size
        val maxDelayFrames = (MAX_DELAY_SEC * sr).toInt().coerceAtLeast(1)
        val step = 2.0 * PI * LFO_FREQ_HZ / sr

        val frameCount = inputBuffer.remaining() / 4
        repeat(frameCount) {
            val l = inputBuffer.short.toDouble()
            val r = inputBuffer.short.toDouble()

            val sinP = sin(phase)
            val dL = maxDelayFrames * inten * (0.5 + 0.5 * sinP)
            val dR = maxDelayFrames * inten * (0.5 - 0.5 * sinP)

            val outL = delayRead16(bufL, cap, writeIdx, dL) * panGain(+sinP, inten)
            val outR = delayRead16(bufR, cap, writeIdx, dR) * panGain(-sinP, inten)

            bufL[writeIdx] = l.toInt().toShort()
            bufR[writeIdx] = r.toInt().toShort()
            writeIdx = (writeIdx + 1) % cap
            phase += step

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

    // ── Fractional delay line helpers ───────────────────────────────────────

    /** Read a fractional-delay tap with linear interpolation. */
    private fun delayRead(buf: FloatArray, cap: Int, write: Int, delayFrames: Double): Double {
        val d = min(delayFrames, (cap - 1).toDouble())
        val base = write - d
        val i0 = ((Math.floor(base).toInt() % cap) + cap) % cap
        val i1 = (i0 + 1) % cap
        val frac = base - Math.floor(base)
        return buf[i0] * (1.0 - frac) + buf[i1] * frac
    }

    private fun delayRead16(buf: ShortArray, cap: Int, write: Int, delayFrames: Double): Double {
        val d = min(delayFrames, (cap - 1).toDouble())
        val base = write - d
        val i0 = ((Math.floor(base).toInt() % cap) + cap) % cap
        val i1 = (i0 + 1) % cap
        val frac = base - Math.floor(base)
        return buf[i0] * (1.0 - frac) + buf[i1] * frac
    }

    /**
     * Constant-power pan for LFO phase value [sinP]. Normalised so the louder
     * channel reaches 1.0 (never amplifies, never fully mutes unless the LFO
     * is at its extreme AND intensity = 1).
     */
    private fun panGain(sinP: Double, inten: Float): Double {
        val p = sinP * inten
        val gL = sqrt(0.5 * (1.0 + p))
        val gR = sqrt(0.5 * (1.0 - p))
        val norm = 1.0 / max(gL, gR)
        return if (p >= 0) gL * norm else gR * norm
    }

    // ── State (re)allocation on format change ───────────────────────────────

    private fun ensureFloatState(sr: Int) {
        if (sampleRate == sr && delayL != null) return
        sampleRate = sr
        phase = 0.0
        writeIdx = 0
        val cap = ((MAX_DELAY_SEC * sr) + 2).toInt().coerceAtLeast(64)
        delayL = FloatArray(cap)
        delayR = FloatArray(cap)
    }

    private fun ensureShortState(sr: Int) {
        if (sampleRate == sr && delayL16 != null) return
        sampleRate = sr
        phase = 0.0
        writeIdx = 0
        val cap = ((MAX_DELAY_SEC * sr) + 2).toInt().coerceAtLeast(64)
        delayL16 = ShortArray(cap)
        delayR16 = ShortArray(cap)
    }
}