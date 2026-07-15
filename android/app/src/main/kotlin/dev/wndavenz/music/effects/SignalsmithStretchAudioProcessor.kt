package dev.wndavenz.music.effects

import android.os.SystemClock
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import dev.wndavenz.music.events.NativeLogger
import java.nio.ByteBuffer
import kotlin.math.floor
import kotlin.math.max

/**
 * AudioProcessor wrapping Signalsmith Stretch (libstretch_native.so) — a
 * header-only C++ STFT-based pitch-shift/time-stretch library — as a FULL
 * REPLACEMENT for ExoPlayer's built-in SonicAudioProcessor.
 *
 * WHY replace Sonic entirely instead of running it alongside: Sonic's
 * WSOLA-style algorithm gets audibly "gritty"/robotic away from 1.0x,
 * especially combined with pitch shift. Signalsmith Stretch stays clean
 * across a much wider range (README: multi-octave pitch shift; best
 * time-stretch quality between 0.75x–1.5x, still usable well outside that).
 * This is a deliberate, user-approved architecture choice — see
 * Media3PlaybackService's chain wiring, which now omits Sonic's speed/pitch
 * handling (PlaybackParameters.speed/pitch are left at their ExoPlayer
 * defaults; this processor owns speed+pitch instead).
 *
 * ── Speed realisation ────────────────────────────────────────────────────
 *
 *  Signalsmith Stretch has no explicit "speed" setter. Per its own docs
 *  ("Time-stretching"): you realise a stretch ratio purely by handing it
 *  differently-sized input/output blocks to process(); it's the caller's
 *  job to make the block lengths average out to the desired ratio over
 *  time. Each queueInput() call here computes
 *  `outputFrames = round(inputFrames / speed)`, with a fractional carry
 *  accumulator so per-call rounding never drifts total track duration.
 *
 * ── Pitch realisation ────────────────────────────────────────────────────
 *
 *  setTransposeSemitones() is a genuine library setting — no block-size
 *  trick needed. It can be changed live between calls.
 *
 * ── Fast path ────────────────────────────────────────────────────────────
 *
 *  When speed==1.0 AND pitch==0 semitones (the overwhelmingly common case),
 *  queueInput() skips the native call entirely and does a pure bulk copy —
 *  the STFT engine is not free even at unity settings, so this keeps the
 *  common case as cheap as the old Sonic-bypassed path.
 *
 * ── Fail-open ────────────────────────────────────────────────────────────
 *
 *  If libstretch_native.so fails to load, or native creation/processing
 *  fails for any reason, this processor deactivates (onConfigure returns
 *  NOT_SET) or emits nothing for the failing call — it can never crash the
 *  pipeline or emit non-finite/garbage audio. The cost of a native failure
 *  is "speed/pitch temporarily has no effect", never corrupted playback.
 *
 * ── Per-player instances ─────────────────────────────────────────────────
 *
 *  Unlike NativeDspAudioProcessor (which calls into shared global C state),
 *  each instance of this class owns its OWN native StretchHandle — Signalsmith
 *  Stretch is not thread-safe/shareable, and each ExoPlayer (primary +
 *  secondary/crossfade) runs its own audio thread. [StretchManager] tracks
 *  all live instances so a single Dart-driven setSpeed/setPitch call updates
 *  every active player atomically, mirroring the [StereoWidthManager] pattern.
 */
@UnstableApi
class SignalsmithStretchAudioProcessor : BaseAudioProcessor() {

    companion object {
        private const val LOG_TAG = "StretchAudioProc"

        @JvmStatic
        private external fun nativeCreate(sampleRate: Int, channels: Int): Long

        @JvmStatic
        private external fun nativeDestroy(handle: Long)

        @JvmStatic
        private external fun nativeReset(handle: Long)

        @JvmStatic
        private external fun nativeSetPitchSemitones(handle: Long, semitones: Float)

        @JvmStatic
        private external fun nativeOutputLatencyFrames(handle: Long): Int

        @JvmStatic
        private external fun nativeProcess(
            handle: Long,
            input: ByteBuffer,
            inputFrames: Int,
            output: ByteBuffer,
            outputFrames: Int,
        ): Int

        @JvmStatic
        private external fun nativeFlush(handle: Long, output: ByteBuffer, outputFrames: Int): Int

        /** Evaluated once; never changes afterwards. */
        val isLibraryAvailable: Boolean = run {
            Log.i(LOG_TAG, "Loading native library stretch_native...")
            NativeLogger.emit("info", "Stretch", "[Stretch] Loading native library stretch_native...")
            runCatching {
                System.loadLibrary("stretch_native")
                Log.i(LOG_TAG, "Native library loaded successfully")
                NativeLogger.emit("info", "Stretch", "[Stretch] Native library loaded successfully")
                true
            }.getOrElse { e ->
                Log.w(LOG_TAG, "Failed to load stretch_native.so: $e")
                NativeLogger.emit("error", "Stretch", "[Stretch] Failed to load stretch_native.so: ${e.message}")
                false
            }
        }

        private const val MAX_CHANNELS = 8

        /**
         * Bridge for native (JNI/C++) log calls — stretch_jni.cpp resolves this
         * static method via JNI and calls it directly, since native code cannot
         * reach the Dart-facing [NativeLogger] EventChannel on its own. Every
         * native log therefore also appears in the app's System Log screen, not
         * only in Logcat.
         */
        @JvmStatic
        fun nativeLog(level: String, message: String) {
            NativeLogger.emit(level, "StretchNative", message)
        }
    }

    @Volatile private var speed: Float = 1f
    @Volatile private var pitchSemitones: Float = 0f

    private var handle: Long = 0L
    private var carryFrames: Double = 0.0

    // Tracks whether the current handle has run any audio through the real
    // STFT path (nativeProcess) since it was created or last flushed/reset.
    // This — NOT the current live speed/pitch values — is what determines
    // whether Signalsmith may still be holding buffered/unemitted output at
    // EOS: speed/pitch can return to unity (routing queueInput() onto the
    // fast bypass below) while audio from an earlier non-unity stretch is
    // still sitting inside the STFT pipeline, unflushed. Only ever touched
    // from this instance's own audio thread (see class doc "Per-player
    // instances"), so a plain field is safe.
    private var hasBufferedStretchState: Boolean = false

    // queueInput() runs exclusively on this instance's own ExoPlayer audio
    // thread (see class doc "Per-player instances"), so a plain (non-volatile)
    // field is safe here and keeps the throttle check allocation-free.
    private var lastQueueInputLogMs: Long = 0L

    /** Applies a new speed (1.0 = normal). Safe to call from any thread. */
    fun setSpeed(newSpeed: Float) {
        speed = if (newSpeed.isFinite() && newSpeed > 0f) newSpeed else 1f
    }

    /** Applies a new pitch shift in semitones (0 = no shift). Safe to call from any thread. */
    fun setPitchSemitones(newSemitones: Float) {
        pitchSemitones = if (newSemitones.isFinite()) newSemitones else 0f
        val h = handle
        if (h != 0L) nativeSetPitchSemitones(h, pitchSemitones)
    }

    // ── BaseAudioProcessor overrides ─────────────────────────────────────────

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val notSetReason = when {
            !isLibraryAvailable -> "library not available"
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT ->
                "encoding=${inputAudioFormat.encoding} != ENCODING_PCM_FLOAT(${C.ENCODING_PCM_FLOAT})"
            inputAudioFormat.channelCount !in 1..MAX_CHANNELS ->
                "channelCount=${inputAudioFormat.channelCount} out of range 1..$MAX_CHANNELS"
            else -> null
        }
        if (notSetReason != null) {
            NativeLogger.emit(
                "warn", "Stretch",
                "[Stretch] onConfigure -> NOT_SET reason=\"$notSetReason\" sampleRate=${inputAudioFormat.sampleRate} " +
                    "channels=${inputAudioFormat.channelCount} encoding=${inputAudioFormat.encoding} " +
                    "handle=0x${handle.toString(16)} libraryAvailable=$isLibraryAvailable active=false",
            )
            return AudioProcessor.AudioFormat.NOT_SET
        }

        if (handle != 0L) {
            NativeLogger.emit("info", "Stretch", "[Stretch] onConfigure destroying stale handle=0x${handle.toString(16)}")
            nativeDestroy(handle)
            handle = 0L
        }
        val h = nativeCreate(inputAudioFormat.sampleRate, inputAudioFormat.channelCount)
        if (h == 0L) {
            Log.w(LOG_TAG, "native stretch init failed — speed/pitch bypassed for this format")
            NativeLogger.emit(
                "warn", "Stretch",
                "[Stretch] onConfigure -> NOT_SET reason=\"nativeCreate returned 0\" " +
                    "sampleRate=${inputAudioFormat.sampleRate} channels=${inputAudioFormat.channelCount} " +
                    "libraryAvailable=$isLibraryAvailable active=false",
            )
            return AudioProcessor.AudioFormat.NOT_SET
        }
        handle = h
        nativeSetPitchSemitones(h, pitchSemitones)
        carryFrames = 0.0
        hasBufferedStretchState = false

        NativeLogger.emit(
            "info", "Stretch",
            "[Stretch] onConfigure -> ACTIVE sampleRate=${inputAudioFormat.sampleRate} " +
                "channels=${inputAudioFormat.channelCount} encoding=${inputAudioFormat.encoding} " +
                "handle=0x${h.toString(16)} libraryAvailable=$isLibraryAvailable returned=PCM_FLOAT active=true",
        )
        logDiagnosticSummary(inputAudioFormat, h)

        // Frame count changes with speed, but channel layout/encoding/rate do not.
        return inputAudioFormat
    }

    /** One-shot "playback started" summary block — see rule 13 of the Stretch diagnostics spec. */
    private fun logDiagnosticSummary(format: AudioProcessor.AudioFormat, h: Long) {
        val summary = buildString {
            appendLine("[Stretch] ========== Stretch Diagnostic ==========")
            appendLine("[Stretch] Library Loaded      : $isLibraryAvailable")
            appendLine("[Stretch] Processor Active    : true")
            appendLine("[Stretch] Audio Format        : ${if (format.encoding == C.ENCODING_PCM_FLOAT) "PCM_FLOAT" else format.encoding.toString()}")
            appendLine("[Stretch] Sample Rate         : ${format.sampleRate}")
            appendLine("[Stretch] Channels            : ${format.channelCount}")
            appendLine("[Stretch] Handle              : 0x${h.toString(16)}")
            appendLine("[Stretch] Speed               : ${"%.2f".format(speed)}")
            appendLine("[Stretch] Pitch               : ${"%.2f".format(pitchSemitones)} st")
            append("[Stretch] ========================================")
        }
        NativeLogger.emit("info", "Stretch", summary)
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining == 0) return

        val channelCount = inputAudioFormat.channelCount
        val bytesPerFrame = channelCount * 4
        val inputFrames = remaining / bytesPerFrame
        if (inputFrames == 0) return

        val currentSpeed = speed
        val currentPitch = pitchSemitones
        val h = handle

        if (h == 0L || (currentSpeed == 1f && currentPitch == 0f)) {
            // Fast bypass: pure pass-through, no STFT cost.
            val output = replaceOutputBuffer(inputFrames * bytesPerFrame)
            output.put(inputBuffer)
            output.flip()
            maybeLogQueueInput(h, inputFrames, inputFrames, currentSpeed, currentPitch, bytesPerFrame, remaining, carryFrames)
            return
        }

        // Fractional-carry accounting so per-call rounding never drifts total
        // track duration over a long playback session.
        val exactOutputFrames = inputFrames / currentSpeed.toDouble() + carryFrames
        val outputFrames = max(0, floor(exactOutputFrames).toInt())
        carryFrames = exactOutputFrames - outputFrames

        maybeLogQueueInput(h, inputFrames, outputFrames, currentSpeed, currentPitch, bytesPerFrame, remaining, carryFrames)

        // Fully consume the input regardless of outcome — this processor
        // never asks to be re-called with the same bytes.
        inputBuffer.position(inputBuffer.limit())

        if (outputFrames == 0) return

        // The STFT engine is about to run — it may retain buffered/unemitted
        // output afterwards even if speed/pitch return to unity before EOS.
        hasBufferedStretchState = true

        val outputBytes = outputFrames * bytesPerFrame
        val output = replaceOutputBuffer(outputBytes)
        val result = nativeProcess(h, inputBuffer, inputFrames, output, outputFrames)
        if (result == 0) {
            output.position(0).limit(outputBytes)
        } else {
            // Fail-open: emit nothing for this call rather than garbage audio.
            output.position(0).limit(0)
        }
    }

    /** Throttled to at most once every 2s (rule 6) to avoid flooding the System Log. */
    private fun maybeLogQueueInput(
        h: Long,
        inputFrames: Int,
        outputFrames: Int,
        spd: Float,
        pitch: Float,
        bytesPerFrame: Int,
        bufferSize: Int,
        carry: Double,
    ) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastQueueInputLogMs < 2000L) return
        lastQueueInputLogMs = now
        NativeLogger.emit(
            "info", "Stretch",
            "[Stretch] queueInput hash=${System.identityHashCode(this)} handle=0x${h.toString(16)} " +
                "inputFrames=$inputFrames outputFrames=$outputFrames carryFrames=$carry speed=$spd pitch=${pitch}st " +
                "bytesPerFrame=$bytesPerFrame bufferSize=$bufferSize",
        )
    }

    override fun onQueueEndOfStream() {
        val h = handle
        NativeLogger.emit(
            "info", "Stretch",
            "[Stretch] onQueueEndOfStream EOS received handle=0x${h.toString(16)} hasBufferedState=$hasBufferedStretchState",
        )
        // Whether to flush depends on whether the STFT engine has actually
        // buffered anything since it was last flushed/reset — NOT on the
        // current live speed/pitch values (those can have returned to unity
        // while earlier non-unity output is still sitting inside the pipeline).
        if (h != 0L && hasBufferedStretchState) {
            val channelCount = inputAudioFormat.channelCount
            // outputLatency() is only the library's documented *minimum* flush
            // size ("should ideally be at least outputLatency()"); passing
            // exactly that triggers Signalsmith's lossy fold-back path inside
            // flush(). outputLatency() == windowSize() - windowSize()/2, i.e.
            // ceil(windowSize()/2), so 2*outputLatency() is always >= the STFT
            // window size — no public API exposes windowSize()/blockSamples()
            // directly, so this is the safest value derivable from the one
            // accessor that does exist. Requesting >= windowSize() makes
            // flush()'s plainOutput branch cover the whole request with zero
            // fold-back, i.e. a clean linear drain.
            val drainFrames = max(1, nativeOutputLatencyFrames(h) * 2)
            NativeLogger.emit("info", "Stretch", "[Stretch] EOS flush started handle=0x${h.toString(16)} drainFrames=$drainFrames")
            val outputBytes = drainFrames * channelCount * 4
            val output = replaceOutputBuffer(outputBytes)
            // Defensive zero-fill: if windowSize() is odd, 2*outputLatency()
            // overshoots it by exactly one frame that flush() never writes.
            // Without this, that trailing frame would surface whatever stale
            // audio was last left in the reused native scratch buffer instead
            // of silence.
            for (i in 0 until outputBytes) output.put(i, 0)
            val result = nativeFlush(h, output, drainFrames)
            if (result == 0) {
                output.position(0).limit(outputBytes)
                hasBufferedStretchState = false
                NativeLogger.emit(
                    "info", "Stretch",
                    "[Stretch] EOS flush completed handle=0x${h.toString(16)} framesFlushed=$drainFrames result=$result",
                )
            } else {
                output.position(0).limit(0)
                NativeLogger.emit("warn", "Stretch", "[Stretch] EOS flush failed handle=0x${h.toString(16)} result=$result")
            }
        } else {
            NativeLogger.emit("info", "Stretch", "[Stretch] EOS flush skipped (no buffered state) handle=0x${h.toString(16)}")
        }
    }

    override fun onFlush() {
        // Called on seek/discontinuity while the processor stays configured —
        // clear internal STFT state so spectral history never bleeds across
        // a seek boundary.
        val h = handle
        NativeLogger.emit("info", "Stretch", "[Stretch] onFlush resetting DSP state handle=0x${h.toString(16)}")
        if (h != 0L) nativeReset(h)
        carryFrames = 0.0
        hasBufferedStretchState = false
    }

    override fun onReset() {
        val h = handle
        if (h != 0L) {
            NativeLogger.emit("info", "Stretch", "[Stretch] onReset destroying handle=0x${h.toString(16)}")
            nativeDestroy(h)
            handle = 0L
            NativeLogger.emit("info", "Stretch", "[Stretch] onReset processor destroyed handle=0x${h.toString(16)}")
        }
        carryFrames = 0.0
        hasBufferedStretchState = false
    }
}
