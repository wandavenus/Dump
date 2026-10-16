package dev.wndavenz.music.effects

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Small, per-deck tone stage for AutoMix: a low-band (bass swap) gain and a
 * high-band (tail filter-out) gain.
 *
 * This is not a full DJ isolator. It estimates two bands with smoothed one-pole
 * low-pass filters — a 150 Hz component for the bass swap and a ~1.2 kHz
 * component for the high band — and adjusts only those components:
 *
 *   out = highLp + (bassAdjusted - highLp) * highGain,  bassAdjusted = in + low * (bassGain - 1)
 *
 * At `bassGain = 0` the estimated bass is suppressed; at `highGain = 1` the input
 * is bit-transparent (the high component is untouched); at `highGain < 1` the
 * deck dulls gently, which is what makes the outgoing tail hand over smoothly
 * instead of being cut off. It is inserted in the PCM_FLOAT Media3 chain.
 */
@UnstableApi
class AutomixToneAudioProcessor(
    private val streamSlot: Int,
) : BaseAudioProcessor() {
    companion object {
        @JvmStatic
        private external fun nativeConfigureTone(
            streamSlot: Int,
            sampleRate: Int,
            channelCount: Int,
        ): Int

        @JvmStatic
        private external fun nativeSetBassGain(streamSlot: Int, gain: Float): Int

        @JvmStatic
        private external fun nativeSetMidGain(streamSlot: Int, gain: Float): Int

        @JvmStatic
        private external fun nativeSetHighGain(streamSlot: Int, gain: Float): Int

        @JvmStatic
        private external fun nativeSetFadeGain(streamSlot: Int, gain: Float): Int

        @JvmStatic
        private external fun nativeSetCrossfadeGains(
            outgoingSlot: Int,
            incomingSlot: Int,
            progress: Float,
            gamma: Float,
            outgoingTrim: Float,
            incomingTrim: Float,
        ): Int

        @JvmStatic
        private external fun nativeProcessTone(
            buffer: ByteBuffer,
            frameCount: Int,
            channelCount: Int,
            streamSlot: Int,
        ): Int

        @JvmStatic
        private external fun nativeResetTone(streamSlot: Int): Int

        internal fun setNativeFadeGain(streamSlot: Int, gain: Float): Boolean {
            if (!NativeDspAudioProcessor.isLibraryAvailable) return false
            return try {
                nativeSetFadeGain(streamSlot, normalizeGain(gain)) == 1
            } catch (_: LinkageError) {
                false
            }
        }

        internal fun setNativeCrossfadeGains(
            outgoingSlot: Int,
            incomingSlot: Int,
            progress: Float,
            gamma: Float,
            outgoingTrim: Float,
            incomingTrim: Float,
        ): Boolean {
            if (!NativeDspAudioProcessor.isLibraryAvailable) return false
            return try {
                nativeSetCrossfadeGains(
                    outgoingSlot,
                    incomingSlot,
                    progress,
                    gamma,
                    outgoingTrim,
                    incomingTrim,
                ) == 1
            } catch (_: LinkageError) {
                false
            }
        }

        private fun normalizeGain(gain: Float): Float =
            if (gain.isFinite()) gain.coerceIn(0f, 1f) else 1f
    }

    @Volatile
    private var channelCount: Int = 0

    val isConfigured: Boolean
        get() = channelCount > 0

    fun setBassGain(gain: Float) {
        if (NativeDspAudioProcessor.isLibraryAvailable) {
            nativeSetBassGain(streamSlot, normalizeGain(gain))
        }
    }

    fun setMidGain(gain: Float) {
        if (NativeDspAudioProcessor.isLibraryAvailable) {
            nativeSetMidGain(streamSlot, normalizeGain(gain))
        }
    }

    fun setHighGain(gain: Float) {
        if (NativeDspAudioProcessor.isLibraryAvailable) {
            nativeSetHighGain(streamSlot, normalizeGain(gain))
        }
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        channelCount = 0
        if (!NativeDspAudioProcessor.isLibraryAvailable ||
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT ||
            inputAudioFormat.channelCount !in 1..8 ||
            inputAudioFormat.sampleRate <= 0
        ) {
            return AudioProcessor.AudioFormat.NOT_SET
        }

        val configuredChannelCount = inputAudioFormat.channelCount
        if (nativeConfigureTone(
                streamSlot,
                inputAudioFormat.sampleRate,
                configuredChannelCount,
            ) != 1
        ) {
            channelCount = 0
            return AudioProcessor.AudioFormat.NOT_SET
        }
        channelCount = configuredChannelCount
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        val frameBytes = channelCount * Float.SIZE_BYTES
        if (remaining == 0 || channelCount <= 0 || frameBytes <= 0) return

        // PCM buffers should be frame-aligned. Preserve any malformed trailing
        // bytes instead of passing a partial frame to the native processor.
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

        if (NativeDspAudioProcessor.isLibraryAvailable) {
            // BaseAudioProcessor provides a direct output buffer. C processes
            // it in-place, with the stereo path vectorized using ARM64 NEON.
            nativeProcessTone(
                output,
                alignedBytes / frameBytes,
                channelCount,
                streamSlot,
            )
        }
        inputBuffer.position(inputBuffer.position() + alignedBytes)
    }

    override fun onFlush() {
        resetNativeState()
    }

    override fun onReset() {
        resetNativeState()
        channelCount = 0
    }

    private fun normalizeGain(gain: Float): Float =
        if (gain.isFinite()) gain.coerceIn(0f, 1f) else 1f

    private fun resetNativeState() {
        if (NativeDspAudioProcessor.isLibraryAvailable) {
            nativeResetTone(streamSlot)
        }
    }
}

/** Tracks per-band isolator controls by physical player slot (primary=0, secondary=1). */
@UnstableApi
class AutomixToneManager {
    private val processors = mutableMapOf<Int, AutomixToneAudioProcessor>()
    private val targetGains = mutableMapOf<Int, Float>()
    private val targetMidGains = mutableMapOf<Int, Float>()
    private val targetHighGains = mutableMapOf<Int, Float>()
    private val lock = Any()

    fun createProcessor(streamSlot: Int): AutomixToneAudioProcessor {
        val processor = AutomixToneAudioProcessor(streamSlot)
        val target: Float
        val midTarget: Float
        val highTarget: Float
        synchronized(lock) {
            processors[streamSlot] = processor
            target = targetGains[streamSlot] ?: 1f
            midTarget = targetMidGains[streamSlot] ?: 1f
            highTarget = targetHighGains[streamSlot] ?: 1f
        }
        processor.setBassGain(target)
        processor.setMidGain(midTarget)
        processor.setHighGain(highTarget)
        return processor
    }

    fun removeProcessor(processor: AutomixToneAudioProcessor) {
        var removedSlot: Int? = null
        synchronized(lock) {
            val slot = processors.entries.firstOrNull { it.value === processor }?.key
            if (slot != null) {
                processors.remove(slot)
                removedSlot = slot
            }
        }
        removedSlot?.let { AutomixToneAudioProcessor.setNativeFadeGain(it, 1f) }
    }

    fun setBassGain(streamSlot: Int, gain: Float) {
        val normalized = if (gain.isFinite()) gain.coerceIn(0f, 1f) else 1f
        val processor: AutomixToneAudioProcessor?
        synchronized(lock) {
            targetGains[streamSlot] = normalized
            processor = processors[streamSlot]
        }
        processor?.setBassGain(normalized)
    }

    /** Mid-band gain for one deck: 1 = transparent, 0 = mid band removed. */
    fun setMidGain(streamSlot: Int, gain: Float) {
        val normalized = if (gain.isFinite()) gain.coerceIn(0f, 1f) else 1f
        val processor: AutomixToneAudioProcessor?
        synchronized(lock) {
            targetMidGains[streamSlot] = normalized
            processor = processors[streamSlot]
        }
        processor?.setMidGain(normalized)
    }

    /** High-band gain for one deck: 1 = transparent, 0 = high band removed. */
    fun setHighGain(streamSlot: Int, gain: Float) {
        val normalized = if (gain.isFinite()) gain.coerceIn(0f, 1f) else 1f
        val processor: AutomixToneAudioProcessor?
        synchronized(lock) {
            targetHighGains[streamSlot] = normalized
            processor = processors[streamSlot]
        }
        processor?.setHighGain(normalized)
    }

    /** Sets both decks' equal-power transfer targets in the native tone stage. */
    fun setCrossfadeGains(
        outgoingSlot: Int,
        incomingSlot: Int,
        progress: Float,
        gamma: Float,
        outgoingTrim: Float,
        incomingTrim: Float,
    ): Boolean {
        if (outgoingSlot == incomingSlot) return false
        val bothConfigured = synchronized(lock) {
            processors[outgoingSlot]?.isConfigured == true &&
                processors[incomingSlot]?.isConfigured == true
        }
        if (!bothConfigured) return false
        return AutomixToneAudioProcessor.setNativeCrossfadeGains(
            outgoingSlot,
            incomingSlot,
            progress,
            gamma,
            outgoingTrim,
            incomingTrim,
        )
    }

    fun setFadeGain(streamSlot: Int, gain: Float) {
        AutomixToneAudioProcessor.setNativeFadeGain(streamSlot, gain)
    }

    fun reset() {
        val snapshot: List<Pair<Int, AutomixToneAudioProcessor>>
        synchronized(lock) {
            snapshot = processors.toList()
            targetGains.clear()
            targetMidGains.clear()
            targetHighGains.clear()
            for ((slot, _) in snapshot) {
                targetGains[slot] = 1f
                targetMidGains[slot] = 1f
                targetHighGains[slot] = 1f
            }
        }
        snapshot.forEach { (slot, processor) ->
            processor.setBassGain(1f)
            processor.setMidGain(1f)
            processor.setHighGain(1f)
            setFadeGain(slot, 1f)
        }
    }
}
