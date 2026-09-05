package dev.wndavenz.music.effects

import androidx.media3.common.util.UnstableApi
import dev.wndavenz.music.events.NativeLogger

/**
 * Manages [ReverbAudioProcessor] instances for the software reverb effect.
 *
 * Same design as [StereoWidthManager]: every ExoPlayer instance (primary +
 * secondary for crossfade) gets its own [ReverbAudioProcessor] embedded in its
 * DefaultAudioSink pipeline, and this manager tracks all live instances so a
 * single [setReverb] call updates every active player simultaneously — no race
 * between active and standby players during a crossfade overlap.
 *
 * Runs inside ExoPlayer's software audio pipeline (like stereo widening), so
 * it works during crossfade overlap and is unaffected by MIUI 12's sporadic
 * AudioSession publication delays.
 *
 * MONO / multi-channel audio: the processor reports NOT_SET in
 * [ReverbAudioProcessor.onConfigure], so the effect is a transparent no-op.
 * TUNNELING: audio bypasses the software pipeline entirely — effects off.
 */
@UnstableApi
class ReverbManager {

    var reverbEnabled: Boolean = false
        private set

    var reverbIntensity: Float = 0.5f
        private set

    private val processors = mutableListOf<ReverbAudioProcessor>()
    private val lock = Any()

    fun createProcessor(): ReverbAudioProcessor {
        val p = ReverbAudioProcessor()
        p.setParams(reverbEnabled, reverbIntensity)
        synchronized(lock) { processors.add(p) }
        return p
    }

    fun removeProcessor(p: ReverbAudioProcessor) {
        synchronized(lock) { processors.remove(p) }
    }

    fun setReverb(enabled: Boolean, intensity: Float = reverbIntensity) {
        reverbEnabled = enabled
        reverbIntensity = intensity.coerceIn(0f, 1f)
        val snapshot: List<ReverbAudioProcessor>
        synchronized(lock) { snapshot = processors.toList() }
        snapshot.forEach { it.setParams(reverbEnabled, reverbIntensity) }
        NativeLogger.emit(
            "info", "Reverb",
            "reverb=$enabled intensity=$reverbIntensity " +
            "(active processors=${snapshot.size})",
        )
    }

    fun releaseAll() {
        synchronized(lock) { processors.clear() }
    }
}