package dev.wndavenz.music.effects

import androidx.media3.common.util.UnstableApi
import dev.wndavenz.music.events.NativeLogger

/**
 * Manages [EchoAudioProcessor] instances for the software echo (gema) effect.
 *
 * Same design as [StereoWidthManager]: every ExoPlayer instance (primary +
 * secondary for crossfade) gets its own [EchoAudioProcessor] embedded in its
 * DefaultAudioSink pipeline, and this manager tracks all live instances so a
 * single [setEcho] call updates every active player simultaneously — no race
 * between active and standby players during a crossfade overlap.
 *
 * Runs inside ExoPlayer's software audio pipeline (like stereo widening), so
 * it works during crossfade overlap and is unaffected by MIUI 12's sporadic
 * AudioSession publication delays.
 *
 * MONO / multi-channel audio: the processor reports NOT_SET in
 * [EchoAudioProcessor.onConfigure], so the effect is a transparent no-op.
 * TUNNELING: audio bypasses the software pipeline entirely — effects off.
 */
@UnstableApi
class EchoManager {

    var echoEnabled: Boolean = false
        private set

    var echoIntensity: Float = 0.5f
        private set

    private val processors = mutableListOf<EchoAudioProcessor>()
    private val lock = Any()

    fun createProcessor(): EchoAudioProcessor {
        val p = EchoAudioProcessor()
        p.setParams(echoEnabled, echoIntensity)
        synchronized(lock) { processors.add(p) }
        return p
    }

    fun removeProcessor(p: EchoAudioProcessor) {
        synchronized(lock) { processors.remove(p) }
    }

    fun setEcho(enabled: Boolean, intensity: Float = echoIntensity) {
        echoEnabled = enabled
        echoIntensity = intensity.coerceIn(0f, 1f)
        val snapshot: List<EchoAudioProcessor>
        synchronized(lock) { snapshot = processors.toList() }
        snapshot.forEach { it.setParams(echoEnabled, echoIntensity) }
        NativeLogger.emit(
            "info", "Echo",
            "echo=$enabled intensity=$echoIntensity " +
            "(active processors=${snapshot.size})",
        )
    }

    fun releaseAll() {
        synchronized(lock) { processors.clear() }
    }
}