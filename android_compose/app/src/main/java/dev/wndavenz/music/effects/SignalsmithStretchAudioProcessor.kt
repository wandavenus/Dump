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

@UnstableApi
class SignalsmithStretchAudioProcessor : BaseAudioProcessor() {

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
        @JvmStatic private external fun nativePrime(handle: Long, input: ByteBuffer, inputFrames: Int): Int

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
    }

    @Volatile private var speed: Float = 1f
    @Volatile private var pitchSemitones: Float = 0f

    private var handle: Long = 0L
    private var appliedSpeed: Float = 1f
    private var appliedPitchSemitones: Float = 0f
    private var nativePitchSemitones: Float = 0f
    private var carryFrames: Double = 0.0

    private var totalInputFrames: Long = 0L
    private var totalOutputFrames: Long = 0L
    private var nativeProcessingHealthy: Boolean = false
    private var lastNativeFailureResult: Int? = null
    private var hasBufferedStretchState: Boolean = false
    private var prevWasBypass: Boolean = true

    private var bypassRingBytes: ByteArray = ByteArray(0)
    private var bypassRingWritePos: Int = 0
    private var bypassRingFilled: Int = 0
    private var bypassPrimeBuf: ByteBuffer = ByteBuffer.allocateDirect(0)

    fun setSpeed(newSpeed: Float) {
        speed = if (newSpeed.isFinite() && newSpeed > 0f) newSpeed else 1f
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
            nativeProcessingHealthy = false
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
        nativeProcessingHealthy = false
        lastNativeFailureResult = null
        appliedSpeed = speed
        appliedPitchSemitones = pitchSemitones
        nativePitchSemitones = pitchSemitones
        nativeSetPitchSemitones(h, nativePitchSemitones)
        prevWasBypass = true
        carryFrames = 0.0
        hasBufferedStretchState = false

        val latencyFrames = nativeOutputLatencyFrames(h)
        val ringCapFrames = max(latencyFrames, 1024)
        val ringCapBytes = ringCapFrames * inputAudioFormat.channelCount * 4
        if (bypassRingBytes.size != ringCapBytes) {
            bypassRingBytes = ByteArray(ringCapBytes)
            bypassPrimeBuf = ByteBuffer.allocateDirect(ringCapBytes)
        }
        clearBypassRing()
        NativeLogger.emit(
            "info", "Stretch",
            "[Stretch] bypass ring: latencyFrames=$latencyFrames ringCapFrames=$ringCapFrames " +
                "ringCapBytes=$ringCapBytes handle=0x${h.toString(16)}",
        )
        logDiagnosticSummary(inputAudioFormat, h)
        return inputAudioFormat
    }

    private fun writeBypassRing(src: ByteBuffer, byteCount: Int) {
        val cap = bypassRingBytes.size
        if (cap == 0 || byteCount <= 0) return
        val view = src.duplicate()
        if (byteCount >= cap) {
            view.position(view.position() + byteCount - cap)
            view.get(bypassRingBytes, 0, cap)
            bypassRingWritePos = 0
            bypassRingFilled = cap
            return
        }
        val firstChunk = minOf(byteCount, cap - bypassRingWritePos)
        val secondChunk = byteCount - firstChunk
        view.get(bypassRingBytes, bypassRingWritePos, firstChunk)
        if (secondChunk > 0) view.get(bypassRingBytes, 0, secondChunk)
        bypassRingWritePos = (bypassRingWritePos + byteCount) % cap
        bypassRingFilled = minOf(bypassRingFilled + byteCount, cap)
    }

    private fun primeEngineFromRing(h: Long, bytesPerFrame: Int): Boolean {
        val filled = bypassRingFilled
        if (filled < bytesPerFrame || bypassPrimeBuf.capacity() == 0) return false
        val cap = bypassRingBytes.size
        bypassPrimeBuf.clear()
        val startPos = ((bypassRingWritePos - filled) % cap + cap) % cap
        val firstChunk = minOf(filled, cap - startPos)
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

    private fun clearBypassRing() {
        bypassRingWritePos = 0
        bypassRingFilled = 0
    }

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
        val inputView = inputBuffer.duplicate()
        val h = handle

        val currentSpeed = advanceSpeed(inputFrames)
        val currentPitch = advancePitch(inputFrames)
        if (h != 0L && abs(currentPitch - nativePitchSemitones) > PARAMETER_EPSILON) {
            nativeSetPitchSemitones(h, currentPitch)
            nativePitchSemitones = currentPitch
        }
        val isBypass = h == 0L || (currentSpeed == 1f && currentPitch == 0f)

        if (h != 0L) {
            if (!isBypass && prevWasBypass) {
                val primed = primeEngineFromRing(h, bytesPerFrame)
                if (!primed) {
                    nativeReset(h)
                    NativeLogger.emit("info", "Stretch", "[Stretch] bypass→STFT: no ring data, fallback reset handle=0x${h.toString(16)}")
                }
                carryFrames = 0.0
                hasBufferedStretchState = false
            } else if (isBypass && !prevWasBypass && hasBufferedStretchState) {
                nativeReset(h)
                clearBypassRing()
                carryFrames = 0.0
                hasBufferedStretchState = false
                NativeLogger.emit("info", "Stretch", "[Stretch] STFT→bypass: reset engine + cleared ring handle=0x${h.toString(16)}")
            }
        }
        prevWasBypass = isBypass

        if (isBypass) {
            totalInputFrames += inputFrames
            totalOutputFrames += inputFrames
            val output = replaceOutputBuffer(inputFrames * bytesPerFrame)
            output.put(inputBuffer)
            output.flip()
            writeBypassRing(output, inputFrames * bytesPerFrame)
            return
        }

        val exactOutputFrames = inputFrames / currentSpeed.toDouble() + carryFrames
        val outputFrames = max(0, floor(exactOutputFrames).toInt())
        carryFrames = exactOutputFrames - outputFrames

        if (outputFrames == 0) {
            val output = replaceOutputBuffer(remaining)
            output.put(inputView)
            output.flip()
            inputBuffer.position(inputBuffer.limit())
            totalInputFrames += inputFrames
            totalOutputFrames += inputFrames
            nativeProcessingHealthy = false
            return
        }

        val outputBytes = outputFrames * bytesPerFrame
        val output = replaceOutputBuffer(max(remaining, outputBytes))
        output.clear()
        val result = nativeProcess(h, inputView, inputFrames, output, outputFrames)
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
            nativeReset(h)
            prevWasBypass = true
            writeBypassRing(output, remaining)
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
        NativeLogger.emit("info", "Stretch", "[Stretch] onQueueEndOfStream EOS received handle=0x${h.toString(16)} hasBufferedState=$hasBufferedStretchState")
        if (h != 0L && hasBufferedStretchState) {
            val channelCount = inputAudioFormat.channelCount
            val drainFrames = max(1, nativeOutputLatencyFrames(h) * 2)
            NativeLogger.emit("info", "Stretch", "[Stretch] EOS flush started handle=0x${h.toString(16)} drainFrames=$drainFrames")
            val outputBytes = drainFrames * channelCount * 4
            val output = replaceOutputBuffer(outputBytes)
            for (i in 0 until outputBytes) output.put(i, 0)
            val result = nativeFlush(h, output, drainFrames)
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

    override fun onFlush() {
        val h = handle
        NativeLogger.emit("info", "Stretch", "[Stretch] onFlush resetting DSP state handle=0x${h.toString(16)}")
        if (h != 0L) nativeReset(h)
        carryFrames = 0.0
        hasBufferedStretchState = false
        nativeProcessingHealthy = false
        lastNativeFailureResult = null
        appliedSpeed = speed
        appliedPitchSemitones = pitchSemitones
        nativePitchSemitones = pitchSemitones
        totalInputFrames = 0L
        totalOutputFrames = 0L
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
        totalInputFrames = 0L
        totalOutputFrames = 0L
        nativeProcessingHealthy = false
        lastNativeFailureResult = null
        appliedSpeed = 1f
        appliedPitchSemitones = 0f
        nativePitchSemitones = 0f
        clearBypassRing()
        prevWasBypass = true
    }
}
