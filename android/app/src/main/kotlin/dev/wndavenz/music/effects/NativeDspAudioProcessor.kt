package dev.wndavenz.music.effects

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer

/**
 * AudioProcessor that routes PCM through the native DSP pipeline
 * (libnative_audio_runtime.so — the same .so loaded by Dart FFI).
 *
 * Phase 4.5 insertion point:
 *   ExoPlayer PCM → NativeDspAudioProcessor → StereoWideningAudioProcessor
 *                                           → SilenceSkipping → Sonic → AudioTrack
 *
 * ── PCM ownership model ──────────────────────────────────────────────────────
 *
 *  1. ExoPlayer calls queueInput() with a ByteBuffer slice of its decoded PCM.
 *  2. We copy the PCM into an output buffer via replaceOutputBuffer() (one
 *     bulk native memcpy — required by BaseAudioProcessor's contract: we must
 *     not modify the caller's inputBuffer).
 *  3. We call nativeProcessFloat() in-place on the output buffer. This is
 *     zero-copy after the initial bulk copy: GetDirectBufferAddress() gives the
 *     C side a raw float* into the direct ByteBuffer's native heap without any
 *     further allocation or copy.
 *  4. The processed buffer is returned by BaseAudioProcessor.getOutput().
 *
 * ── Thread safety ────────────────────────────────────────────────────────────
 *
 *  queueInput() / getOutput() run on ExoPlayer's audio rendering thread.
 *  nar_dsp_pipeline_process_raw() acquires no locks and makes no heap
 *  allocations. Gain/bypass/enable parameters written from Dart (UI thread) use
 *  C11 atomic stores — the audio thread reads them with atomic loads. Safe.
 *
 * ── Activation ───────────────────────────────────────────────────────────────
 *
 *  Active only for ENCODING_PCM_FLOAT (float32 interleaved).
 *  DefaultRenderersFactory.setEnableAudioFloatOutput(true) (already set in
 *  Media3PlaybackService) enables float output from the decoder pipeline.
 *
 *  If libnative_audio_runtime.so is unavailable (e.g. simulator) or the native
 *  pipeline has not yet been initialised by Dart, audio is passed through
 *  unmodified (fail-open). In the latter case nar_dsp_pipeline_process_raw()
 *  returns NATIVE_RUNTIME_ERROR_NOT_INITIALIZED without touching the buffer.
 *
 * ── Per-player instances ─────────────────────────────────────────────────────
 *
 *  One NativeDspAudioProcessor is created per ExoPlayer instance (matching the
 *  StereoWideningAudioProcessor pattern). BaseAudioProcessor is stateful, so
 *  instances must not be shared. All instances call into the same global C
 *  pipeline state — shared, user-configured PARAMETERS (gain/bypass/enable/
 *  thresholds/ratios/etc.) apply uniformly to both primary and secondary
 *  (crossfade) players, which is the intended behaviour.
 *
 *  Production-hardening pass: each instance now also carries its own
 *  immutable [streamSlot] (0 = primary, 1 = secondary/crossfade-standby),
 *  threaded into every native call. This tells the native pipeline WHICH
 *  concurrently-playing stream a buffer belongs to, so per-stream RUNTIME
 *  state (envelope followers, look-ahead delay buffers, filter histories)
 *  inside comp/limiter/peq/crossfeed/loudness stays isolated between the two
 *  players — see dsp_stream.h for the full rationale. Before this, both
 *  ExoPlayer audio threads wrote the same unsynchronized global state during
 *  crossfade, a genuine data race.
 */
@UnstableApi
class NativeDspAudioProcessor(
    private val streamSlot: Int = 0,
) : BaseAudioProcessor() {

    companion object {
        private const val LOG_TAG = "NativeDspAudioProc"

        /**
         * Process [frameCount] × [channelCount] float32 samples in [buffer]
         * in-place, for the given [streamSlot] (see dsp_stream.h).
         *
         * [buffer] must be a direct ByteBuffer with position 0 pointing at the
         * first PCM sample. Returns NATIVE_RUNTIME_OK (0) on success.
         *
         * Called exclusively on ExoPlayer's audio rendering thread.
         */
        @JvmStatic
        private external fun nativeProcessFloat(
            buffer: ByteBuffer,
            frameCount: Int,
            channelCount: Int,
            sampleRate: Int,
            streamSlot: Int,
        ): Int

        /**
         * Returns true if the native DSP pipeline has been initialised by Dart
         * (i.e. nar_dsp_pipeline_init() has completed successfully).
         * Backed by a C atomic load — safe from any thread.
         */
        @JvmStatic
        private external fun nativeIsInitialized(): Boolean

        /**
         * Whether libnative_audio_runtime.so was successfully loaded.
         * Evaluated once at class initialisation; never changes afterwards.
         */
        val isLibraryAvailable: Boolean = runCatching {
            System.loadLibrary("native_audio_runtime")
            true
        }.getOrElse { e ->
            Log.w(LOG_TAG, "native_audio_runtime unavailable — DSP bypassed: $e")
            false
        }
    }

    // ── BaseAudioProcessor overrides ─────────────────────────────────────────

    /**
     * Activate for float32 input only.
     *
     * PCM_16BIT is not supported in Phase 4.5 — the C pipeline operates on
     * float32. PCM_16BIT inputs pass through this processor unchanged (NOT_SET
     * makes it inactive for that format, so ExoPlayer skips it entirely).
     */
    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat =
        if (isLibraryAvailable && inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT)
            inputAudioFormat  // same format in/out; gain is transparent w.r.t. sample type
        else
            AudioProcessor.AudioFormat.NOT_SET

    /**
     * Bulk-copy PCM into an owned output buffer, then process in-place via JNI.
     *
     * Design rationale for the copy-then-in-place strategy:
     *   a) BaseAudioProcessor requires output via replaceOutputBuffer(), not
     *      modification of inputBuffer.
     *   b) After replaceOutputBuffer() + put(), the output buffer is a direct
     *      ByteBuffer on the native heap. nativeProcessFloat() uses
     *      JNI GetDirectBufferAddress() to obtain a raw float* — no further
     *      copy or allocation occurs. This meets the "zero unnecessary
     *      allocations" requirement for the hot processing path.
     */
    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining == 0) return

        // Allocate or reuse the output buffer (managed by BaseAudioProcessor).
        val output = replaceOutputBuffer(remaining)

        // One bulk copy: input → output (equivalent to a native memcpy).
        output.put(inputBuffer)
        output.flip()  // position=0, limit=remaining — ready for JNI and getOutput()

        if (!isLibraryAvailable) return

        // Process in-place. Non-OK return (e.g. NOT_INITIALIZED on startup
        // race) leaves the output buffer unmodified — correct fail-open behaviour.
        val channelCount = inputAudioFormat.channelCount
        val sampleRate   = inputAudioFormat.sampleRate
        // frameCount = total_bytes / (channelCount × sizeof(float32))
        val frameCount   = remaining / (channelCount * 4)

        nativeProcessFloat(output, frameCount, channelCount, sampleRate, streamSlot)
        // output.position/limit unchanged by JNI — BaseAudioProcessor.getOutput() is correct.
    }
}
