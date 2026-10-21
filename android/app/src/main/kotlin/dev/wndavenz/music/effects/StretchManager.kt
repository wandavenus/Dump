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

    // The two Media3 players occupy stable physical slots (primary=0,
    // secondary=1). Track each processor by slot so AutoMix can tempo-match
    // only the incoming deck without touching the currently playing deck.
    private val processors = mutableMapOf<Int, SignalsmithStretchAudioProcessor>()
    private val autoMixMultipliers = mutableMapOf<Int, Float>()
    // Additive AutoMix key shift per physical slot (0 = none). It is applied on
    // top of the user's global pitch setting and only during an overlap.
    private val autoMixPitchSemitones = mutableMapOf<Int, Float>()
    private val lock = Any()

    private var speedTarget: Float = 1f
    private var pitchTarget: Float = 0f
    private var smoothingTimer: Timer? = null

    private val tickMs: Long = 16L
    private val smoothingFactor: Float = 0.05f
    private val settleEpsilon: Float = 0.001f

    fun createProcessor(streamSlot: Int): SignalsmithStretchAudioProcessor {
        val p = SignalsmithStretchAudioProcessor()
        val multiplier: Float
        val pitchOffset: Float
        val basePitch: Float
        val count: Int
        synchronized(lock) {
            multiplier = autoMixMultipliers[streamSlot] ?: 1f
            pitchOffset = autoMixPitchSemitones[streamSlot] ?: 0f
            basePitch = pitchSemitones
            processors[streamSlot] = p
            count = processors.size
        }
        p.setSpeed(speed)
        p.setPitchSemitones(basePitch + pitchOffset)
        p.setAutoMixTempoMultiplier(multiplier)
        NativeLogger.emit(
            "info", "Stretch",
            "[Stretch] processor created slot=$streamSlot hash=${System.identityHashCode(p)} count=$count speed=$speed autoMix=$multiplier pitch=${basePitch + pitchOffset}st (base=$basePitch autoMixPitch=$pitchOffset)",
        )
        return p
    }

    fun removeProcessor(p: SignalsmithStretchAudioProcessor) {
        val slot: Int?
        val count: Int
        synchronized(lock) {
            slot = processors.entries.firstOrNull { it.value === p }?.key
            if (slot != null) processors.remove(slot)
            count = processors.size
        }
        NativeLogger.emit("info", "Stretch", "[Stretch] processor destroyed slot=$slot hash=${System.identityHashCode(p)} count=$count")
    }

    /** Applies a bounded pitch-preserving tempo correction to only one deck. */
    fun setAutoMixTempoMultiplier(streamSlot: Int, multiplier: Float) {
        val normalized = if (multiplier.isFinite()) multiplier.coerceIn(0.92f, 1.08f) else 1f
        val processor: SignalsmithStretchAudioProcessor?
        synchronized(lock) {
            autoMixMultipliers[streamSlot] = normalized
            processor = processors[streamSlot]
        }
        processor?.setAutoMixTempoMultiplier(normalized)
        NativeLogger.emit("info", "Stretch", "[Stretch] AutoMix deck slot=$streamSlot multiplier=$normalized")
    }

    /**
     * Adds a temporary per-deck pitch offset (semitones) on top of the user's
     * global pitch setting. AutoMix uses ±1 semitone on the outgoing deck only;
     * 0 clears the offset.
     */
    fun setAutoMixPitchSemitones(streamSlot: Int, semitones: Float) {
        val normalized = if (semitones.isFinite()) semitones.coerceIn(-1f, 1f) else 0f
        val processor: SignalsmithStretchAudioProcessor?
        val basePitch: Float
        synchronized(lock) {
            if (normalized == 0f) {
                autoMixPitchSemitones.remove(streamSlot)
            } else {
                autoMixPitchSemitones[streamSlot] = normalized
            }
            processor = processors[streamSlot]
            basePitch = pitchSemitones
        }
        processor?.setPitchSemitones(basePitch + normalized)
        NativeLogger.emit(
            "info", "Stretch",
            "[Stretch] AutoMix pitch slot=$streamSlot offset=${normalized}st base=${basePitch}st",
        )
    }

    /**
     * Returns the speed currently applied by this deck's processing chain.
     * This is intentionally the processor's smoothed value, not only the target.
     */
    fun effectivePlaybackSpeed(streamSlot: Int): Float {
        val processor = synchronized(lock) { processors[streamSlot] }
        return processor?.effectivePlaybackSpeed() ?: 1f
    }

    fun setSpeed(newSpeed: Float) {
        // Written under the same lock the smoothing timer reads it with, so a
        // committed slider value cannot be missed (which would let the timer
        // settle early on a stale target).
        synchronized(lock) {
            speedTarget = if (newSpeed.isFinite() && newSpeed > 0f) newSpeed else 1f
        }
        ensureSmoothingLoop()
    }

    fun setPitchSemitones(newSemitones: Float) {
        synchronized(lock) {
            pitchTarget = if (newSemitones.isFinite()) newSemitones else 0f
        }
        ensureSmoothingLoop()
    }

    private fun ensureSmoothingLoop() {
        synchronized(lock) {
            if (smoothingTimer != null) return
            smoothingTimer = Timer("StretchManager", /* isDaemon = */ true).apply {
                scheduleAtFixedRate(0L, tickMs) {
                    val snapshot: List<Pair<Int, SignalsmithStretchAudioProcessor>>
                    val pitchOffsets: Map<Int, Float>
                    val currentSpeed: Float
                    val currentPitch: Float
                    val targetSpeed: Float
                    val targetPitch: Float

                    synchronized(lock) {
                        speed = stepToward(speed, speedTarget, smoothingFactor)
                        pitchSemitones = stepToward(pitchSemitones, pitchTarget, smoothingFactor)

                        snapshot = processors.entries.map { it.key to it.value }
                        pitchOffsets = autoMixPitchSemitones.toMap()
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

                    snapshot.forEach { (slot, p) ->
                        p.setSpeed(currentSpeed)
                        p.setPitchSemitones(currentPitch + (pitchOffsets[slot] ?: 0f))
                    }
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
            autoMixMultipliers.clear()
            autoMixPitchSemitones.clear()
        }
        NativeLogger.emit("info", "Stretch", "[Stretch] releaseAll — all processors cleared count=0")
    }
}
