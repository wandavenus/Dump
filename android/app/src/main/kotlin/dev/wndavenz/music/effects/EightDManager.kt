package dev.wndavenz.music.effects

import androidx.media3.common.util.UnstableApi
import dev.wndavenz.music.events.NativeLogger

/**
 * Manages [EightDAudioProcessor] instances for the software 8D rotating effect.
 *
 * Same design as [StereoWidthManager]: every ExoPlayer instance (primary +
 * secondary for crossfade) gets its own [EightDAudioProcessor] embedded in its
 * DefaultAudioSink pipeline, and this manager tracks all live instances so a
 * single [setEightD] call updates every active player simultaneously — no race
 * between active and standby players during a crossfade overlap.
 *
 * Runs inside ExoPlayer's software audio pipeline (like stereo widening), so
 * it works during crossfade overlap and is unaffected by MIUI 12's sporadic
 * AudioSession publication delays.
 *
 * MONO / multi-channel audio: the processor reports NOT_SET in
 * [EightDAudioProcessor.onConfigure], so the effect is a transparent no-op.
 * TUNNELING: audio bypasses the software pipeline entirely — effects off.
 */
@UnstableApi
class EightDManager {

    var eightDEnabled: Boolean = false
        private set

    var eightDIntensity: Float = 0.5f
        private set

    private val processors = mutableListOf<EightDAudioProcessor>()
    private val lock = Any()

    fun createProcessor(): EightDAudioProcessor {
        val p = EightDAudioProcessor()
        p.setParams(eightDEnabled, eightDIntensity)
        synchronized(lock) { processors.add(p) }
        return p
    }

    fun removeProcessor(p: EightDAudioProcessor) {
        synchronized(lock) { processors.remove(p) }
    }

    fun setEightD(enabled: Boolean, intensity: Float = eightDIntensity) {
        eightDEnabled = enabled
        eightDIntensity = intensity.coerceIn(0f, 1f)
        val snapshot: List<EightDAudioProcessor>
        synchronized(lock) { snapshot = processors.toList() }
        snapshot.forEach { it.setParams(eightDEnabled, eightDIntensity) }
        NativeLogger.emit(
            "info", "EightD",
            "eightD=$enabled intensity=$eightDIntensity " +
            "(active processors=${snapshot.size})",
        )
    }

    fun releaseAll() {
        synchronized(lock) { processors.clear() }
    }
}