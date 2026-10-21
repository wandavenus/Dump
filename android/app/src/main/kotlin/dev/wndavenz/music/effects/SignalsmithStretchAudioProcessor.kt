package dev.wndavenz.music.effects

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import dev.wndavenz.music.events.NativeLogger
import java.nio.ByteBuffer
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max

/**
 * Overridable seam over the JNI entry points used by
 * [SignalsmithStretchAudioProcessor]. Production always uses the private
 * [SignalsmithStretchAudioProcessor.JniStretchBridge] implementation, which
 * forwards to the `nativeX` externals; JVM unit tests inject a recording fake
 * to assert the always-on STFT contract without the native library.
 */
internal interface StretchNativeBridge {
    val isAvailable: Boolean
    fun create(sampleRate: Int, channels: Int): Long
    fun destroy(handle: Long)
    fun reset(handle: Long)
    fun setPitchSemitones(handle: Long, semitones: Float)
    fun outputLatencyFrames(handle: Long): Int
    fun process(
        handle: Long,
        input: ByteBuffer,
        inputFrames: Int,
        output: ByteBuffer,
        outputFrames: Int,
    ): Int
    fun flush(handle: Long, output: ByteBuffer, outputFrames: Int): Int
}

@UnstableApi
class SignalsmithStretchAudioProcessor internal constructor(
    private val native: StretchNativeBridge = JniStretchBridge,
) : BaseAudioProcessor() {

    companion object {
        private const val LOG_TAG = "StretchAudioProc"
        private const val MIN_FRAMES_FOR_RATIO = 512L

        // Continuous audio-thread smoothing. Unlike the old linear ramp, the
        // current value is never reset when the target changes, so tap-to-value
        // jumps and rapid slider updates cannot restart a ramp at every block.
        private const val PARAMETER_SMOOTHING_MS = 110f
        private const val PARAMETER_EPSILON = 0.0005f

        @JvmStatic private external fun nativeCreate(sampleRate: Int, channels: Int): Long
        @JvmStatic private external fun nativeDestroy(handle: Long)
        @JvmStatic private external fun nativeReset(handle: Long)
        @JvmStatic private external fun nativeSetPitchSemitones(handle: Long, semitones: Float)
        @JvmStatic private external fun nativeOutputLatencyFrames(handle: Long): Int
        @JvmStatic private external fun nativeProcess(handle: Long, input: ByteBuffer, inputFrames: Int, output: ByteBuffer, outputFrames: Int): Int
        @JvmStatic private external fun nativeFlush(handle: Long, output: ByteBuffer, outputFrames: Int): Int

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

        @JvmStatic
        fun nativeLog(level: String, message: String) {
            NativeLogger.emit(level, "StretchNative", message)
        }

        /**
         * Production [StretchNativeBridge]. Kept inside the companion so the
         * externals stay private without Kotlin `internal` name mangling — JNI
         * symbol names in stretch_jni.cpp must match the JVM method names
         * exactly (`Java_..._nativeCreate`, not `nativeCreate$app_debug`).
         */
        private object JniStretchBridge : StretchNativeBridge {
            override val isAvailable: Boolean get() = isLibraryAvailable

            override fun create(sampleRate: Int, channels: Int): Long =
                nativeCreate(sampleRate, channels)

            override fun destroy(handle: Long) = nativeDestroy(handle)

            override fun reset(handle: Long) = nativeReset(handle)

            override fun setPitchSemitones(handle: Long, semitones: Float) =
                nativeSetPitchSemitones(handle, semitones)

            override fun outputLatencyFrames(handle: Long): Int =
                nativeOutputLatencyFrames(handle)

            override fun process(
                handle: Long,
                input: ByteBuffer,
                inputFrames: Int,
                output: ByteBuffer,
                outputFrames: Int,
            ): Int = nativeProcess(handle, input, inputFrames, output, outputFrames)

            override fun flush(handle: Long, output: ByteBuffer, outputFrames: Int): Int =
                nativeFlush(handle, output, outputFrames)
        }
    }

    @Volatile private var speed: Float = 1f
    @Volatile private var baseSpeed: Float = 1f
    @Volatile private var autoMixTempoMultiplier: Float = 1f
    @Volatile private var pitchSemitones: Float = 0f

    private var handle: Long = 0L
    @Volatile private var appliedSpeed: Float = 1f
    private var appliedPitchSemitones: Float = 0f
    private var nativePitchSemitones: Float = 0f
    private var carryFrames: Double = 0.0

    private var totalInputFrames: Long = 0L
    private var totalOutputFrames: Long = 0L
    private var nativeProcessingHealthy: Boolean = false
    private var lastNativeFailureResult: Int? = null
    private var hasBufferedStretchState: Boolean = false

    /** Speed currently applied by the audio thread after smoothing. */
    fun effectivePlaybackSpeed(): Float =
        appliedSpeed.takeIf { it.isFinite() && it > 0f } ?: 1f

    /** User-selected speed, multiplied by the independent AutoMix deck tempo. */
    fun setSpeed(newSpeed: Float) {
        baseSpeed = if (newSpeed.isFinite() && newSpeed > 0f) newSpeed else 1f
        speed = baseSpeed * autoMixTempoMultiplier
    }

    /** AutoMix-only tempo correction; it never changes the user's manual speed setting. */
    fun setAutoMixTempoMultiplier(multiplier: Float) {
        autoMixTempoMultiplier = if (multiplier.isFinite()) multiplier.coerceIn(0.92f, 1.08f) else 1f
        speed = baseSpeed * autoMixTempoMultiplier
    }

    fun setPitchSemitones(newSemitones: Float) {
        pitchSemitones = if (newSemitones.isFinite()) newSemitones else 0f
    }

    /**
     * Continuous first-order smoothing. The important property is that a new
     * target does NOT reset elapsed time/start value. The audio-thread value
     * simply moves a small fraction toward whatever target is current for this
     * block. This makes a single large tap and a sequence of drag updates follow
     * exactly the same continuous path.
     */
    private fun advanceParameter(current: Float, target: Float, inputFrames: Int): Float {
        if (abs(current - target) <= PARAMETER_EPSILON) return target
        val sampleRate = inputAudioFormat.sampleRate.coerceAtLeast(1)
        val timeConstantFrames =
            (sampleRate * PARAMETER_SMOOTHING_MS / 1000f).coerceAtLeast(1f)
        val alpha = (1f - exp(-inputFrames / timeConstantFrames)).coerceIn(0f, 1f)
        return current + (target - current) * alpha
    }

    private fun advanceSpeed(inputFrames: Int): Float {
        appliedSpeed = advanceParameter(appliedSpeed, speed, inputFrames)
        return appliedSpeed
    }

    private fun advancePitch(inputFrames: Int): Float {
        appliedPitchSemitones = advanceParameter(appliedPitchSemitones, pitchSemitones, inputFrames)
        return appliedPitchSemitones
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val notSetReason = when {
            !native.isAvailable -> "library not available"
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
                    "handle=0x${handle.toString(16)} libraryAvailable=${native.isAvailable} active=false",
            )
            return AudioProcessor.AudioFormat.NOT_SET
        }

        if (handle != 0L) {
            NativeLogger.emit("info", "Stretch", "[Stretch] onConfigure destroying stale handle=0x${handle.toString(16)}")
            native.destroy(handle)
            handle = 0L
        }
        val h = native.create(inputAudioFormat.sampleRate, inputAudioFormat.channelCount)
        if (h == 0L) {
            nativeProcessingHealthy = false
            Log.w(LOG_TAG, "native stretch init failed — speed/pitch bypassed for this format")
            NativeLogger.emit(
                "warn", "Stretch",
                "[Stretch] onConfigure -> NOT_SET reason=\"nativeCreate returned 0\" " +
                    "sampleRate=${inputAudioFormat.sampleRate} channels=${inputAudioFormat.channelCount} " +
                    "libraryAvailable=${native.isAvailable} active=false",
            )
            return AudioProcessor.AudioFormat.NOT_SET
        }
        handle = h
        nativeProcessingHealthy = false
        lastNativeFailureResult = null
        appliedSpeed = speed
        appliedPitchSemitones = pitchSemitones
        nativePitchSemitones = pitchSemitones
        native.setPitchSemitones(h, nativePitchSemitones)
        carryFrames = 0.0
        hasBufferedStretchState = false

        val latencyFrames = native.outputLatencyFrames(h)
        // Always-on STFT: Signalsmith has an intrinsic block+interval input→output
        // latency. Splicing it in mid-stream (dry bypass → STFT) cannot be aligned
        // by seek(); the first output is the pre-roll (audio the user already
        // heard) and synthesis needs one interval to warm up, which is audible as
        // a dropout/stutter click on the first speed/pitch slider move. Keeping
        // the engine engaged from the first sample of every stream removes that
        // transition entirely; parameter changes then only move its targets.
        NativeLogger.emit(
            "info", "Stretch",
            "[Stretch] always-on STFT engaged for this stream outputLatency=$latencyFrames frames " +
                "handle=0x${h.toString(16)}",
        )
        logDiagnosticSummary(inputAudioFormat, h)
        return inputAudioFormat
    }

    private fun logDiagnosticSummary(format: AudioProcessor.AudioFormat, h: Long) {
        val summary = buildString {
            appendLine("[Stretch] ========== Stretch Diagnostic ==========")
            appendLine("[Stretch] Library Loaded      : ${native.isAvailable}")
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
        val inputView = inputBuffer.duplicate()
        val h = handle

        val currentSpeed = advanceSpeed(inputFrames)
        val currentPitch = advancePitch(inputFrames)
        if (h != 0L && abs(currentPitch - nativePitchSemitones) > PARAMETER_EPSILON) {
            native.setPitchSemitones(h, currentPitch)
            nativePitchSemitones = currentPitch
        }

        // Native library unavailable → transparent pass-through (fail-open).
        // When a handle exists the STFT engine is ALWAYS used, including at
        // exactly 1.0x / 0 semitones. That is deliberate: a mid-stream switch
        // between dry bypass and the latency-bearing STFT would replay the
        // pre-roll and drop the synthesis warm-up interval, which is exactly
        // the first-slider-move crackle this processor used to have.
        if (h == 0L) {
            totalInputFrames += inputFrames
            totalOutputFrames += inputFrames
            val output = replaceOutputBuffer(remaining)
            output.put(inputBuffer)
            output.flip()
            return
        }

        val exactOutputFrames = inputFrames / currentSpeed.toDouble() + carryFrames
        val outputFrames = max(1, floor(exactOutputFrames).toInt())
        carryFrames = exactOutputFrames - outputFrames

        val outputBytes = outputFrames * bytesPerFrame
        val output = replaceOutputBuffer(max(remaining, outputBytes))
        output.clear()
        val result = native.process(h, inputView, inputFrames, output, outputFrames)
        inputBuffer.position(inputBuffer.limit())
        if (result == 0) {
            output.position(0).limit(outputBytes)
            totalInputFrames += inputFrames
            totalOutputFrames += outputFrames
            nativeProcessingHealthy = true
            lastNativeFailureResult = null
            hasBufferedStretchState = true
        } else {
            output.clear()
            output.put(inputView)
            output.flip()
            totalInputFrames += inputFrames
            totalOutputFrames += inputFrames
            nativeProcessingHealthy = false
            hasBufferedStretchState = false
            carryFrames = 0.0
            native.reset(h)
            if (lastNativeFailureResult != result) {
                NativeLogger.emit(
                    "warn", "Stretch",
                    "[Stretch] nativeProcess failed result=$result sampleRate=${inputAudioFormat.sampleRate} " +
                        "inputFrames=$inputFrames outputFrames=$outputFrames; using pass-through",
                )
                lastNativeFailureResult = result
            }
        }
    }

    override fun onQueueEndOfStream() {
        val h = handle
        if (h != 0L && hasBufferedStretchState) {
            val channelCount = inputAudioFormat.channelCount
            // Signalsmith Stretch 1.2.0 flushes at most one STFT block; outputLatency() is
            // the documented minimum tail to read and is within the default block size.
            val drainFrames = max(1, native.outputLatencyFrames(h))
            val outputBytes = drainFrames * channelCount * 4
            val output = replaceOutputBuffer(outputBytes)
            for (i in 0 until outputBytes) output.put(i, 0)
            val result = native.flush(h, output, drainFrames)
            if (result == 0) {
                output.position(0).limit(outputBytes)
                hasBufferedStretchState = false
                NativeLogger.emit("info", "Stretch", "[Stretch] EOS flush completed handle=0x${h.toString(16)} framesFlushed=$drainFrames result=$result")
            } else {
                output.position(0).limit(0)
                NativeLogger.emit("warn", "Stretch", "[Stretch] EOS flush failed handle=0x${h.toString(16)} result=$result")
            }
        } else {
            NativeLogger.emit("info", "Stretch", "[Stretch] EOS flush skipped (no buffered state) handle=0x${h.toString(16)}")
        }
    }

    fun getMediaDuration(playoutDurationUs: Long): Long {
        if (!nativeProcessingHealthy) return playoutDurationUs
        val out = totalOutputFrames
        val inp = totalInputFrames
        return when {
            out < MIN_FRAMES_FOR_RATIO -> {
                val s = speed
                if (s == 1f) playoutDurationUs else (playoutDurationUs.toDouble() * s).toLong()
            }
            else -> Util.scaleLargeTimestamp(playoutDurationUs, inp, out)
        }
    }

    override fun getDurationAfterProcessorApplied(durationUs: Long): Long {
        if (!nativeProcessingHealthy) return durationUs
        val s = speed
        if (s == 1f) return durationUs
        return (durationUs.toDouble() / s).toLong().coerceAtLeast(0L)
    }

    @Deprecated("Deprecated by Media3; retained for BaseAudioProcessor lifecycle compatibility.")
    override fun onFlush() {
        val h = handle
        // No NativeLogger.emit() here: onFlush runs on the playback thread for
        // every seek/timeline reset, and the native→Kotlin log bridge must not
        // be called from a path that can overlap audible audio.
        if (h != 0L) {
            native.reset(h)
            native.setPitchSemitones(h, pitchSemitones)
        }
        carryFrames = 0.0
        hasBufferedStretchState = false
        nativeProcessingHealthy = false
        lastNativeFailureResult = null
        appliedSpeed = speed
        appliedPitchSemitones = pitchSemitones
        nativePitchSemitones = pitchSemitones
        totalInputFrames = 0L
        totalOutputFrames = 0L
    }

    override fun onReset() {
        val h = handle
        if (h != 0L) {
            NativeLogger.emit("info", "Stretch", "[Stretch] onReset destroying handle=0x${h.toString(16)}")
            native.destroy(h)
            handle = 0L
            NativeLogger.emit("info", "Stretch", "[Stretch] onReset processor destroyed handle=0x${h.toString(16)}")
        }
        carryFrames = 0.0
        hasBufferedStretchState = false
        totalInputFrames = 0L
        totalOutputFrames = 0L
        nativeProcessingHealthy = false
        lastNativeFailureResult = null
        appliedSpeed = 1f
        appliedPitchSemitones = 0f
        nativePitchSemitones = 0f
    }
}
