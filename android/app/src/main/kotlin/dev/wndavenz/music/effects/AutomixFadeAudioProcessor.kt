package dev.wndavenz.music.effects

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Process-wide capability latch for the optional sample-timeline AutoMix fade.
 *
 * This latch is deliberately independent from [AutomixToneNativeAvailability]:
 * an APK may have working tone symbols while its fade symbols are absent (or
 * vice versa), and either feature must fail open without disabling the other.
 */
internal class AutomixFadeNativeAvailability {
    @Volatile
    private var available: Boolean = true

    fun canUse(libraryAvailable: Boolean): Boolean = libraryAvailable && available

    fun markUnavailable() {
        available = false
    }
}

/**
 * Float PCM processor that applies one AutoMix deck envelope per sample frame.
 *
 * The native stage is armed with an absolute media-timeline position. Its
 * audio-thread frame cursor advances with PCM input, so decoder/output
 * buffering does not turn JNI-call time into the fade phase. If the library,
 * format, symbol, or processor state is unavailable, Media3 skips this stage
 * and [CrossfadeController] uses its Kotlin volume-envelope fallback.
 */
@UnstableApi
class AutomixFadeAudioProcessor(
    internal val streamSlot: Int,
) : BaseAudioProcessor() {
    companion object {
        const val OUTGOING = 0
        const val INCOMING = 1

        private val nativeAvailability = AutomixFadeNativeAvailability()

        @JvmStatic
        private external fun nativeConfigureFade(
            streamSlot: Int,
            sampleRate: Int,
            channelCount: Int,
        ): Int

        @JvmStatic
        private external fun nativeSetTimelinePositionMs(
            streamSlot: Int,
            positionMs: Long,
        ): Int

        @JvmStatic
        private external fun nativeArmFade(
            streamSlot: Int,
            startPositionMs: Long,
            durationMs: Long,
            gamma: Float,
            outgoingTrim: Float,
            incomingTrim: Float,
            direction: Int,
        ): Int

        @JvmStatic
        private external fun nativeDisarmFade(streamSlot: Int): Int

        @JvmStatic
        private external fun nativeResetFade(streamSlot: Int): Int

        @JvmStatic
        private external fun nativeProcessFade(
            buffer: ByteBuffer,
            frameCount: Int,
            channelCount: Int,
            streamSlot: Int,
        ): Int

        @JvmStatic
        private external fun nativeIsConfigured(streamSlot: Int): Boolean

        @JvmStatic
        private external fun nativeHasFailed(streamSlot: Int): Boolean

        @JvmStatic
        private external fun nativeGetProcessedFrames(streamSlot: Int): Long

        @JvmStatic
        private external fun nativeGetProcessCalls(streamSlot: Int): Long

        @JvmStatic
        private external fun nativeGetCurrentGain(streamSlot: Int): Float

        internal fun setTimelinePositionMs(streamSlot: Int, positionMs: Long): Boolean {
            if (!nativeAvailability.canUse(NativeDspAudioProcessor.isLibraryAvailable) ||
                streamSlot !in 0..1 || positionMs < 0L
            ) return false
            return try {
                nativeSetTimelinePositionMs(streamSlot, positionMs) == 1
            } catch (_: LinkageError) {
                nativeAvailability.markUnavailable()
                false
            }
        }

        internal fun arm(
            streamSlot: Int,
            startPositionMs: Long,
            durationMs: Long,
            gamma: Float,
            outgoingTrim: Float,
            incomingTrim: Float,
            direction: Int,
        ): Boolean {
            if (!nativeAvailability.canUse(NativeDspAudioProcessor.isLibraryAvailable) ||
                streamSlot !in 0..1 || startPositionMs < 0L || durationMs <= 0L ||
                direction !in OUTGOING..INCOMING
            ) return false
            return try {
                nativeArmFade(
                    streamSlot,
                    startPositionMs,
                    durationMs,
                    normalizeGamma(gamma),
                    normalizeGain(outgoingTrim),
                    normalizeGain(incomingTrim),
                    direction,
                ) == 1
            } catch (_: LinkageError) {
                nativeAvailability.markUnavailable()
                false
            }
        }

        internal fun disarm(streamSlot: Int): Boolean {
            if (!nativeAvailability.canUse(NativeDspAudioProcessor.isLibraryAvailable) ||
                streamSlot !in 0..1
            ) return false
            return try {
                nativeDisarmFade(streamSlot) == 1
            } catch (_: LinkageError) {
                nativeAvailability.markUnavailable()
                false
            }
        }

        internal fun reset(streamSlot: Int): Boolean {
            if (!nativeAvailability.canUse(NativeDspAudioProcessor.isLibraryAvailable) ||
                streamSlot !in 0..1
            ) return false
            return try {
                nativeResetFade(streamSlot) == 1
            } catch (_: LinkageError) {
                nativeAvailability.markUnavailable()
                false
            }
        }

        internal fun isConfigured(streamSlot: Int): Boolean {
            if (!nativeAvailability.canUse(NativeDspAudioProcessor.isLibraryAvailable) ||
                streamSlot !in 0..1
            ) return false
            return try {
                nativeIsConfigured(streamSlot)
            } catch (_: LinkageError) {
                nativeAvailability.markUnavailable()
                false
            }
        }

        internal fun hasFailed(streamSlot: Int): Boolean {
            if (!nativeAvailability.canUse(NativeDspAudioProcessor.isLibraryAvailable) ||
                streamSlot !in 0..1
            ) return true
            return try {
                nativeHasFailed(streamSlot)
            } catch (_: LinkageError) {
                nativeAvailability.markUnavailable()
                true
            }
        }

        internal fun processedFrames(streamSlot: Int): Long {
            if (!nativeAvailability.canUse(NativeDspAudioProcessor.isLibraryAvailable) ||
                streamSlot !in 0..1
            ) return 0L
            return try {
                nativeGetProcessedFrames(streamSlot)
            } catch (_: LinkageError) {
                nativeAvailability.markUnavailable()
                0L
            }
        }

        internal fun processCalls(streamSlot: Int): Long {
            if (!nativeAvailability.canUse(NativeDspAudioProcessor.isLibraryAvailable) ||
                streamSlot !in 0..1
            ) return 0L
            return try {
                nativeGetProcessCalls(streamSlot)
            } catch (_: LinkageError) {
                nativeAvailability.markUnavailable()
                0L
            }
        }

        internal fun currentGain(streamSlot: Int): Float {
            if (!nativeAvailability.canUse(NativeDspAudioProcessor.isLibraryAvailable) ||
                streamSlot !in 0..1
            ) return 1f
            return try {
                nativeGetCurrentGain(streamSlot).takeIf { it.isFinite() } ?: 1f
            } catch (_: LinkageError) {
                nativeAvailability.markUnavailable()
                1f
            }
        }

        internal fun nativeAvailable(): Boolean =
            nativeAvailability.canUse(NativeDspAudioProcessor.isLibraryAvailable)

        private fun normalizeGain(value: Float): Float =
            if (value.isFinite()) value.coerceIn(0f, 1f) else 1f

        private fun normalizeGamma(value: Float): Float =
            if (value.isFinite()) value.coerceIn(0.6f, 1.6f) else 1f
    }

    @Volatile
    private var channelCount: Int = 0

    @Volatile
    private var runtimeFailed: Boolean = false

    val isConfigured: Boolean
        get() = channelCount > 0 && !runtimeFailed

    val processedFrameCount: Long
        get() = processedFrames(streamSlot)

    val processCallCount: Long
        get() = processCalls(streamSlot)

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        channelCount = 0
        runtimeFailed = false
        if (!nativeAvailable() ||
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT ||
            inputAudioFormat.channelCount !in 1..8 ||
            inputAudioFormat.sampleRate <= 0
        ) {
            return AudioProcessor.AudioFormat.NOT_SET
        }

        val configured = try {
            nativeConfigureFade(
                streamSlot,
                inputAudioFormat.sampleRate,
                inputAudioFormat.channelCount,
            ) == 1
        } catch (_: LinkageError) {
            nativeAvailability.markUnavailable()
            false
        }
        if (!configured) return AudioProcessor.AudioFormat.NOT_SET
        channelCount = inputAudioFormat.channelCount
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        val frameBytes = channelCount * Float.SIZE_BYTES
        if (remaining == 0 || frameBytes <= 0) return

        val alignedBytes = remaining - remaining % frameBytes
        if (alignedBytes <= 0) {
            inputBuffer.position(inputBuffer.limit())
            return
        }

        val output = replaceOutputBuffer(alignedBytes)
            .order(ByteOrder.nativeOrder())
        val input = inputBuffer.duplicate()
        input.limit(input.position() + alignedBytes)
        output.put(input)
        output.flip()

        if (nativeAvailable()) {
            val processed = try {
                nativeProcessFade(
                    output,
                    alignedBytes / frameBytes,
                    channelCount,
                    streamSlot,
                ) == 1
            } catch (_: LinkageError) {
                nativeAvailability.markUnavailable()
                false
            }
            if (!processed) runtimeFailed = true
        } else {
            runtimeFailed = true
        }
        inputBuffer.position(inputBuffer.limit())
    }

    @Deprecated("Deprecated by Media3; retained for BaseAudioProcessor lifecycle compatibility.")
    override fun onFlush() {
        reset(streamSlot)
    }

    override fun onReset() {
        reset(streamSlot)
        channelCount = 0
        runtimeFailed = false
    }
}

/** Owns one native fade processor per physical ExoPlayer slot. */
@UnstableApi
class AutomixFadeManager {
    private val processors = mutableMapOf<Int, AutomixFadeAudioProcessor>()
    private val lock = Any()

    fun createProcessor(streamSlot: Int): AutomixFadeAudioProcessor {
        val processor = AutomixFadeAudioProcessor(streamSlot)
        synchronized(lock) {
            processors[streamSlot] = processor
        }
        return processor
    }

    fun removeProcessor(processor: AutomixFadeAudioProcessor) {
        synchronized(lock) {
            processors.entries.removeIf { it.value === processor }
        }
        AutomixFadeAudioProcessor.reset(processor.streamSlot)
    }

    fun setTimelinePosition(streamSlot: Int, positionMs: Long): Boolean =
        AutomixFadeAudioProcessor.setTimelinePositionMs(streamSlot, positionMs)

    fun arm(
        outgoingSlot: Int,
        incomingSlot: Int,
        outgoingStartMs: Long,
        incomingStartMs: Long,
        durationMs: Long,
        gamma: Float,
        outgoingTrim: Float,
        incomingTrim: Float,
    ): Boolean {
        if (outgoingSlot == incomingSlot) return false
        val installed = synchronized(lock) {
            processors.containsKey(outgoingSlot) && processors.containsKey(incomingSlot)
        }
        if (!installed) return false
        val outgoingArmed = AutomixFadeAudioProcessor.arm(
            outgoingSlot,
            outgoingStartMs,
            durationMs,
            gamma,
            outgoingTrim,
            incomingTrim,
            AutomixFadeAudioProcessor.OUTGOING,
        )
        val incomingArmed = AutomixFadeAudioProcessor.arm(
            incomingSlot,
            incomingStartMs,
            durationMs,
            gamma,
            outgoingTrim,
            incomingTrim,
            AutomixFadeAudioProcessor.INCOMING,
        )
        return outgoingArmed && incomingArmed
    }

    fun isReady(outgoingSlot: Int, incomingSlot: Int): Boolean {
        val configured = synchronized(lock) {
            processors[outgoingSlot]?.isConfigured == true &&
                processors[incomingSlot]?.isConfigured == true
        }
        return configured &&
            AutomixFadeAudioProcessor.nativeAvailable() &&
            !AutomixFadeAudioProcessor.hasFailed(outgoingSlot) &&
            !AutomixFadeAudioProcessor.hasFailed(incomingSlot) &&
            AutomixFadeAudioProcessor.isConfigured(outgoingSlot) &&
            AutomixFadeAudioProcessor.isConfigured(incomingSlot)
    }

    fun hasProcessed(outgoingSlot: Int, incomingSlot: Int): Boolean {
        if (outgoingSlot == incomingSlot) return false
        val processed = synchronized(lock) {
            processors.containsKey(outgoingSlot) && processors.containsKey(incomingSlot)
        }
        return processed &&
            AutomixFadeAudioProcessor.processCalls(outgoingSlot) > 0L &&
            AutomixFadeAudioProcessor.processCalls(incomingSlot) > 0L &&
            !AutomixFadeAudioProcessor.hasFailed(outgoingSlot) &&
            !AutomixFadeAudioProcessor.hasFailed(incomingSlot)
    }

    fun currentGain(streamSlot: Int): Float =
        AutomixFadeAudioProcessor.currentGain(streamSlot)

    fun disarm(streamSlot: Int): Boolean =
        AutomixFadeAudioProcessor.disarm(streamSlot)

    fun reset(streamSlot: Int): Boolean =
        AutomixFadeAudioProcessor.reset(streamSlot)

    fun reset() {
        val slots = synchronized(lock) { processors.keys.toList() }
        slots.forEach { AutomixFadeAudioProcessor.reset(it) }
    }

    fun status(streamSlot: Int): String {
        if (!AutomixFadeAudioProcessor.nativeAvailable()) return "unavailable"
        val processor = synchronized(lock) { processors[streamSlot] }
            ?: return "unavailable"
        if (!processor.isConfigured || AutomixFadeAudioProcessor.hasFailed(streamSlot)) {
            return "unavailable"
        }
        return if (processor.processCallCount > 0L) "native" else "ready"
    }

}
