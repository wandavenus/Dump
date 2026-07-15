package dev.wndavenz.music.effects

import androidx.media3.common.util.UnstableApi
import dev.wndavenz.music.events.NativeLogger

/**
 * Manages [SignalsmithStretchAudioProcessor] instances (playback speed +
 * pitch shift), one per live ExoPlayer (primary + secondary/crossfade).
 *
 * Exactly the same rationale as [StereoWidthManager]: each ExoPlayer gets
 * its own processor instance embedded in its DefaultAudioSink pipeline
 * (Signalsmith Stretch's internal STFT state is not shareable across
 * threads), but the Dart-facing "setSpeed"/"setPitch" commands are a single
 * global setting from the user's point of view. StretchManager tracks every
 * live instance so one call updates all of them atomically — no race
 * between the active and standby player during crossfade overlap.
 *
 * NOTE on the Bit-Perfect dedicated player (createBitPerfectPlayer() in
 * Media3PlaybackService): that player intentionally has zero AudioProcessors
 * and must NEVER get a stretch processor registered here — Bit-Perfect mode
 * means "no processing whatsoever", so speed/pitch has no effect while it is
 * active, matching the pre-existing behaviour for every other effect.
 */
@UnstableApi
class StretchManager {

    var speed: Float = 1f
        private set

    var pitchSemitones: Float = 0f
        private set

    private val processors = mutableListOf<SignalsmithStretchAudioProcessor>()
    private val lock = Any()

    fun createProcessor(): SignalsmithStretchAudioProcessor {
        val p = SignalsmithStretchAudioProcessor()
        p.setSpeed(speed)
        p.setPitchSemitones(pitchSemitones)
        synchronized(lock) { processors.add(p) }
        return p
    }

    fun removeProcessor(p: SignalsmithStretchAudioProcessor) {
        synchronized(lock) { processors.remove(p) }
    }

    fun setSpeed(newSpeed: Float) {
        speed = if (newSpeed.isFinite() && newSpeed > 0f) newSpeed else 1f
        val snapshot: List<SignalsmithStretchAudioProcessor>
        synchronized(lock) { snapshot = processors.toList() }
        snapshot.forEach { it.setSpeed(speed) }
        NativeLogger.emit("info", "Stretch", "speed=$speed applied to ${snapshot.size} live processor(s)")
    }

    fun setPitchSemitones(newSemitones: Float) {
        pitchSemitones = if (newSemitones.isFinite()) newSemitones else 0f
        val snapshot: List<SignalsmithStretchAudioProcessor>
        synchronized(lock) { snapshot = processors.toList() }
        snapshot.forEach { it.setPitchSemitones(pitchSemitones) }
        NativeLogger.emit("info", "Stretch", "pitch=${pitchSemitones}st applied to ${snapshot.size} live processor(s)")
    }

    fun releaseAll() {
        synchronized(lock) { processors.clear() }
    }
}
