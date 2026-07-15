package dev.wndavenz.music.effects

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
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
        val isLibraryAvailable: Boolean = runCatching {
            System.loadLibrary("stretch_native")
            true
        }.getOrElse { e ->
            Log.w(LOG_TAG, "stretch_native unavailable — speed/pitch bypassed: $e")
            false
        }

        private const val MAX_CHANNELS = 8
    }

    @Volatile private var speed: Float = 1f
    @Volatile private var pitchSemitones: Float = 0f

    private var handle: Long = 0L
    private var carryFrames: Double = 0.0

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
        if (!isLibraryAvailable ||
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT ||
            inputAudioFormat.channelCount !in 1..MAX_CHANNELS
        ) {
            return AudioProcessor.AudioFormat.NOT_SET
        }

        if (handle != 0L) {
            nativeDestroy(handle)
            handle = 0L
        }
        val h = nativeCreate(inputAudioFormat.sampleRate, inputAudioFormat.channelCount)
        if (h == 0L) {
            Log.w(LOG_TAG, "native stretch init failed — speed/pitch bypassed for this format")
            return AudioProcessor.AudioFormat.NOT_SET
        }
        handle = h
        nativeSetPitchSemitones(h, pitchSemitones)
        carryFrames = 0.0

        // Frame count changes with speed, but channel layout/encoding/rate do not.
        return inputAudioFormat
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
            return
        }

        // Fractional-carry accounting so per-call rounding never drifts total
        // track duration over a long playback session.
        val exactOutputFrames = inputFrames / currentSpeed.toDouble() + carryFrames
        val outputFrames = max(0, floor(exactOutputFrames).toInt())
        carryFrames = exactOutputFrames - outputFrames

        // Fully consume the input regardless of outcome — this processor
        // never asks to be re-called with the same bytes.
        inputBuffer.position(inputBuffer.limit())

        if (outputFrames == 0) return

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

    override fun queueEndOfStream() {
        val h = handle
        if (h != 0L && !(speed == 1f && pitchSemitones == 0f)) {
            val channelCount = inputAudioFormat.channelCount
            val drainFrames = max(1, nativeOutputLatencyFrames(h))
            val outputBytes = drainFrames * channelCount * 4
            val output = replaceOutputBuffer(outputBytes)
            val result = nativeFlush(h, output, drainFrames)
            if (result == 0) {
                output.position(0).limit(outputBytes)
            } else {
                output.position(0).limit(0)
            }
        }
        super.queueEndOfStream()
    }

    override fun onFlush() {
        // Called on seek/discontinuity while the processor stays configured —
        // clear internal STFT state so spectral history never bleeds across
        // a seek boundary.
        val h = handle
        if (h != 0L) nativeReset(h)
        carryFrames = 0.0
    }

    override fun onReset() {
        val h = handle
        if (h != 0L) {
            nativeDestroy(h)
            handle = 0L
        }
        carryFrames = 0.0
    }
}
