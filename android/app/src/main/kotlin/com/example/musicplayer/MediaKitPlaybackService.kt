package com.example.musicplayer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.example.musicplayer.notification.PlaybackNotificationManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MediaKit foreground playback service.
 *
 * Mirrors the role of [Media3PlaybackService] but for the MediaKit engine.
 * This service does NOT produce audio — MediaKit drives audio entirely on the
 * Dart side via media_kit. This service exists to:
 *   1. Hold a [MediaSession] so the OS sees an active media player.
 *   2. Display the playback notification via [PlaybackNotificationManager].
 *   3. Request and release audio focus.
 *   4. Forward transport commands from the system (lock screen, BT, notification
 *      buttons) back to Flutter via [MediaKitEventEmitter].
 *
 * Lifecycle (Dart-driven):
 *   • Dart calls "startService" → [MainActivity] calls startForegroundService().
 *   • Dart calls "updateMetadata" / "updatePlaybackState" → [handle] updates the
 *     [MediaKitStatePlayer] and notification.
 *   • Dart calls "release" → service stops foreground and calls [stopSelf].
 *
 * Transport button flow:
 *   Lock screen / BT / notification → [onStartCommand] or [MediaKitStatePlayer]
 *   callback → [MediaKitEventEmitter.emitTransport] → Dart EventChannel
 *   → [MediaKitServiceBridge] handler → [MediaKitEngine.play/pause/…].
 */
@OptIn(UnstableApi::class)
class MediaKitPlaybackService : MediaSessionService() {

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var statePlayer: MediaKitStatePlayer
    private var session: MediaSession? = null
    private lateinit var notificationManager: PlaybackNotificationManager

    // Playback state mirrored from Dart; kept in sync so the notification and
    // state player always reflect the latest values.
    private var currentTitle    = ""
    private var currentArtist   = ""
    private var currentArtUri:  String? = null
    private var currentDuration = 0L
    private var currentPlaying  = false
    private var currentPosition = 0L

    // Audio focus (minSdk = 29 → always API 26+ path)
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var hasAudioFocus = false

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                currentPlaying = false
                statePlayer.updatePlaybackState(false, currentPosition)
                refreshIfVisible()
                MediaKitEventEmitter.emitTransport("pause")
            }
            // AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK: keep playing but let the OS duck volume.
            // We do not pause on duck — the user can still hear the music at reduced volume.
        }
    }

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                currentPlaying = false
                statePlayer.updatePlaybackState(false, currentPosition)
                refreshIfVisible()
                MediaKitEventEmitter.emitTransport("pause")
            }
        }
    }

    companion object {
        /** Non-null while this service instance is alive. */
        @Volatile var instance: MediaKitPlaybackService? = null
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        instance     = this
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        statePlayer = MediaKitStatePlayer(
            onPlay     = { requestFocusThenEmit("play") },
            onPause    = { updateStateAndEmit(playing = false, action = "pause") },
            onSkipNext = { MediaKitEventEmitter.emitTransport("next") },
            onSkipPrev = { MediaKitEventEmitter.emitTransport("previous") },
            onSeek     = { pos -> MediaKitEventEmitter.emitTransport("seek", pos) },
        )

        // Build the session. Attach the app's launch intent so tapping the
        // notification opens the Flutter UI.
        val sessionBuilder = MediaSession.Builder(this, statePlayer)
        packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
            sessionBuilder.setSessionActivity(
                android.app.PendingIntent.getActivity(
                    this, 0, launch,
                    android.app.PendingIntent.FLAG_IMMUTABLE or
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT,
                )
            )
        }
        session = sessionBuilder.build()

        notificationManager = PlaybackNotificationManager(
            service         = this,
            handler         = handler,
            getSession      = { session },
            getIsPlaying    = { currentPlaying },
            getCurrentTrack = { buildCurrentTrackMap() },
            serviceClass    = MediaKitPlaybackService::class.java,
        )
        notificationManager.ensureChannel()

        // Register headphone-unplug receiver.
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(noisyReceiver, filter)
        }

        // Do NOT call ensureMediaForeground() here.
        // The service is started with startService() (not startForegroundService()),
        // so there is no 5-second startForeground() obligation.
        // Foreground will be entered lazily when updatePlaybackState(isPlaying=true)
        // arrives from Dart — i.e. when playback actually begins.
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    /**
     * Suppress Media3's built-in DefaultMediaNotificationProvider — we manage
     * the notification entirely via [PlaybackNotificationManager], the same
     * pattern used by [Media3PlaybackService].
     */
    override fun onUpdateNotification(session: MediaSession, startInForegroundRequired: Boolean) {
        // intentionally empty — PlaybackNotificationManager owns the notification
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        // Match against PlaybackNotificationManager constants — those are the action
        // strings baked into the PendingIntents that the notification buttons fire.
        when (intent?.action) {
            PlaybackNotificationManager.ACTION_PLAY_PAUSE -> {
                if (currentPlaying) updateStateAndEmit(playing = false, action = "pause")
                else requestFocusThenEmit("play")
            }
            PlaybackNotificationManager.ACTION_SKIP_NEXT  -> MediaKitEventEmitter.emitTransport("next")
            PlaybackNotificationManager.ACTION_SKIP_PREV  -> MediaKitEventEmitter.emitTransport("previous")
            PlaybackNotificationManager.ACTION_STOP       -> {
                updateStateAndEmit(playing = false, action = "stop")
                abandonAudioFocus()
                notificationManager.stopForeground()
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        handler.removeCallbacksAndMessages(null)
        try { unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
        abandonAudioFocus()
        notificationManager.stopForeground()
        statePlayer.release()
        session?.release()
        session = null
        super.onDestroy()
    }

    // ── MethodChannel command handler ─────────────────────────────────────────

    /**
     * Called by [MainActivity] for every MethodChannel call on
     * `musicplayer/mediakit_service`.
     */
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateMetadata" -> {
                currentTitle    = call.argument<String>("title")  ?: ""
                currentArtist   = call.argument<String>("artist") ?: ""
                currentArtUri   = call.argument<String>("artworkUri")
                currentDuration = (call.argument<Number>("durationMs")?.toLong()) ?: 0L
                statePlayer.updateMetadata(currentTitle, currentArtist, currentArtUri, currentDuration)
                // Only refresh the notification if we are already in foreground.
                // Before playback starts the service runs silently — no notification.
                refreshIfVisible()
                result.success(null)
            }
            "updatePlaybackState" -> {
                currentPlaying  = call.argument<Boolean>("isPlaying") ?: false
                currentPosition = (call.argument<Number>("positionMs")?.toLong()) ?: 0L
                statePlayer.updatePlaybackState(currentPlaying, currentPosition)
                if (currentPlaying) {
                    // First play — promote from background to foreground and show
                    // the notification for the first time.
                    notificationManager.ensureMediaForeground()
                } else {
                    // Paused/stopped — update the play/pause icon only if the
                    // notification is already showing; do not re-create it.
                    refreshIfVisible()
                }
                result.success(null)
            }
            "release" -> {
                updateStateAndEmit(playing = false, action = "stop")
                abandonAudioFocus()
                notificationManager.stopForeground()
                result.success(null)
                stopSelf()
            }
            else -> result.notImplemented()
        }
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun requestFocusThenEmit(action: String) {
        requestAudioFocus()
        MediaKitEventEmitter.emitTransport(action)
    }

    private fun updateStateAndEmit(playing: Boolean, action: String) {
        currentPlaying = playing
        statePlayer.updatePlaybackState(playing, currentPosition)
        refreshIfVisible()
        MediaKitEventEmitter.emitTransport(action)
    }

    /**
     * Updates the notification only when the service is already in foreground.
     *
     * Calling [PlaybackNotificationManager.refresh] while [isForeground] is false
     * would invoke [startForegroundWith] and make the notification appear before
     * playback has started. This guard prevents that.
     */
    private fun refreshIfVisible() {
        if (notificationManager.isForeground) notificationManager.refresh()
    }

    private fun buildCurrentTrackMap(): Map<String, Any?>? {
        if (currentTitle.isEmpty()) return null
        return mapOf(
            "title"      to currentTitle,
            "artist"     to currentArtist,
            "artworkUri" to currentArtUri,
            "duration"   to currentDuration,
        )
    }

    // ── Audio focus (API 29 guaranteed — minSdk = 29) ─────────────────────────

    private fun requestAudioFocus() {
        if (hasAudioFocus) return
        val am = audioManager ?: return
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attrs)
            .setOnAudioFocusChangeListener(focusListener, handler)
            .setWillPauseWhenDucked(false)
            .setAcceptsDelayedFocusGain(true)
            .build()
        focusRequest  = req
        val result    = am.requestAudioFocus(req)
        hasAudioFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED ||
                        result == AudioManager.AUDIOFOCUS_REQUEST_DELAYED
    }

    private fun abandonAudioFocus() {
        focusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        focusRequest  = null
        hasAudioFocus = false
    }
}
