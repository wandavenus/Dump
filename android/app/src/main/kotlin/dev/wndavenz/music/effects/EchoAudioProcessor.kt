package dev.wndavenz.music.effects

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer

private const val LOG_TAG = "EchoProc"

/**
 * Custom AudioProcessor implementing an "echo / gema" (feedback-delay) effect.
 *
 * Replaces the previous 8D rotation with a warm, decaying echo: a short
 * feedback delay line with a one-pole low-pass in the feedback path, so each
 * repeat is softer and darker — the classic "menggema" tail rather than a
 * hard, metallic repetition.
 *
 *  - DELAY: fixed at [ECHO_DELAY_SEC] (≈ 250 ms), same for both channels so the
 *    stereo image stays intact.
 *  - FEEDBACK: intensity × [MAX_FEEDBACK] (max ≈ 0.65, always < 1 → stable).
 *  - WET MIX: intensity × [WET_MAX]; the dry signal always passes at unity.
 *  - LOW-PASS: one-pole smoothing (alpha = [LOW_PASS_ALPHA]) on the feedback
 *    signal, so the tail decays in brightness and blends naturally.
 *
 *  [intensity] ∈ [0, 1] scales BOTH the feedback depth and the wet mix.
 *  intensity = 0 is a perfect identity (no feedback, no wet, no gain change) —
 *  this is what makes the settings slider behave like an off/on control at its
 *  zero position.
 *
 * Thread safety: same contract as the former 8D processor — [setParams] runs on
 * the main thread; [queueInput] runs on ExoPlayer's audio rendering thread. The
 * intensity field is volatile; all DSP state (buffers, indices, filter state)
 * is owned exclusively by the audio thread, so no synchronisation is needed.
 *
 * MONO / multi-channel / other encodings: [onConfigure] returns NOT_SET
 * (transparent bypass), matching the former 8D processor.
 */
@UnstableApi
class EchoAudioProcessor : BaseAudioProcessor() {

    companion object {
        /** Echo delay time in seconds (≈ 250 ms) — identical for both channels. */
        private const val ECHO_DELAY_SEC = 0.25f

        /** Max feedback gain applied at full intensity (always < 1 → stable). */
        private const val MAX_FEEDBACK = 0.65f

        /** Max wet mix at full intensity; the dry signal always passes at unity. */
        private const val WET_MAX = 0.8f

        /** One-pole low-pass coefficient on the feedback path (darker tail). */
        private const val LOW_PASS_ALPHA = 0.35f
    }

    @Volatile private var intensity: Float = 0f

    // ── Per-format DSP state (audio thread only) ────────────────────────────
    private var sampleRate = -1
    private var maxDelayFrames = 1
    private var delayL: FloatArray? = null   // circular feedback delay lines (float path)
    private var delayR: FloatArray? = null
    private var delayL16: ShortArray? = null // circular feedback delay lines (PCM-16 path)
    private var delayR16: ShortArray? = null
    private var writeIdx = 0   // write position
    private var readIdx = 0    // read position (= write − maxDelayFrames)
    private var lpL = 0.0      // low-pass state (float path)
    private var lpR = 0.0
    private var lpL16 = 0.0    // low-pass state (PCM-16 path)
    private var lpR16 = 0.0

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
        val delayFrames = maxDelayFrames
        val fb = MAX_FEEDBACK * inten
        val wet = WET_MAX * inten
        val alpha = LOW_PASS_ALPHA

        var rIdx = readIdx
        var wIdx = writeIdx
        var lL = lpL
        var lR = lpR

        val frameCount = inputBuffer.remaining() / 8
        repeat(frameCount) {
            val l = inputBuffer.float.toDouble()
            val r = inputBuffer.float.toDouble()

            val delL = bufL[rIdx]
            val delR = bufR[rIdx]

            // One-pole low-pass on the feedback tap → warmer, decaying tail.
            val fL = lL + alpha * (delL - lL)
            val fR = lR + alpha * (delR - lR)

            bufL[wIdx] = (l + fb * fL).toFloat()
            bufR[wIdx] = (r + fb * fR).toFloat()

            val outL = l + wet * delL
            val outR = r + wet * delR

            rIdx = (rIdx + 1) % cap
            wIdx = (wIdx + 1) % cap
            lL = fL
            lR = fR

            output.putFloat(outL.toFloat())
            output.putFloat(outR.toFloat())
        }
        readIdx = rIdx
        writeIdx = wIdx
        lpL = lL
        lpR = lR
    }

    // ── PCM-16 path (defensive; the chain forces float in practice) ────────

    private fun processPcm16(inputBuffer: ByteBuffer, output: ByteBuffer, inten: Float) {
        val sr = inputAudioFormat.sampleRate
        ensureShortState(sr)
        val bufL = delayL16!!
        val bufR = delayR16!!
        val cap = bufL.size
        val delayFrames = maxDelayFrames
        val fb = MAX_FEEDBACK * inten
        val wet = WET_MAX * inten
        val alpha = LOW_PASS_ALPHA

        var rIdx = readIdx
        var wIdx = writeIdx
        var lL = lpL16
        var lR = lpR16

        val frameCount = inputBuffer.remaining() / 4
        repeat(frameCount) {
            val l = inputBuffer.short.toDouble()
            val r = inputBuffer.short.toDouble()

            val delL = bufL[rIdx]
            val delR = bufR[rIdx]

            val fL = lL + alpha * (delL - lL)
            val fR = lR + alpha * (delR - lR)

            bufL[wIdx] = (l + fb * fL)
                .coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble())
                .toInt().toShort()
            bufR[wIdx] = (r + fb * fR)
                .coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble())
                .toInt().toShort()

            val outL = l + wet * delL
            val outR = r + wet * delR

            rIdx = (rIdx + 1) % cap
            wIdx = (wIdx + 1) % cap
            lL = fL
            lR = fR

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
        readIdx = rIdx
        writeIdx = wIdx
        lpL16 = lL
        lpR16 = lR
    }

    // ── State (re)allocation on format change ───────────────────────────────

    private fun ensureFloatState(sr: Int) {
        if (sampleRate == sr && delayL != null) return
        sampleRate = sr
        maxDelayFrames = (ECHO_DELAY_SEC * sr).toInt().coerceAtLeast(1)
        // Buffer holds exactly `maxDelayFrames` samples of history, with one
        // free slot so the read index always lags write by the echo delay.
        val cap = maxDelayFrames + 1
        delayL = FloatArray(cap)
        delayR = FloatArray(cap)
        writeIdx = maxDelayFrames
        readIdx = 0
        lpL = 0.0
        lpR = 0.0
    }

    private fun ensureShortState(sr: Int) {
        if (sampleRate == sr && delayL16 != null) return
        sampleRate = sr
        maxDelayFrames = (ECHO_DELAY_SEC * sr).toInt().coerceAtLeast(1)
        val cap = maxDelayFrames + 1
        delayL16 = ShortArray(cap)
        delayR16 = ShortArray(cap)
        writeIdx = maxDelayFrames
        readIdx = 0
        lpL16 = 0.0
        lpR16 = 0.0
    }
}