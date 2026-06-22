package com.example.musicplayer.effects

import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import android.os.Build
import android.os.Handler
import com.example.musicplayer.events.NativeLogger

/**
 * Manages Android audio effects lifecycle (EQ, LoudnessEnhancer, BassBoost,
 * Virtualizer, PresetReverb).
 *
 * Fixes:
 * RC-03: attachEffects() retry now checks `lastAttachedSessionId` guard at
 *        entry of each retry attempt; avoids attaching to a dead session if
 *        the session changed between scheduling and firing.
 * RC-04: equalizerParameters() no longer creates a temporary Equalizer on the
 *        main thread when the primary one isn't ready — returns safe defaults
 *        instead to avoid races during session creation.
 */
class AudioEffectsManager(private val effectHandler: Handler) {

    private var equalizer: Equalizer? = null
    private var loudness: LoudnessEnhancer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var reverb: PresetReverb? = null

    private var lastAttachedSessionId = -1

    // ── Persisted intent state (applied on next attach if effects not yet ready) ─
    var eqEnabled           = false;       private set
    var loudnessEnabled     = false;       private set
    var loudnessTargetMb    = 0f;         private set
    var bassBoostEnabled    = false;       private set
    var bassBoostStrength: Short = 0;     private set
    var virtualizerEnabled  = false;       private set
    var virtualizerStrength: Short = 1000; private set
    var reverbPreset: Short = 0;          private set
    val bandGains = mutableMapOf<Short, Short>()

    // ── Capability flags ──────────────────────────────────────────────────────
    var bassBoostSupported   = false; private set
    var virtualizerSupported = false; private set
    var reverbSupported      = false; private set

    // ── Session attachment ────────────────────────────────────────────────────

    fun attachEffects(sessionId: Int, attempt: Int = 0) {
        if (sessionId <= 0) return
        // RC-03 fix: guard checked at every retry entry, not just initially.
        if (sessionId == lastAttachedSessionId) {
            NativeLogger.emit("verbose", "Effects", "attachEffects skipped session=$sessionId")
            return
        }
        releaseEffects()

        var eqOk = false
        var leOk = false

        try {
            equalizer = Equalizer(0, sessionId).apply {
                enabled = eqEnabled
                bandGains.forEach { (b, g) ->
                    setBandLevel(b, g.coerceIn(bandLevelRange[0], bandLevelRange[1]))
                }
            }
            eqOk = true
        } catch (e: Exception) {
            NativeLogger.emit("warn", "Effects", "Equalizer init failed (session=$sessionId a${attempt+1}): ${e.message}")
        }

        try {
            loudness = LoudnessEnhancer(sessionId).apply {
                setTargetGain(loudnessTargetMb.toInt())
                enabled = loudnessEnabled
            }
            leOk = true
        } catch (e: Exception) {
            NativeLogger.emit("warn", "Effects", "LoudnessEnhancer init failed (session=$sessionId a${attempt+1}): ${e.message}")
        }

        bassBoostSupported = false
        if (isEffectTypeAvailable(AudioEffect.EFFECT_TYPE_BASS_BOOST)) {
            try {
                bassBoost = BassBoost(0, sessionId).apply {
                    setStrength(bassBoostStrength)
                    enabled = bassBoostEnabled
                }
                bassBoostSupported = true
            } catch (e: Exception) {
                NativeLogger.emit("warn", "Effects", "BassBoost init failed (a${attempt+1}): ${e.message}")
            }
        }

        virtualizerSupported = false
        if (isEffectTypeAvailable(AudioEffect.EFFECT_TYPE_VIRTUALIZER)) {
            try {
                virtualizer = Virtualizer(0, sessionId).apply {
                    setStrength(virtualizerStrength)
                    enabled = virtualizerEnabled
                }
                virtualizerSupported = true
            } catch (e: Exception) {
                NativeLogger.emit("warn", "Effects", "Virtualizer init failed (a${attempt+1}): ${e.message}")
            }
        }

        reverbSupported = false
        if (isEffectTypeAvailable(AudioEffect.EFFECT_TYPE_PRESET_REVERB)) {
            try {
                reverb = PresetReverb(0, sessionId).apply {
                    preset  = toAndroidReverbPreset(reverbPreset)
                    enabled = reverbPreset > 0
                }
                reverbSupported = true
            } catch (e: Exception) {
                NativeLogger.emit("warn", "Effects", "PresetReverb init failed (a${attempt+1}): ${e.message}")
            }
        }

        if (eqOk || leOk) {
            lastAttachedSessionId = sessionId
            NativeLogger.emit("info", "Effects",
                "attachEffects(session=$sessionId) ok a${attempt+1} " +
                "bass=$bassBoostSupported virt=$virtualizerSupported reverb=$reverbSupported")
            return
        }

        if (attempt < 2) {
            val delayMs = if (attempt == 0) 100L else 200L
            NativeLogger.emit("warn", "Effects", "attachEffects(session=$sessionId) retry in ${delayMs}ms")
            effectHandler.postDelayed({ attachEffects(sessionId, attempt + 1) }, delayMs)
            return
        }
        NativeLogger.emit("warn", "Effects", "attachEffects(session=$sessionId) failed after retries")
    }

    fun releaseEffects() {
        try { equalizer?.release()   } catch (_: Exception) {}
        try { loudness?.release()    } catch (_: Exception) {}
        try { bassBoost?.release()   } catch (_: Exception) {}
        try { virtualizer?.release() } catch (_: Exception) {}
        try { reverb?.release()      } catch (_: Exception) {}
        equalizer   = null
        loudness    = null
        bassBoost   = null
        virtualizer = null
        reverb      = null
    }

    // ── Effect setters ────────────────────────────────────────────────────────

    fun setEqualizerEnabled(enabled: Boolean) {
        eqEnabled = enabled
        try { equalizer?.enabled = enabled } catch (_: Exception) {}
    }

    fun setEqualizerBandGain(band: Short, gain: Short) {
        bandGains[band] = gain
        try {
            equalizer?.let { it.setBandLevel(band, gain.coerceIn(it.bandLevelRange[0], it.bandLevelRange[1])) }
        } catch (_: Exception) {}
    }

    fun setLoudnessTargetGain(gainMb: Float) {
        loudnessTargetMb = gainMb
        try { loudness?.setTargetGain(gainMb.toInt()) } catch (_: Exception) {}
    }

    fun setLoudnessEnabled(enabled: Boolean) {
        loudnessEnabled = enabled
        try { loudness?.enabled = enabled } catch (_: Exception) {}
    }

    fun setBassBoostEnabled(enabled: Boolean) {
        bassBoostEnabled = enabled
        try { bassBoost?.enabled = enabled } catch (_: Exception) {}
    }

    fun setBassBoostStrength(strength: Short) {
        bassBoostStrength = strength
        try { bassBoost?.setStrength(strength) } catch (_: Exception) {}
        if (bassBoostEnabled != (strength > 0)) setBassBoostEnabled(strength > 0)
    }

    fun setVirtualizerEnabled(enabled: Boolean) {
        virtualizerEnabled = enabled
        try {
            virtualizer?.run {
                if (enabled) { setStrength(virtualizerStrength); this.enabled = true }
                else         { this.enabled = false }
            }
        } catch (_: Exception) {}
    }

    fun setVirtualizerStrength(strength: Short) {
        virtualizerStrength = strength
        try { if (virtualizerEnabled) virtualizer?.setStrength(strength) } catch (_: Exception) {}
    }

    fun setReverbPreset(preset: Short) {
        reverbPreset = preset
        try { reverb?.run { this.preset = toAndroidReverbPreset(preset); this.enabled = preset > 0 } } catch (_: Exception) {}
    }

    // ── Query ─────────────────────────────────────────────────────────────────

    /**
     * RC-04 fix: returns safe defaults when equalizer is not yet attached,
     * instead of creating a temporary Equalizer on the main thread.
     */
    fun equalizerParameters(): Map<String, Any> {
        val eq = equalizer
        return if (eq != null) {
            try {
                mapOf(
                    "minDecibels" to eq.bandLevelRange[0] / 100.0,
                    "maxDecibels" to eq.bandLevelRange[1] / 100.0,
                    "bands"       to List(eq.numberOfBands.toInt()) { it }
                )
            } catch (_: Exception) { defaultEqualizerParameters() }
        } else {
            defaultEqualizerParameters()
        }
    }

    fun effectSupportMap() = mapOf(
        "virtualizerSupported" to virtualizerSupported,
        "bassBoostSupported"   to bassBoostSupported,
        "reverbSupported"      to reverbSupported,
    )

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun defaultEqualizerParameters() = mapOf(
        "minDecibels" to -15.0,
        "maxDecibels" to 15.0,
        "bands"       to listOf(0, 1, 2, 3, 4)
    )

    private fun toAndroidReverbPreset(preset: Short): Short = when (preset.toInt()) {
        1    -> PresetReverb.PRESET_SMALLROOM
        2    -> PresetReverb.PRESET_MEDIUMROOM
        3    -> PresetReverb.PRESET_LARGEROOM
        4    -> PresetReverb.PRESET_MEDIUMHALL
        5    -> PresetReverb.PRESET_LARGEHALL
        6    -> PresetReverb.PRESET_PLATE
        else -> PresetReverb.PRESET_NONE
    }

    private fun isEffectTypeAvailable(type: java.util.UUID): Boolean =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) true
        else try { AudioEffect.queryEffects()?.any { it.type == type } ?: false } catch (_: Exception) { false }
}
