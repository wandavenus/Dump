package dev.wndavenz.music.effects

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.exp

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
class AutomixToneAudioProcessor : BaseAudioProcessor() {
    @Volatile
    private var targetBassGain: Float = 1f

    @Volatile
    private var targetHighGain: Float = 1f

    private var currentBassGain: Float = 1f
    private var currentHighGain: Float = 1f
    private var lowPassState = FloatArray(0)
    private var highCutState = FloatArray(0)
    private var sampleRateHz: Int = 0
    private var channelCount: Int = 0
    private var lowPassAlpha: Float = 0f
    private var highCutAlpha: Float = 0f
    private var gainSmoothingAlpha: Float = 0f

    fun setBassGain(gain: Float) {
        targetBassGain = if (gain.isFinite()) gain.coerceIn(0f, 1f) else 1f
    }

    /**
     * High-band gain: 1 = transparent, 0 = the high band is removed entirely.
     * Applied on top of the bass swap, so both automations can run together.
     */
    fun setHighGain(gain: Float) {
        targetHighGain = if (gain.isFinite()) gain.coerceIn(0f, 1f) else 1f
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT ||
            inputAudioFormat.channelCount !in 1..8 ||
            inputAudioFormat.sampleRate <= 0
        ) {
            return AudioProcessor.AudioFormat.NOT_SET
        }

        sampleRateHz = inputAudioFormat.sampleRate
        channelCount = inputAudioFormat.channelCount
        lowPassState = FloatArray(channelCount)
        highCutState = FloatArray(channelCount)
        // 150 Hz one-pole low-pass for the bass swap, ~1.2 kHz for the high band;
        // keep both gain automations smooth over ~20 ms.
        lowPassAlpha = (1.0 - exp(-2.0 * Math.PI * 150.0 / sampleRateHz)).toFloat()
        highCutAlpha = (1.0 - exp(-2.0 * Math.PI * 1200.0 / sampleRateHz)).toFloat()
        gainSmoothingAlpha = (1.0 - exp(-1.0 / (sampleRateHz * 0.020))).toFloat()
        currentBassGain = targetBassGain
        currentHighGain = targetHighGain
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining < 4 || channelCount <= 0) return

        val input = inputBuffer.duplicate().order(ByteOrder.nativeOrder())
        val frames = remaining / (channelCount * 4)
        val output = replaceOutputBuffer(frames * channelCount * 4)
            .order(ByteOrder.nativeOrder())
        val alpha = lowPassAlpha
        val highAlpha = highCutAlpha
        val gainAlpha = gainSmoothingAlpha

        repeat(frames) {
            val desiredGain = targetBassGain
            val desiredHigh = targetHighGain
            currentBassGain += (desiredGain - currentBassGain) * gainAlpha
            currentHighGain += (desiredHigh - currentHighGain) * gainAlpha
            repeat(channelCount) { channel ->
                val sample = input.float
                val low = lowPassState[channel] +
                    alpha * (sample - lowPassState[channel])
                lowPassState[channel] = low
                val bassAdjusted = sample + low * (currentBassGain - 1f)
                // Split the bass-adjusted signal once more: the part below the
                // high cutoff passes through untouched, the part above it is
                // scaled by the tail filter. At highGain = 1 this is exactly
                // `bassAdjusted`, so an idle AutoMix deck stays transparent.
                val highLp = highCutState[channel] +
                    highAlpha * (bassAdjusted - highCutState[channel])
                highCutState[channel] = highLp
                val processed = highLp + (bassAdjusted - highLp) * currentHighGain
                output.putFloat(if (processed.isFinite()) processed else 0f)
            }
        }
        output.flip()
        inputBuffer.position(inputBuffer.limit())
    }

    override fun onFlush() {
        lowPassState = FloatArray(channelCount.coerceAtLeast(0))
        highCutState = FloatArray(channelCount.coerceAtLeast(0))
        currentBassGain = targetBassGain
        currentHighGain = targetHighGain
    }

    override fun onReset() {
        lowPassState = FloatArray(0)
        highCutState = FloatArray(0)
        sampleRateHz = 0
        channelCount = 0
        lowPassAlpha = 0f
        highCutAlpha = 0f
        gainSmoothingAlpha = 0f
        currentBassGain = 1f
        currentHighGain = 1f
        targetBassGain = 1f
        targetHighGain = 1f
    }
}

/** Tracks bass-swap and tail-filter controls by physical player slot (primary=0, secondary=1). */
@UnstableApi
class AutomixToneManager {
    private val processors = mutableMapOf<Int, AutomixToneAudioProcessor>()
    private val targetGains = mutableMapOf<Int, Float>()
    private val targetHighGains = mutableMapOf<Int, Float>()
    private val lock = Any()

    fun createProcessor(streamSlot: Int): AutomixToneAudioProcessor {
        val processor = AutomixToneAudioProcessor()
        val target: Float
        val highTarget: Float
        synchronized(lock) {
            processors[streamSlot] = processor
            target = targetGains[streamSlot] ?: 1f
            highTarget = targetHighGains[streamSlot] ?: 1f
        }
        processor.setBassGain(target)
        processor.setHighGain(highTarget)
        return processor
    }

    fun removeProcessor(processor: AutomixToneAudioProcessor) {
        synchronized(lock) {
            val slot = processors.entries.firstOrNull { it.value === processor }?.key
            if (slot != null) processors.remove(slot)
        }
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

    fun reset() {
        val snapshot: List<Pair<Int, AutomixToneAudioProcessor>>
        synchronized(lock) {
            snapshot = processors.toList()
            targetGains.clear()
            targetHighGains.clear()
            for ((slot, _) in snapshot) {
                targetGains[slot] = 1f
                targetHighGains[slot] = 1f
            }
        }
        snapshot.forEach { (_, processor) ->
            processor.setBassGain(1f)
            processor.setHighGain(1f)
        }
    }
}
