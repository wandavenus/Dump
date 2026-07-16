package dev.wndavenz.music.effects

import android.os.SystemClock
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
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

        /**
         * Minimum accumulated output-frame count before [getMediaDuration] switches from the
         * nominal-speed approximation to the actual I/O-frame ratio.  Mirrors Sonic's
         * MIN_BYTES_FOR_DURATION_SCALING_CALCULATION (1 024 bytes) scaled to frames; at 44 100 Hz
         * stereo float32 one chunk is typically 1 024 frames, so the real path kicks in after
         * the very first queueInput() call under normal conditions.
         */
        private const val MIN_FRAMES_FOR_RATIO = 512L

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

        /**
         * Primes the STFT engine's spectral-analysis history without producing output.
         * Feeds [inputFrames] of interleaved float32 PCM into the engine with
         * outputSamples=0 — the analysis window fills with real signal so the very
         * first [nativeProcess] call after a bypass→STFT transition produces clean,
         * seamless audio instead of a STFT warm-up silence artifact.
         *
         * Returns 0 on success, negative on failure (treated as no-op by the caller).
         */
        @JvmStatic
        private external fun nativePrime(handle: Long, input: ByteBuffer, inputFrames: Int): Int

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

    // ── Media-timeline synchronization counters ───────────────────────────────
    //
    // Accumulated input and output frame counts since the last flush() — mirrors
    // SonicAudioProcessor's inputBytes/outputBytes approach (SonicAudioProcessor.java:64–65,
    // 233, 259).  Used by getMediaDuration() to report the actual I/O ratio to
    // StretchAwareAudioProcessorChain, which feeds it into DefaultAudioSink's
    // applyMediaPositionParameters() → getCurrentPositionUs() path.
    //
    // Both fields are written exclusively on the ExoPlayer audio thread (same thread
    // that calls queueInput/onFlush/onReset), so they need no synchronisation.
    // getMediaDuration() is also called from the same audio/render thread via
    // DecoderAudioRenderer → DefaultAudioSink.getCurrentPositionUs().
    private var totalInputFrames: Long = 0L
    private var totalOutputFrames: Long = 0L

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

    // ── Thread-safety for pitch changes ───────────────────────────────────────
    //
    // Signalsmith Stretch is NOT thread-safe. Both setTransposeSemitones() and
    // process() operate on the same C++ StretchHandle. Previously, setPitchSemitones()
    // called nativeSetPitchSemitones() directly from whatever thread it was
    // invoked on (typically the MethodChannel handler = main thread), racing with
    // nativeProcess() on the audio thread — undefined behaviour.
    //
    // Fix: setPitchSemitones() now only writes the @Volatile pitchSemitones
    // field and raises this flag. The actual native call is deferred to
    // queueInput(), which always runs on the audio thread that owns this handle.
    @Volatile private var pendingPitchApply: Boolean = false

    // Audio thread only — tracks whether the PREVIOUS queueInput() call went
    // through the fast-bypass path. Used to detect bypass↔STFT transitions.
    // Initialised to true so the very first queueInput() in STFT mode always
    // attempts a prime (or falls back to reset if the ring is empty).
    private var prevWasBypass: Boolean = true

    // ── Bypass audio ring buffer for zero-flicker STFT priming ───────────────
    //
    // On a bypass→STFT transition (speed/pitch leaving 1.0×/0st) we feed the
    // last outputLatency() frames of bypass audio into the engine with
    // outputFrames=0 via nativePrime().  This populates the STFT's spectral-
    // analysis history with real signal so its very first process() output is a
    // seamless continuation — no warm-up silence, no fade-in artifact.
    //
    // Layout: interleaved float32 PCM bytes, identical to ExoPlayer's ByteBuffer,
    // so the assembled prime buffer can be passed directly to nativePrime() via
    // GetDirectBufferAddress without any extra deinterleave step in Kotlin.
    //
    // All fields are audio-thread-only — no synchronisation required.
    //
    //   bypassRingBytes  – circular byte store; size = ringCapBytes (set at configure)
    //   bypassRingWritePos – next write position (byte index, wraps at capacity)
    //   bypassRingFilled   – bytes currently valid (≤ capacity)
    //   bypassPrimeBuf     – pre-allocated direct ByteBuffer for the JNI prime call;
    //                        assembled from the ring on each bypass→STFT transition
    private var bypassRingBytes: ByteArray = ByteArray(0)
    private var bypassRingWritePos: Int = 0
    private var bypassRingFilled: Int = 0
    private var bypassPrimeBuf: ByteBuffer = ByteBuffer.allocateDirect(0)

    /** Applies a new speed (1.0 = normal). Safe to call from any thread. */
    fun setSpeed(newSpeed: Float) {
        speed = if (newSpeed.isFinite() && newSpeed > 0f) newSpeed else 1f
    }

    /**
     * Applies a new pitch shift in semitones (0 = no shift). Safe to call from any thread.
     *
     * The actual [nativeSetPitchSemitones] call is deferred to [queueInput] so it always
     * runs on the audio thread — never concurrently with [nativeProcess] on the same
     * (not thread-safe) Signalsmith Stretch object. See [pendingPitchApply].
     */
    fun setPitchSemitones(newSemitones: Float) {
        pitchSemitones = if (newSemitones.isFinite()) newSemitones else 0f
        pendingPitchApply = true
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
        nativeSetPitchSemitones(h, pitchSemitones)   // safe: onConfigure runs on audio thread
        pendingPitchApply = false                     // pitch is now in sync with the engine
        prevWasBypass = true                          // fresh engine, treat as bypass start
        carryFrames = 0.0
        hasBufferedStretchState = false

        // Allocate the bypass ring buffer sized to the engine's output latency.
        // outputLatency() is deterministic after presetDefault() — no audio has
        // to have been processed for this to return the correct value.
        val latencyFrames  = nativeOutputLatencyFrames(h)
        val ringCapFrames  = max(latencyFrames, 1024)   // 1024 frames minimum (~23 ms)
        val ringCapBytes   = ringCapFrames * inputAudioFormat.channelCount * 4  // float32
        if (bypassRingBytes.size != ringCapBytes) {
            bypassRingBytes  = ByteArray(ringCapBytes)
            bypassPrimeBuf   = ByteBuffer.allocateDirect(ringCapBytes)
        }
        clearBypassRing()
        NativeLogger.emit(
            "info", "Stretch",
            "[Stretch] bypass ring: latencyFrames=$latencyFrames ringCapFrames=$ringCapFrames " +
                "ringCapBytes=$ringCapBytes handle=0x${h.toString(16)}",
        )

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

    // ── Bypass ring buffer helpers (audio thread only) ────────────────────────

    /**
     * Writes [byteCount] bytes from [src] (at its current position, via a
     * duplicate so the caller's position is not advanced) into the circular
     * bypass ring buffer, overwriting the oldest data when full.
     */
    private fun writeBypassRing(src: ByteBuffer, byteCount: Int) {
        val cap = bypassRingBytes.size
        if (cap == 0 || byteCount <= 0) return
        val view = src.duplicate()           // independent position, same backing data
        if (byteCount >= cap) {
            // Input fills or overflows the entire ring — keep only the last cap bytes.
            view.position(view.position() + byteCount - cap)
            view.get(bypassRingBytes, 0, cap)
            bypassRingWritePos = 0
            bypassRingFilled   = cap
            return
        }
        // Write two contiguous slices into the circular store.
        val firstChunk  = minOf(byteCount, cap - bypassRingWritePos)
        val secondChunk = byteCount - firstChunk
        view.get(bypassRingBytes, bypassRingWritePos, firstChunk)
        if (secondChunk > 0) view.get(bypassRingBytes, 0, secondChunk)
        bypassRingWritePos = (bypassRingWritePos + byteCount) % cap
        bypassRingFilled   = minOf(bypassRingFilled + byteCount, cap)
    }

    /**
     * Assembles the ring's content into [bypassPrimeBuf] in chronological order
     * and calls [nativePrime] so the STFT engine's analysis window is populated
     * with real bypass audio before the first [nativeProcess] call.
     *
     * Returns true when priming succeeded; false when there was not enough data
     * (caller should fall back to [nativeReset] for a clean-but-silent start).
     */
    private fun primeEngineFromRing(h: Long, bytesPerFrame: Int): Boolean {
        val filled = bypassRingFilled
        if (filled < bytesPerFrame || bypassPrimeBuf.capacity() == 0) return false
        val cap = bypassRingBytes.size
        // Assemble ring into the pre-allocated direct buffer in chronological order.
        bypassPrimeBuf.clear()
        val startPos    = ((bypassRingWritePos - filled) % cap + cap) % cap
        val firstChunk  = minOf(filled, cap - startPos)
        val secondChunk = filled - firstChunk
        bypassPrimeBuf.put(bypassRingBytes, startPos, firstChunk)
        if (secondChunk > 0) bypassPrimeBuf.put(bypassRingBytes, 0, secondChunk)
        bypassPrimeBuf.flip()
        val primeFrames = filled / bytesPerFrame
        val result = nativePrime(h, bypassPrimeBuf, primeFrames)
        NativeLogger.emit(
            "info", "Stretch",
            "[Stretch] bypass→STFT prime: primeFrames=$primeFrames result=$result " +
                "ringFilled=${filled}B handle=0x${h.toString(16)}",
        )
        return result == 0
    }

    /** Resets the ring buffer's logical content without zeroing the backing array. */
    private fun clearBypassRing() {
        bypassRingWritePos = 0
        bypassRingFilled   = 0
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

        val h = handle

        // ── Fix 1: Apply pending pitch change on the audio thread ─────────────
        // setPitchSemitones() only writes @Volatile pitchSemitones + sets this
        // flag; the actual native call is deferred here so setTransposeSemitones()
        // and process() never run concurrently on the same StretchHandle.
        if (pendingPitchApply && h != 0L) {
            nativeSetPitchSemitones(h, pitchSemitones)
            pendingPitchApply = false
        }

        val currentSpeed = speed
        val currentPitch = pitchSemitones
        val isBypass = h == 0L || (currentSpeed == 1f && currentPitch == 0f)

        // ── bypass ↔ STFT transition handling ────────────────────────────────
        if (h != 0L) {
            if (!isBypass && prevWasBypass) {
                // bypass → STFT: prime the STFT engine with the last outputLatency()
                // frames of bypass audio so its spectral history is populated with
                // real signal — the first process() output is a seamless continuation
                // rather than a STFT warm-up silence (zero-flicker transition).
                // Fall back to nativeReset() only if the ring has no data yet
                // (first-ever STFT call, or transition too quick to fill the ring).
                val primed = primeEngineFromRing(h, bytesPerFrame)
                if (!primed) {
                    nativeReset(h)
                    NativeLogger.emit("info", "Stretch",
                        "[Stretch] bypass→STFT: no ring data, fallback reset handle=0x${h.toString(16)}")
                }
                carryFrames = 0.0
                hasBufferedStretchState = false
                totalInputFrames  = 0L
                totalOutputFrames = 0L
            } else if (isBypass && !prevWasBypass && hasBufferedStretchState) {
                // STFT → bypass: reset engine + clear ring.
                // Clearing the ring ensures the next bypass→STFT prime uses only
                // the fresh bypass audio that follows — not audio from before this
                // STFT session, which could be temporally distant.
                nativeReset(h)
                clearBypassRing()
                carryFrames = 0.0
                hasBufferedStretchState = false
                NativeLogger.emit("info", "Stretch",
                    "[Stretch] STFT→bypass: reset engine + cleared ring handle=0x${h.toString(16)}")
            }
        }
        prevWasBypass = isBypass

        if (isBypass) {
            // Fast bypass: pure pass-through, no STFT cost.
            totalInputFrames  += inputFrames
            totalOutputFrames += inputFrames
            val output = replaceOutputBuffer(inputFrames * bytesPerFrame)
            output.put(inputBuffer)
            output.flip()
            // Feed bypass audio into the ring so a future bypass→STFT transition
            // can prime the engine's spectral history for zero-flicker output.
            writeBypassRing(output, inputFrames * bytesPerFrame)
            maybeLogQueueInput(h, inputFrames, inputFrames, currentSpeed, currentPitch, bytesPerFrame, remaining, carryFrames)
            return
        }

        // Fractional-carry accounting so per-call rounding never drifts total
        // track duration over a long playback session.
        val exactOutputFrames = inputFrames / currentSpeed.toDouble() + carryFrames
        val outputFrames = max(0, floor(exactOutputFrames).toInt())
        carryFrames = exactOutputFrames - outputFrames

        // Record the actual I/O ratio for getMediaDuration().  Input is always
        // counted (the bytes are fully consumed regardless of outputFrames), so
        // the ratio tracks the true cumulative stretch applied so far — identical
        // in approach to SonicAudioProcessor.inputBytes / outputBytes.
        totalInputFrames  += inputFrames
        totalOutputFrames += outputFrames

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

    // ── Media-timeline synchronization API ───────────────────────────────────
    //
    // These two methods are the Signalsmith counterparts of
    // SonicAudioProcessor.getMediaDuration() / getDurationAfterProcessorApplied().
    // Together they close the gap identified in the audit: DefaultAudioSink has
    // no way to learn about a custom processor's time-stretch ratio unless the
    // processor explicitly exposes it.

    /**
     * Returns the media duration corresponding to [playoutDurationUs] of AudioTrack
     * output, accounting for the actual accumulated I/O frame ratio.
     *
     * Called by [StretchAwareAudioProcessorChain.getMediaDuration], which is invoked
     * on every [DefaultAudioSink.getCurrentPositionUs] call so that
     * [currentPositionUs] in DecoderAudioRenderer stays aligned with the real media
     * timeline regardless of the current stretch factor.
     *
     * Uses the same approach as [androidx.media3.common.audio.SonicAudioProcessor]:
     * accumulated byte counts (here: frame counts) rather than the nominal speed
     * parameter, so small per-call rounding errors in [carryFrames] cannot
     * accumulate into a visible position drift over a long track.
     *
     * Falls back to the nominal speed multiplier when fewer than [MIN_FRAMES_FOR_RATIO]
     * output frames have been accumulated (initial buffer before the ratio is stable),
     * and returns [playoutDurationUs] unchanged (identity) when speed == 1.0 and
     * pitch == 0 (the common case — fast path produces a 1:1 ratio anyway).
     *
     * Thread: audio / render thread only (same thread that calls queueInput and
     * getCurrentPositionUs inside DefaultAudioSink).
     */
    fun getMediaDuration(playoutDurationUs: Long): Long {
        val out = totalOutputFrames
        val inp = totalInputFrames
        return when {
            // Below the stability threshold — nominal speed gives a reasonable approximation.
            out < MIN_FRAMES_FOR_RATIO -> {
                val s = speed
                if (s == 1f) playoutDurationUs
                else (playoutDurationUs.toDouble() * s).toLong()
            }
            // Accumulated ratio path — identical math to SonicAudioProcessor.getMediaDuration():
            //   Util.scaleLargeTimestamp(playoutDuration, processedInputBytes, outputBytes)
            // substituting frames for bytes (units cancel in the ratio).
            else -> Util.scaleLargeTimestamp(playoutDurationUs, inp, out)
        }
    }

    /**
     * Returns the playout duration that corresponds to [durationUs] of media input
     * at the current speed setting.
     *
     * Called by [AudioProcessingPipeline.flush] (line 188, Media3 1.10.1) for each
     * active processor during seek/track-change to propagate [StreamMetadata.positionOffsetUs]
     * through the pipeline.  At flush time the frame counters have just been reset to
     * zero, so there is no accumulated ratio to use — the nominal speed value is the
     * only available information (same fallback Sonic uses at line 157:
     * `return (long)((double) speed * playoutDuration)` in reverse).
     *
     * Pitch-shift alone (speed == 1.0, semitones ≠ 0) does not change frame count —
     * the result is the identity in that case.
     *
     * @return [durationUs] / speed, i.e. how many microseconds of AudioTrack output
     *         this processor will produce from [durationUs] microseconds of input.
     */
    override fun getDurationAfterProcessorApplied(durationUs: Long): Long {
        val s = speed
        // Fast path / pitch-only: ratio is 1:1.
        if (s == 1f) return durationUs
        // Stretch path: playout is shorter at speed > 1.0, longer at speed < 1.0.
        return (durationUs.toDouble() / s).toLong().coerceAtLeast(0L)
    }

    // ── BaseAudioProcessor lifecycle ──────────────────────────────────────────

    override fun onFlush() {
        // Called on seek/discontinuity while the processor stays configured —
        // clear internal STFT state so spectral history never bleeds across
        // a seek boundary.
        val h = handle
        NativeLogger.emit("info", "Stretch", "[Stretch] onFlush resetting DSP state handle=0x${h.toString(16)}")
        if (h != 0L) nativeReset(h)
        carryFrames = 0.0
        hasBufferedStretchState = false
        // Reset I/O counters: the new segment starts fresh, so any ratio
        // accumulated before the seek is irrelevant to the new position.
        totalInputFrames  = 0L
        totalOutputFrames = 0L
        // Engine has been reset; ring contents are pre-seek audio — discard them
        // so the next bypass→STFT prime uses only post-seek bypass audio.
        clearBypassRing()
        prevWasBypass = true
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
        totalInputFrames  = 0L
        totalOutputFrames = 0L
        pendingPitchApply = false
        clearBypassRing()
        prevWasBypass = true
    }
}
