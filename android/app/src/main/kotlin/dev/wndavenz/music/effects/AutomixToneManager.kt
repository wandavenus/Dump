package dev.wndavenz.music.effects

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.exp

/**
 * Small, per-deck low-band gain stage for AutoMix bass swaps.
 *
 * This is not a full DJ isolator: it uses a smoothed one-pole low-pass
 * component and adjusts only that component, leaving the remaining spectrum
 * untouched. At gain=0 the estimated bass is suppressed; at gain=1 the input
 * is transparent. It is inserted in the PCM_FLOAT Media3 chain.
 */
@UnstableApi
class AutomixToneAudioProcessor : BaseAudioProcessor() {
    @Volatile
    private var targetBassGain: Float = 1f

    private var currentBassGain: Float = 1f
    private var lowPassState = FloatArray(0)
    private var sampleRateHz: Int = 0
    private var channelCount: Int = 0
    private var lowPassAlpha: Float = 0f
    private var gainSmoothingAlpha: Float = 0f

    fun setBassGain(gain: Float) {
        targetBassGain = if (gain.isFinite()) gain.coerceIn(0f, 1f) else 1f
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
        // 150 Hz one-pole low-pass; keep low-band gain automation smooth over ~20 ms.
        lowPassAlpha = (1.0 - exp(-2.0 * Math.PI * 150.0 / sampleRateHz)).toFloat()
        gainSmoothingAlpha = (1.0 - exp(-1.0 / (sampleRateHz * 0.020))).toFloat()
        currentBassGain = targetBassGain
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
        val gainAlpha = gainSmoothingAlpha

        repeat(frames) {
            val desiredGain = targetBassGain
            currentBassGain += (desiredGain - currentBassGain) * gainAlpha
            repeat(channelCount) { channel ->
                val sample = input.float
                val low = lowPassState[channel] +
                    alpha * (sample - lowPassState[channel])
                lowPassState[channel] = low
                val processed = sample + low * (currentBassGain - 1f)
                output.putFloat(if (processed.isFinite()) processed else 0f)
            }
        }
        output.flip()
        inputBuffer.position(inputBuffer.limit())
    }

    override fun onFlush() {
        lowPassState = FloatArray(channelCount.coerceAtLeast(0))
        currentBassGain = targetBassGain
    }

    override fun onReset() {
        lowPassState = FloatArray(0)
        sampleRateHz = 0
        channelCount = 0
        lowPassAlpha = 0f
        gainSmoothingAlpha = 0f
        currentBassGain = 1f
        targetBassGain = 1f
    }
}

/** Tracks bass-swap controls by physical player slot (primary=0, secondary=1). */
@UnstableApi
class AutomixToneManager {
    private val processors = mutableMapOf<Int, AutomixToneAudioProcessor>()
    private val targetGains = mutableMapOf<Int, Float>()
    private val lock = Any()

    fun createProcessor(streamSlot: Int): AutomixToneAudioProcessor {
        val processor = AutomixToneAudioProcessor()
        val target: Float
        synchronized(lock) {
            processors[streamSlot] = processor
            target = targetGains[streamSlot] ?: 1f
        }
        processor.setBassGain(target)
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

    fun reset() {
        val snapshot: List<Pair<Int, AutomixToneAudioProcessor>>
        synchronized(lock) {
            snapshot = processors.toList()
            targetGains.clear()
            for ((slot, _) in snapshot) targetGains[slot] = 1f
        }
        snapshot.forEach { (_, processor) -> processor.setBassGain(1f) }
    }
}
