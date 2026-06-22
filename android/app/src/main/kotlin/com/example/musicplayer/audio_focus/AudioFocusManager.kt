package com.example.musicplayer.audio_focus

import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.events.NativeLogger

/**
 * Manages Android audio focus lifecycle.
 *
 * Improvements over previous version:
 *
 * MIUI 12 / Android 11:
 *   - setAcceptsDelayedFocusGain(true) on API 26+: MIUI sometimes grants focus
 *     asynchronously (AUDIOFOCUS_REQUEST_DELAYED).  With delayed-gain enabled the
 *     system notifies us via AUDIOFOCUS_GAIN when focus becomes available instead
 *     of silently failing.
 *   - Separate handling of AUDIOFOCUS_REQUEST_DELAYED result (return true so the
 *     caller can proceed to call player.play() speculatively; the listener will
 *     handle the gain event gracefully).
 *
 * Crossfade-aware ducking:
 *   - getCrossfadeInProgress lambda (passed at construction): when true, the duck
 *     handler skips updating volumeBeforeDuck so it retains the full pre-fade target
 *     volume rather than a mid-fade value (e.g. 0.3).  This prevents broken volume
 *     restoration after the duck ends.
 *   - AUDIOFOCUS_LOSS_TRANSIENT during crossfade: the active (new) player is paused
 *     and resumeAfterFocusGain is set; the caller (noisyReceiver / service) is
 *     responsible for calling CrossfadeController.cancel() to clean up the old player.
 *
 * Volume tracking:
 *   - volumeBeforeDuck: exposed so CrossfadeController uses the correct target vol.
 *   - Duck factor is 0.2 (−14 dB) — perceptible as a clear background level rather
 *     than the old 0.25 which was barely audible on some MIUI device profiles.
 */
@UnstableApi
class AudioFocusManager(
    private val audioManager: AudioManager,
    private val getPlayer:    () -> ExoPlayer?,
    private val startTicker:  () -> Unit,
    private val stopTicker:   () -> Unit,
    private val onFocusEvent: () -> Unit,
    /**
     * Lambda that returns true while a crossfade is in progress.
     * Used to guard the duck handler: during crossfade the active player's volume
     * is in mid-fade (e.g. 0.3) so we must not save that as the volumeBeforeDuck
     * target — otherwise restoration after duck would leave the player at the
     * mid-fade level instead of full volume.
     */
    private val getCrossfadeInProgress: () -> Boolean = { false },
) {
    var volumeBeforeDuck: Float = 1f
        private set

    private var _hasAudioFocus        = false
    private var resumeAfterFocusGain  = false
    private var focusRequest: AudioFocusRequest? = null

    // ── Focus change listener ─────────────────────────────────────────────────

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        val p = getPlayer() ?: return@OnAudioFocusChangeListener
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK -> {
                _hasAudioFocus = true
                // Restore volume to pre-duck level
                p.volume = volumeBeforeDuck.coerceIn(0f, 1f)
                if (resumeAfterFocusGain) {
                    resumeAfterFocusGain = false
                    p.play()
                    startTicker()
                    log("AUDIOFOCUS_GAIN → resumed playback")
                } else {
                    log("AUDIOFOCUS_GAIN → volume restored")
                }
            }

            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                // During crossfade the active player's volume is mid-fade (e.g. 0.3).
                // Saving that as volumeBeforeDuck would cause broken restoration after
                // the duck ends.  Only update the target when NOT in a crossfade.
                if (!getCrossfadeInProgress()) {
                    volumeBeforeDuck = p.volume.coerceIn(0.01f, 1f)
                }
                // Duck to 20% of the pre-duck target (–14 dB).
                p.volume = (volumeBeforeDuck * 0.2f).coerceIn(0f, 0.2f)
                log("AUDIOFOCUS_DUCK → ${p.volume} (crossfade=${getCrossfadeInProgress()})")
            }

            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_EXCLUSIVE -> {
                resumeAfterFocusGain = p.isPlaying
                p.pause()
                stopTicker()
                log("AUDIOFOCUS_LOSS_TRANSIENT → paused (will resume=$resumeAfterFocusGain)")
            }

            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeAfterFocusGain = false
                p.pause()
                stopTicker()
                abandon()
                log("AUDIOFOCUS_LOSS → stopped and abandoned focus")
            }
        }
        onFocusEvent()
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Request audio focus.  Returns true if focus is granted (or already held,
     * or the request is pending/delayed on MIUI 12).
     */
    fun request(): Boolean {
        if (_hasAudioFocus) return true

        val granted: Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(focusListener)
                .setWillPauseWhenDucked(false)
                .setAcceptsDelayedFocusGain(true)   // MIUI 12: async grant
                .build()
            focusRequest = req
            val result = audioManager.requestAudioFocus(req)
            // AUDIOFOCUS_REQUEST_DELAYED counts as "will get focus" — proceed
            result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED ||
            result == AudioManager.AUDIOFOCUS_REQUEST_DELAYED
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
        _hasAudioFocus = granted
        log("requestAudioFocus → granted=$granted")
        return granted
    }

    fun abandon() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
        focusRequest       = null
        _hasAudioFocus     = false
        resumeAfterFocusGain = false
        log("abandonAudioFocus")
    }

    fun hasAudioFocus(): Boolean = _hasAudioFocus

    /**
     * Called when the user explicitly sets the volume via MethodChannel.
     * Keeps volumeBeforeDuck in sync so duck/restore works correctly after a
     * manual volume change.
     */
    fun setUserVolume(volume: Float) {
        volumeBeforeDuck = volume.coerceIn(0f, 1f)
        log("setUserVolume: $volumeBeforeDuck")
    }

    private fun log(msg: String) = NativeLogger.emit("info", "AudioFocus", msg)
}
