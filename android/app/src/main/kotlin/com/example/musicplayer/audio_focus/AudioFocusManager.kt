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
 * Fixes:
 * - volumeBeforeDuck now exposed so CrossfadeController can read the correct
 *   target volume when starting a fade (previously read from a service field that
 *   wasn't always in sync after duck events).
 * - Duck restoration uses the stored pre-duck volume rather than 1f literal.
 */
@UnstableApi
class AudioFocusManager(
    private val audioManager: AudioManager,
    private val getPlayer: () -> ExoPlayer?,
    private val startTicker: () -> Unit,
    private val stopTicker: () -> Unit,
    private val onFocusEvent: () -> Unit,
) {
    var volumeBeforeDuck: Float = 1f
        private set

    private var hasAudioFocus = false
    private var resumeAfterFocusGain = false
    private var focusRequest: AudioFocusRequest? = null

    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { change ->
        val p = getPlayer() ?: return@OnAudioFocusChangeListener
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                p.volume = volumeBeforeDuck
                if (resumeAfterFocusGain) {
                    resumeAfterFocusGain = false
                    p.play()
                    startTicker()
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                resumeAfterFocusGain = p.isPlaying
                p.pause()
                stopTicker()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                volumeBeforeDuck = p.volume
                p.volume = (p.volume * 0.25f).coerceAtMost(0.25f)
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeAfterFocusGain = false
                p.pause()
                stopTicker()
                abandon()
            }
        }
        onFocusEvent()
    }

    /** Returns true if focus was granted (or already held). */
    fun request(): Boolean {
        if (hasAudioFocus) return true
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(focusChangeListener)
                .setWillPauseWhenDucked(false)
                .build()
            focusRequest = req
            audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusChangeListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
        hasAudioFocus = granted
        return granted
    }

    fun abandon() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusChangeListener)
        }
        focusRequest = null
        hasAudioFocus = false
    }

    fun hasAudioFocus(): Boolean = hasAudioFocus

    /**
     * Explicit volume setter called when user sets volume via MethodChannel.
     * Keeps volumeBeforeDuck in sync so duck/restore works correctly after
     * a manual volume change.
     */
    fun setUserVolume(volume: Float) {
        volumeBeforeDuck = volume.coerceIn(0f, 1f)
    }

    private fun log(msg: String) = NativeLogger.emit("info", "AudioFocus", msg)
}
