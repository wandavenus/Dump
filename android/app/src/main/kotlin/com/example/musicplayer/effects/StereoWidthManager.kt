package com.example.musicplayer.effects

import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.ChannelMixingAudioProcessor
import androidx.media3.exoplayer.audio.ChannelMixingMatrix
import com.example.musicplayer.events.NativeLogger

/**
 * Manages ChannelMixingAudioProcessor instances for software stereo widening.
 *
 * Each ExoPlayer instance (primary + secondary for crossfade) gets its own
 * ChannelMixingAudioProcessor embedded in its DefaultAudioSink pipeline.
 * StereoWidthManager tracks all live instances so a single setStereoWidening()
 * call updates every active player simultaneously — no race between active
 * and standby players during crossfade overlap.
 *
 * WHY software widening instead of android.media.audiofx.Virtualizer:
 *   - Does NOT require a valid AudioSession from hardware — survives MIUI 12's
 *     sporadic AudioSession publication delays.
 *   - Runs in ExoPlayer's audio pipeline, not in AudioFlinger's effects chain,
 *     so it works correctly during crossfade overlap when two players share the
 *     same audio output device.
 *   - No retry-backoff needed; the processor is always attached from the moment
 *     the player is created.
 *
 * STEREO WIDENING MATRIX (2-ch stereo → 2-ch):
 *   width factor  w = 1.0 + strength × 0.5   (maps [0, 1] → [1.0, 1.5])
 *   L_out = ((1+w)/2) × L_in + ((1-w)/2) × R_in
 *   R_out = ((1-w)/2) × L_in + ((1+w)/2) × R_in
 *
 *   strength=0.0 → identity matrix (transparent, no processing)
 *   strength=0.5 → diag=1.125, cross=−0.125
 *   strength=1.0 → diag=1.25,  cross=−0.25 (25 % separation increase)
 *
 * MONO and multi-channel audio: no matrix is set for those combinations, so
 * the processor is a transparent no-op for mono and surround content.
 *
 * TUNNELING incompatibility: when tunneling is enabled, audio bypasses the
 * ExoPlayer software pipeline entirely, so this processor has no effect.
 * The UI should reflect this: tunneling = effects off.
 */
@UnstableApi
class StereoWidthManager {

    var stereoWideningEnabled: Boolean = false
        private set

    var stereoWideningStrength: Float = 0.5f
        private set

    private val processors = mutableListOf<ChannelMixingAudioProcessor>()
    private val lock = Any()

    fun createProcessor(): ChannelMixingAudioProcessor {
        val p = ChannelMixingAudioProcessor()
        applyMatrix(p, stereoWideningEnabled, stereoWideningStrength)
        synchronized(lock) { processors.add(p) }
        return p
    }

    fun removeProcessor(p: ChannelMixingAudioProcessor) {
        synchronized(lock) { processors.remove(p) }
    }

    fun setStereoWidening(enabled: Boolean, strength: Float = stereoWideningStrength) {
        stereoWideningEnabled = enabled
        stereoWideningStrength = strength.coerceIn(0f, 1f)
        val snapshot: List<ChannelMixingAudioProcessor>
        synchronized(lock) { snapshot = processors.toList() }
        snapshot.forEach { applyMatrix(it, enabled, stereoWideningStrength) }
        NativeLogger.emit(
            "info", "StereoWidth",
            "stereoWidening=$enabled strength=$stereoWideningStrength " +
            "(active processors=${snapshot.size})",
        )
    }

    fun releaseAll() {
        synchronized(lock) { processors.clear() }
    }

    private fun applyMatrix(
        processor: ChannelMixingAudioProcessor,
        enabled: Boolean,
        strength: Float,
    ) {
        val coefficients: FloatArray = if (!enabled) {
            floatArrayOf(1f, 0f, 0f, 1f)
        } else {
            val w     = 1f + strength * 0.5f
            val diag  = (1f + w) / 2f
            val cross = (1f - w) / 2f
            floatArrayOf(diag, cross, cross, diag)
        }
        try {
            processor.putChannelMixingMatrix(ChannelMixingMatrix(2, 2, coefficients))
        } catch (_: Exception) {
        }
    }
}
