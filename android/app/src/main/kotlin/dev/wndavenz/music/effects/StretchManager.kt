package dev.wndavenz.music.effects

import androidx.media3.common.util.UnstableApi
import dev.wndavenz.music.events.NativeLogger
import java.util.Timer
import kotlin.concurrent.scheduleAtFixedRate

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

    private var speedTarget: Float = 1f
    private var pitchTarget: Float = 0f
    private var smoothingTimer: Timer? = null

    private val tickMs: Long = 24L
    private val smoothingFactor: Float = 0.08f
    private val settleEpsilon: Float = 0.0015f

    fun createProcessor(): SignalsmithStretchAudioProcessor {
        val p = SignalsmithStretchAudioProcessor()
        p.setSpeed(speed)
        p.setPitchSemitones(pitchSemitones)
        val count: Int
        synchronized(lock) {
            processors.add(p)
            count = processors.size
        }
        NativeLogger.emit(
            "info", "Stretch",
            "[Stretch] processor created hash=${System.identityHashCode(p)} count=$count speed=$speed pitch=${pitchSemitones}st",
        )
        return p
    }

    fun removeProcessor(p: SignalsmithStretchAudioProcessor) {
        val count: Int
        synchronized(lock) {
            processors.remove(p)
            count = processors.size
        }
        NativeLogger.emit("info", "Stretch", "[Stretch] processor destroyed hash=${System.identityHashCode(p)} count=$count")
    }

    fun setSpeed(newSpeed: Float) {
        speedTarget = if (newSpeed.isFinite() && newSpeed > 0f) newSpeed else 1f
        ensureSmoothingLoop()
    }

    fun setPitchSemitones(newSemitones: Float) {
        pitchTarget = if (newSemitones.isFinite()) newSemitones else 0f
        ensureSmoothingLoop()
    }

    private fun ensureSmoothingLoop() {
        synchronized(lock) {
            if (smoothingTimer != null) return
            smoothingTimer = Timer("StretchManager", /* isDaemon = */ true).apply {
                scheduleAtFixedRate(0L, tickMs) {
                    val snapshot: List<SignalsmithStretchAudioProcessor>
                    val currentSpeed: Float
                    val currentPitch: Float
                    val targetSpeed: Float
                    val targetPitch: Float

                    synchronized(lock) {
                        speed = stepToward(speed, speedTarget, smoothingFactor)
                        pitchSemitones = stepToward(pitchSemitones, pitchTarget, smoothingFactor)

                        snapshot = processors.toList()
                        currentSpeed = speed
                        currentPitch = pitchSemitones
                        targetSpeed = speedTarget
                        targetPitch = pitchTarget

                        if (absDiff(currentSpeed, targetSpeed) <= settleEpsilon &&
                            absDiff(currentPitch, targetPitch) <= settleEpsilon
                        ) {
                            smoothingTimer?.cancel()
                            smoothingTimer = null
                        }
                    }

                    snapshot.forEach { p ->
                        p.setSpeed(currentSpeed)
                        p.setPitchSemitones(currentPitch)
                    }

                    NativeLogger.emit(
                        "info", "Stretch",
                        "[Stretch] smoothed update speed=$currentSpeed pitch=${currentPitch}st targetSpeed=$targetSpeed targetPitch=${targetPitch}st appliedTo=${snapshot.size}",
                    )
                }
            }
        }
    }

    private fun stepToward(current: Float, target: Float, factor: Float): Float {
        val next = current + (target - current) * factor
        return when {
            absDiff(next, target) <= settleEpsilon -> target
            else -> next
        }
    }

    private fun absDiff(a: Float, b: Float): Float = kotlin.math.abs(a - b)

    fun releaseAll() {
        synchronized(lock) {
            smoothingTimer?.cancel()
            smoothingTimer = null
            processors.clear()
        }
        NativeLogger.emit("info", "Stretch", "[Stretch] releaseAll — all processors cleared count=0")
    }
}
