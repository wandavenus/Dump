package com.example.musicplayer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.MediaStyleNotificationHelper
import java.util.IdentityHashMap
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class Media3PlaybackService : MediaSessionService() {
    private var primaryPlayer: ExoPlayer? = null
    private var secondaryPlayer: ExoPlayer? = null
    private var activePlayer: ExoPlayer? = null
    private val player: ExoPlayer?
        get() = activePlayer

    private fun standbyPlayer(): ExoPlayer? =
        if (activePlayer === primaryPlayer) secondaryPlayer else primaryPlayer
    
    private var session: MediaSession? = null
    private var queue: List<Map<String, Any?>> = emptyList()
    private val handler = Handler(Looper.getMainLooper())
    private val positionUpdateMs = 200L
    private lateinit var audioManager: AudioManager
    private var focusRequest: AudioFocusRequest? = null
    private var resumeAfterFocusGain = false
    private var volumeBeforeDuck = 1f
    private var equalizer: Equalizer? = null
    private var loudness: LoudnessEnhancer? = null
    private var eqEnabled = false
    private val bandGains = mutableMapOf<Short, Short>()
    private var loudnessEnabled = false
    private var loudnessTargetMb = 0f

    // ── Bass Boost ─────────────────────────────────────────────────────────────
    private var bassBoost: BassBoost? = null
    private var bassBoostStrength: Short = 0
    private var bassBoostEnabled: Boolean = false
    private var bassBoostSupported: Boolean = false

    // ── Virtualizer / Spatial Audio ────────────────────────────────────────────
    private var virtualizer: Virtualizer? = null
    private var virtualizerStrength: Short = 1000
    private var virtualizerEnabled: Boolean = false
    private var virtualizerSupported: Boolean = false

    // ── Preset Reverb ──────────────────────────────────────────────────────────
    private var reverb: PresetReverb? = null
    private var reverbPreset: Short = 0
    private var reverbSupported: Boolean = false

    // ── Crossfade (fade-out near track end, fade-in on transition) ─────────────
    private var crossfadeDurationSec: Float = 0f
    private var crossfadeFadeRunnable: Runnable? = null
    private var promotionTriggered = false
    private var crossfadeInProgress = false
    private var preloadedQueueIndex = C.INDEX_UNSET
    private var activeQueueIndex = 0
    private val playerListeners = IdentityHashMap<ExoPlayer, Player.Listener>()
    // Android 11 / MIUI 12: ensureMediaForeground() must only be called once per
    // service lifecycle.  MIUI aggressively kills services that call startForeground()
    // repeatedly, and Android 11 requires startForeground() within 5 s of
    // startForegroundService() — subsequent calls reset the timer unnecessarily.
    private var isForeground = false

    private val positionTicker = object : Runnable {
        override fun run() {
            emitAll()
            maybeCrossfadeOut()
            handler.postDelayed(this, positionUpdateMs)
        }
    }

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                player?.pause()
                emitAll()
            }
        }
    }

    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { change ->
        val p = player ?: return@OnAudioFocusChangeListener
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                p.volume = volumeBeforeDuck
                if (resumeAfterFocusGain) {
                    resumeAfterFocusGain = false
                    p.play()
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                resumeAfterFocusGain = p.isPlaying
                p.pause()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                volumeBeforeDuck = p.volume
                p.volume = (p.volume * 0.25f).coerceAtMost(0.25f)
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeAfterFocusGain = false
                p.pause()
                abandonAudioFocus()
            }
        }
        emitAll()
    }

    // ── Foreground service ─────────────────────────────────────────────────────
    //
    // Android 11 (API 30) requires startForeground() to be called within 5 s of
    // startForegroundService(). MediaSessionService does this lazily (only when
    // a MediaController connects or playback starts), which is too late when the
    // service is driven via MethodChannel on MIUI 12.
    //
    // We call startForeground() immediately with a proper MediaStyle notification
    // using the MediaSession token. This satisfies the OS timer AND ensures the
    // notification is already media-style so Media3's DefaultMediaNotificationProvider
    // can update it with track metadata and transport controls without replacing
    // our foreground association.

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        when (intent?.action) {
            ACTION_PLAY_PAUSE -> {
                val p = player
                if (p != null) {
                    if (p.isPlaying) {
                        p.pause()
                        abandonAudioFocus()
                        nativeLog("info", "transport: pause (notification/BT button)")
                    } else {
                        if (requestAudioFocus()) {
                            p.play()
                            nativeLog("info", "transport: play (notification/BT button)")
                        } else {
                            nativeLog("warn", "transport: play denied — audio focus not granted")
                        }
                    }
                    emitAll()
                    refreshNotification()
                } else {
                    nativeLog("warn", "transport: ACTION_PLAY_PAUSE received but player is null")
                }
            }
            ACTION_SKIP_NEXT -> {
                player?.seekToNextMediaItem()
                nativeLog("info", "transport: skipNext (notification/BT button)")
                emitAll()
                refreshNotification()
            }
            ACTION_SKIP_PREV -> {
                player?.seekToPreviousMediaItem()
                nativeLog("info", "transport: skipPrev (notification/BT button)")
                emitAll()
                refreshNotification()
            }
         ACTION_STOP -> {
    nativeLog("info", "transport: stop (notification/BT button)")

    player?.pause()
    player?.seekTo(0)
    abandonAudioFocus()

    isForeground = false
    stopForeground(STOP_FOREGROUND_REMOVE)

    emitAll()
}
            
            else -> {
    if ((player?.mediaItemCount ?: 0) > 0) {
        ensureMediaForeground()
    }
}
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        nativeLog("info", "onTaskRemoved: app removed from recents — service continues in background (stopWithTask=false)")
        // Do NOT stop the service here. android:stopWithTask="false" keeps us alive.
        // When the user reopens the app, AudioService.syncFromNative() restores Dart state.
    }

    /** Creates a PendingIntent that re-enters this service with the given [action]. */
    private fun buildTransportPendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, Media3PlaybackService::class.java).setAction(action)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                this, requestCode, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } else {
            PendingIntent.getService(
                this, requestCode, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
    }

    private fun ensureMediaForeground() {
        if (isForeground) return   // MIUI 12 / Android 11: run once per lifecycle only
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
       val p = player ?: return


        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Music Playback", NotificationManager.IMPORTANCE_LOW)
                    .apply { setSound(null, null); enableVibration(false) }
            )
        }

        val sess = session
        val t = currentTrackMap()
        val title = t?.get("title") as? String ?: "Music Player"
        val artist = t?.get("artist") as? String ?: ""

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        // Attach MediaSession token and transport controls (Prev / Play-Pause / Next).
        // setShowActionsInCompactView(0, 1, 2) puts all three buttons in the collapsed view
        // AND in the lockscreen / Bluetooth head-unit.
        if (sess != null) {
            val isPlaying = player?.isPlaying ?: false

builder
    .addAction(
        NotificationCompat.Action(
            R.drawable.ic_prev,
            "Previous",
            buildTransportPendingIntent(ACTION_SKIP_PREV, 1)
        )
    )
    .addAction(
        NotificationCompat.Action(
            if (isPlaying) R.drawable.ic_pause
            else R.drawable.ic_play,
            if (isPlaying) "Pause" else "Play",
            buildTransportPendingIntent(ACTION_PLAY_PAUSE, 2)
        )
    )
    .addAction(
        NotificationCompat.Action(
            R.drawable.ic_next,
            "Next",
            buildTransportPendingIntent(ACTION_SKIP_NEXT, 3)
        )
    )
    .addAction(
        NotificationCompat.Action(
            R.drawable.ic_stop,
            "Stop",
            buildTransportPendingIntent(ACTION_STOP, 4)
        )
    )
    .setStyle(
        MediaStyleNotificationHelper.MediaStyle(sess)
            .setShowActionsInCompactView(0, 1, 2)
    )
        }

        // Try to set artwork from the current track if available.
      /*  val artworkUri = t?.get("artworkUri") as? String

if (!artworkUri.isNullOrBlank()) {
    try {
        val uri = Uri.parse(artworkUri)

        if (
            uri.toString().contains("/albumart/-") ||
            uri.toString().endsWith("/0")
        ) {
            nativeLog("warn", "Skipping invalid artwork URI: $uri")
        } else {
            val bitmap = contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it)
            }

            if (bitmap != null) {
                builder.setLargeIcon(bitmap)
            }
        }
    } catch (e: Exception) {
        nativeLog("warn", "Artwork load failed: ${e.message}")
    }
}*/

        val notification = builder.build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        isForeground = true   // guard: subsequent calls are no-ops until ACTION_STOP
    }

    // ── Notification refresh ───────────────────────────────────────────────────
    //
    // Called whenever track or playback state changes to update the media
    // notification content (title, artist, artwork, transport controls).

    private fun refreshNotification() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val sess = session ?: return
        val nm = getSystemService(NotificationManager::class.java)

        val t = currentTrackMap()
        val p = player ?: return
        val title = t?.get("title") as? String ?: "Music Player"
        val artist = t?.get("artist") as? String ?: ""

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
    .setSmallIcon(R.drawable.ic_notification)
    .setContentTitle(title)
    .setContentText(artist)
    .setContentIntent(pendingIntent)
    .setOngoing(p.isPlaying)
    .setOnlyAlertOnce(true)
    .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

    .addAction(
        NotificationCompat.Action(
            R.drawable.ic_prev,
            "Previous",
            buildTransportPendingIntent(ACTION_SKIP_PREV, 1)
        )
    )
    .addAction(
        NotificationCompat.Action(
            if (p.isPlaying)
                R.drawable.ic_pause
            else
                R.drawable.ic_play,
            if (p.isPlaying) "Pause" else "Play",
            buildTransportPendingIntent(ACTION_PLAY_PAUSE, 2)
        )
    )
    .addAction(
        NotificationCompat.Action(
            R.drawable.ic_next,
            "Next",
            buildTransportPendingIntent(ACTION_SKIP_NEXT, 3)
        )
    )
    .addAction(
        NotificationCompat.Action(
            R.drawable.ic_stop,
            "Stop",
            buildTransportPendingIntent(ACTION_STOP, 4)
        )
    )
    .setStyle(
        MediaStyleNotificationHelper.MediaStyle(sess)
            .setShowActionsInCompactView(0, 1, 2)
    )
                
        val artworkUri = t?.get("artworkUri") as? String
        if (!artworkUri.isNullOrBlank()) {
            try {
                val uri = Uri.parse(artworkUri)
                if (!uri.toString().contains("/albumart/-") && !uri.toString().endsWith("/0")) {
                    val bitmap = contentResolver.openInputStream(uri)?.use {
                        BitmapFactory.decodeStream(it)
                    }
                    if (bitmap != null) {
                        builder.setLargeIcon(bitmap)
                        nativeLog("verbose", "refreshNotification: artwork loaded for '$title'")
                    }
                }
            } catch (e: Exception) {
                nativeLog("verbose", "refreshNotification: artwork load skipped — ${e.message}")
            }
        }

        try {
    val notification = builder.build()

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(
            NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        )
    } else {
        startForeground(
            NOTIFICATION_ID,
            notification
        )
    }
} catch (e: Exception) {
    nativeLog(
        "warn",
        "refreshNotification: update failed — ${e.message}"
    )
}
    }

    private fun createConfiguredPlayer(): ExoPlayer = ExoPlayer.Builder(this).build().apply {
        val attrs = androidx.media3.common.AudioAttributes.Builder()
            .setUsage(androidx.media3.common.C.USAGE_MEDIA)
            .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()
        setAudioAttributes(attrs, false)
        setHandleAudioBecomingNoisy(true)
    }

    private fun attachPlayerListener(player: ExoPlayer) {
        detachPlayerListener(player)
        val listener = object : Player.Listener {
            private fun isActiveEvent(): Boolean = player === activePlayer

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (!isActiveEvent()) return
                emitAll()
                refreshNotification()
                if (playbackState == Player.STATE_READY && crossfadeDurationSec > 0f) preloadNextTrack()
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (!isActiveEvent()) return
                emitAll()
                refreshNotification()
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                if (!isActiveEvent()) return
                if (!crossfadeInProgress && player.currentMediaItemIndex >= 0) {
                    activeQueueIndex = player.currentMediaItemIndex
                    promotionTriggered = false
                    if (crossfadeDurationSec > 0f) preloadNextTrack(force = true)
                }
                emitAll()
                refreshNotification()
            }

            override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) {
                if (isActiveEvent()) emitAll()
            }

            override fun onRepeatModeChanged(repeatMode: Int) {
                if (isActiveEvent()) emitAll()
            }

            override fun onAudioSessionIdChanged(audioSessionId: Int) {
                if (!isActiveEvent()) return
                nativeLog("info", "audioSessionId → $audioSessionId")
                attachEffects(audioSessionId)
                emitAll()
            }
        }
        playerListeners[player] = listener
        player.addListener(listener)
    }

    private fun detachPlayerListener(player: ExoPlayer) {
        playerListeners.remove(player)?.let { player.removeListener(it) }
    }

    private fun ensureStandbyPlayer(): ExoPlayer? {
        if (crossfadeDurationSec <= 0f) return null
        val standby = standbyPlayer()
        if (standby != null) return standby
        val created = createConfiguredPlayer()
        if (activePlayer === primaryPlayer) secondaryPlayer = created else primaryPlayer = created
        attachPlayerListener(created)
        return created
    }

    private fun clearStandbyQueue() {
        standbyPlayer()?.let { standby ->
            try { standby.pause() } catch (_: Exception) {}
            try { standby.stop() } catch (_: Exception) {}
            try { standby.clearMediaItems() } catch (_: Exception) {}
        }
        preloadedQueueIndex = C.INDEX_UNSET
    }

    private fun releaseStandbyPlayer() {
        val standby = standbyPlayer() ?: return
        detachPlayerListener(standby)
        try { standby.release() } catch (_: Exception) {}
        if (standby === primaryPlayer) primaryPlayer = null
        if (standby === secondaryPlayer) secondaryPlayer = null
        preloadedQueueIndex = C.INDEX_UNSET
    }

    private fun cancelCrossfade(resetVolume: Boolean) {
        crossfadeFadeRunnable?.let { handler.removeCallbacks(it) }
        crossfadeFadeRunnable = null
        crossfadeInProgress = false
        promotionTriggered = false
        if (resetVolume) player?.volume = volumeBeforeDuck
    }

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        primaryPlayer = createConfiguredPlayer()
        val exoPlayer = primaryPlayer!!
        activePlayer = exoPlayer
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        session = MediaSession.Builder(this, exoPlayer)
            .setSessionActivity(pendingIntent)
            .build()

attachPlayerListener(primaryPlayer!!)
        
        registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        instance = this
ensureMediaForeground()
        // Ticker will be started dynamically when playback starts
        nativeLog("info", "onCreate: ExoPlayer ready, MediaSession created (Android ${Build.VERSION.SDK_INT} / MIUI=${isMiui()})")
        emitAll()
    }

    private fun isMiui(): Boolean = try {
        val cls = Class.forName("android.os.SystemProperties")
        val get = cls.getMethod("get", String::class.java)
        (get.invoke(cls, "ro.miui.ui.version.name") as? String)?.isNotEmpty() == true
    } catch (_: Exception) { false }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onDestroy() {
        nativeLog("info", "onDestroy: releasing ExoPlayer, MediaSession, effects")
        effectHandler.removeCallbacksAndMessages(null) 
        handler.removeCallbacks(positionTicker)
        try { unregisterReceiver(noisyReceiver) } catch (e: Exception) { android.util.Log.w("Media3", "Noisy receiver unregister failed", e) }
        abandonAudioFocus()
        releaseEffects()
        instance = null
        primaryPlayer?.release()
secondaryPlayer?.release()

primaryPlayer = null
secondaryPlayer = null
activePlayer = null

session?.release()
session = null
        super.onDestroy()
    }

    private fun emitAll() {
        val p = player ?: return
        val state = when (p.playbackState) {
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_READY -> "ready"
            Player.STATE_ENDED -> "completed"
            else -> "idle"
        }
        Events.emit("playbackState", mapOf("playing" to p.isPlaying, "processingState" to state))
        Events.emit("bufferingState", p.playbackState == Player.STATE_BUFFERING)
        Events.emit("position", p.currentPosition.coerceAtLeast(0L))
        Events.emit("duration", p.duration.coerceAtLeast(0L))
        Events.emit("currentTrack", currentTrackMap())
        Events.emit("queue", queue)
        Events.emit("audioSessionId", p.audioSessionId)
    }

    private fun currentTrackMap(): Map<String, Any?>? {
        val p = player ?: return null
        val index = if (crossfadeDurationSec > 0f) activeQueueIndex else p.currentMediaItemIndex
        val songMap = queue.getOrNull(index) ?: return null
        // Compute artworkUri from albumId so refreshNotification() can load album art.
        // content://media/external/audio/albumart/<albumId> works on Android 10+
        // (API 29) and is the standard MediaStore album-art content URI.
        val albumId = (songMap["albumId"] as? Number)?.toLong() ?: 0L
        val artUri  = if (albumId > 0) "content://media/external/audio/albumart/$albumId" else null
        return songMap + mapOf("index" to index, "artworkUri" to artUri)
    }

    private fun mediaItemFrom(map: Map<*, *>): MediaItem {
    val path = map["path"] as? String ?: ""

    val uri =
        if (path.startsWith("content://") || path.startsWith("file://"))
            path.toUri()
        else
            Uri.fromFile(java.io.File(path))

    val albumId = (map["albumId"] as? Number)?.toLong() ?: 0L

    val artworkUri: Uri? =
        if (albumId > 0) {
            Uri.parse("content://media/external/audio/albumart/$albumId")
        } else {
            null
        }

    val metadataBuilder = MediaMetadata.Builder()
        .setTitle(map["title"] as? String)
        .setArtist(map["artist"] as? String)
        .setAlbumTitle(map["album"] as? String)

    if (artworkUri != null) {
        metadataBuilder.setArtworkUri(artworkUri)
    }

    val metadata = metadataBuilder.build()

    return MediaItem.Builder()
        .setMediaId((map["id"] ?: path).toString())
        .setUri(uri)
        .setMediaMetadata(metadata)
        .build()
}
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val p = player ?: return result.error("not_ready", "Media3 service is not ready", null)
        when (call.method) {
            "play" -> {
                val granted = requestAudioFocus()
                if (granted) {
                    p.play()
               
                    handler.removeCallbacks(positionTicker)
handler.post(positionTicker)  
                    
                    val t = currentTrackMap()
                    val title  = t?.get("title")  as? String ?: "?"
                    val artist = t?.get("artist") as? String ?: "?"
                    nativeLog("info", "play → '$title' · $artist  [${p.currentMediaItemIndex + 1}/${queue.size}]")
                } else {
                    nativeLog("warn", "play: audio focus denied by OS")
                }
                result.success(null)
            }
            "pause" -> {
                p.pause()
               
             handler.removeCallbacks(positionTicker)
                
                abandonAudioFocus()
                val ms = p.currentPosition
                nativeLog("info", "pause @ %d:%02d.%02d".format(ms / 60000, (ms % 60000) / 1000, (ms % 1000) / 10))
                result.success(null)
            }
            "stop" -> { p.stop(); 
             
                handler.removeCallbacks(positionTicker)   
                
                abandonAudioFocus(); nativeLog("info", "stop"); result.success(null) }
            "seek" -> {
                val pos = (call.argument<Number>("position")?.toLong() ?: 0L).coerceAtLeast(0L)
                p.seekTo(pos)
                nativeLog("verbose", "seek → %d:%02d.%02d".format(pos / 60000, (pos % 60000) / 1000, (pos % 1000) / 10))
                result.success(null)
            }
            "skipNext" -> {
                cancelCrossfade(resetVolume = true)
                clearStandbyQueue()
                p.seekToNextMediaItem()
                nativeLog("verbose", "skipNext")
                result.success(null)
            }
            "skipPrevious" -> {
                cancelCrossfade(resetVolume = true)
                clearStandbyQueue()
                p.seekToPreviousMediaItem()
                nativeLog("verbose", "skipPrevious")
                result.success(null)
            }
            "setQueue" -> {
                @Suppress("UNCHECKED_CAST") val items = call.argument<List<Map<String, Any?>>>("queue") ?: emptyList()
                val index = call.argument<Number>("index")?.toInt() ?: 0
                queue = items
                activeQueueIndex = index.coerceIn(0, (items.size - 1).coerceAtLeast(0))
                cancelCrossfade(resetVolume = true)
                releaseStandbyPlayer()
                p.setMediaItems(items.map { mediaItemFrom(it) }, activeQueueIndex, 0L)
                p.prepare()
                if (crossfadeDurationSec > 0f) preloadNextTrack() 
              
               
                
                val firstTitle = items.getOrNull(index)?.get("title") as? String ?: "?"
                nativeLog("info", "setQueue: ${items.size} tracks → [$index] '$firstTitle'")
                emitAll(); refreshNotification(); result.success(null)
            }
            "setTrack" -> {
                val target = (call.argument<Number>("index")?.toInt() ?: 0).coerceIn(0, (queue.size - 1).coerceAtLeast(0))
                cancelCrossfade(resetVolume = true)
                clearStandbyQueue()
                activeQueueIndex = target
                p.seekToDefaultPosition(target)
                if (crossfadeDurationSec > 0f) preloadNextTrack()
                result.success(null)
            }
            "setRepeatMode" -> {
                p.repeatMode = when (call.argument<String>("mode")) { "one" -> Player.REPEAT_MODE_ONE; "all" -> Player.REPEAT_MODE_ALL; else -> Player.REPEAT_MODE_OFF }
                clearStandbyQueue()
                if (crossfadeDurationSec > 0f) preloadNextTrack(force = true)
                result.success(null)
            }
            "setShuffleMode" -> {
                p.shuffleModeEnabled = call.argument<Boolean>("enabled") ?: false
                clearStandbyQueue()
                if (crossfadeDurationSec > 0f) preloadNextTrack(force = true)
                result.success(null)
            }
            "setVolume" -> { p.volume = (call.argument<Number>("volume")?.toFloat() ?: 1f).coerceIn(0f, 1f); volumeBeforeDuck = p.volume; result.success(null) }
            "setSpeed" -> { val speed = (call.argument<Number>("speed")?.toFloat() ?: 1f).coerceIn(0.25f, 4f); p.playbackParameters = PlaybackParameters(speed, p.playbackParameters.pitch); result.success(null) }
            "setPitch" -> { val pitch = (call.argument<Number>("pitch")?.toFloat() ?: 1f).coerceIn(0.5f, 2f); p.playbackParameters = PlaybackParameters(p.playbackParameters.speed, pitch); result.success(null) }
            "setEqualizerEnabled" -> { setEqualizerEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }
            "setEqualizerBandGain" -> { setEqualizerBandGain((call.argument<Number>("band")?.toInt() ?: 0).toShort(), ((call.argument<Number>("gainDb")?.toDouble() ?: 0.0) * 100).toInt().toShort()); result.success(null) }
            "setLoudnessTargetGain" -> { setLoudnessTargetGain((call.argument<Number>("gainMb")?.toFloat() ?: 0f)); result.success(null) }
            "setLoudnessEnabled" -> { setLoudnessEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }

            // ── ReplayGain (pre-computed by Dart, applied via LoudnessEnhancer) ──────
            "setTrackGain" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val gainDb  = call.argument<Number>("gainDb")?.toFloat() ?: 0f
                val gainMb  = gainDb * 100f
                setLoudnessTargetGain(gainMb)
                setLoudnessEnabled(enabled)
                result.success(null)
            }

            // ── Bass Boost ──────────────────────────────────────────────────────────
            "setBassBoostEnabled"   -> { nativeBassBoostEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }
            "setBassBoostStrength"  -> { nativeBassBoostStrength((call.argument<Number>("strength")?.toInt() ?: 0).toShort()); result.success(null) }

            // ── Virtualizer / Spatial Audio ─────────────────────────────────────────
            "setVirtualizerEnabled"  -> { nativeVirtualizerEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }
            "setVirtualizerStrength" -> { nativeVirtualizerStrength((call.argument<Number>("strength")?.toInt() ?: 1000).toShort()); result.success(null) }

            // ── Preset Reverb ───────────────────────────────────────────────────────
            "setReverbPreset" -> { nativeReverbPreset((call.argument<Number>("preset")?.toInt() ?: 0).toShort()); result.success(null) }

            // ── Crossfade ───────────────────────────────────────────────────────────
            "setCrossfadeDuration" -> {
                crossfadeDurationSec = (call.argument<Number>("duration")?.toFloat() ?: 0f).coerceAtLeast(0f)
                cancelCrossfade(resetVolume = true)
                if (crossfadeDurationSec <= 0f) {
                    releaseStandbyPlayer()
                } else {
                    ensureStandbyPlayer()
                    preloadNextTrack()
                }
                nativeLog("verbose", "setCrossfadeDuration: ${crossfadeDurationSec}s")
                result.success(null)
            }

            // ── Effect support query ────────────────────────────────────────────────
            "getEffectSupport" -> {
                result.success(mapOf(
                    "virtualizerSupported" to virtualizerSupported,
                    "bassBoostSupported"   to bassBoostSupported,
                    "reverbSupported"      to reverbSupported,
                ))
            }

            "getEqualizerParameters" -> result.success(equalizerParameters())

            // ── State sync APIs ──────────────────────────────────────────────────
            // These are called explicitly by Flutter on startup and resume to
            // reconstruct the playback state without waiting for EventChannel events.

            "getPlaybackSnapshot" -> {
                val state = when (p.playbackState) {
                    Player.STATE_BUFFERING -> "buffering"
                    Player.STATE_READY -> "ready"
                    Player.STATE_ENDED -> "completed"
                    else -> "idle"
                }
                result.success(mapOf(
                    "queue"           to queue,
                    "currentIndex"    to (if (crossfadeDurationSec > 0f) activeQueueIndex else p.currentMediaItemIndex),
                    "isPlaying"       to p.isPlaying,
                    "processingState" to state,
                    "positionMs"      to p.currentPosition.coerceAtLeast(0L),
                    "durationMs"      to p.duration.coerceAtLeast(0L),
                    "audioSessionId"  to p.audioSessionId,
                ))
            }

            else -> result.notImplemented()
        }
        if (call.method != "getPlaybackSnapshot" && call.method != "getEqualizerParameters") {
            emitAll()
        }
    }

    private fun requestAudioFocus(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs).setOnAudioFocusChangeListener(focusChangeListener).setWillPauseWhenDucked(false).build()
            focusRequest = req
            audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(focusChangeListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        else @Suppress("DEPRECATION") audioManager.abandonAudioFocus(focusChangeListener)
        focusRequest = null
    }

    private var lastAttachedSessionId = -1
    private val effectHandler = Handler(Looper.getMainLooper())

    private fun attachEffects(sessionId: Int, attempt: Int = 0) {
        if (sessionId <= 0) return

        if (sessionId == lastAttachedSessionId) {
            nativeLog("verbose", "attachEffects skipped for session=$sessionId")
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
            nativeLog("warn", "Equalizer init failed (session=$sessionId, attempt=${attempt + 1}): ${e.message}")
        }

        try {
            loudness = LoudnessEnhancer(sessionId).apply {
                setTargetGain(loudnessTargetMb.toInt())
                enabled = loudnessEnabled
            }
            leOk = true
        } catch (e: Exception) {
            nativeLog("warn", "LoudnessEnhancer init failed (session=$sessionId, attempt=${attempt + 1}): ${e.message}")
        }

        // ── Bass Boost ──────────────────────────────────────────────────────
        bassBoostSupported = false
        if (isEffectTypeAvailable(AudioEffect.EFFECT_TYPE_BASS_BOOST)) {
            try {
                bassBoost = BassBoost(0, sessionId).apply {
                    setStrength(bassBoostStrength)
                    enabled = bassBoostEnabled
                }
                bassBoostSupported = true
            } catch (e: Exception) {
                nativeLog("warn", "BassBoost init failed (attempt=${attempt + 1}): ${e.message}")
            }
        }

        // ── Virtualizer ─────────────────────────────────────────────────────
        virtualizerSupported = false
        if (isEffectTypeAvailable(AudioEffect.EFFECT_TYPE_VIRTUALIZER)) {
            try {
                virtualizer = Virtualizer(0, sessionId).apply {
                    setStrength(virtualizerStrength)
                    enabled = virtualizerEnabled
                }
                virtualizerSupported = true
            } catch (e: Exception) {
                nativeLog("warn", "Virtualizer init failed (attempt=${attempt + 1}): ${e.message}")
            }
        }

        // ── Preset Reverb ────────────────────────────────────────────────────
        reverbSupported = false
        if (isEffectTypeAvailable(AudioEffect.EFFECT_TYPE_PRESET_REVERB)) {
            try {
                reverb = PresetReverb(0, sessionId).apply {
                    preset  = toAndroidReverbPreset(reverbPreset)
                    enabled = reverbPreset > 0
                }
                reverbSupported = true
            } catch (e: Exception) {
                nativeLog("warn", "PresetReverb init failed (attempt=${attempt + 1}): ${e.message}")
            }
        }

        if (eqOk || leOk) {
            lastAttachedSessionId = sessionId
            nativeLog(
                "info",
                "attachEffects(session=$sessionId) success attempt=${attempt + 1} " +
                "bass=$bassBoostSupported virt=$virtualizerSupported reverb=$reverbSupported"
            )
            return
        }

        if (attempt < 2) {
            val delayMs = when (attempt) { 0 -> 100L; 1 -> 200L; else -> 400L }
            nativeLog("warn", "attachEffects(session=$sessionId) retry in ${delayMs}ms")
            effectHandler.postDelayed({ attachEffects(sessionId, attempt + 1) }, delayMs)
            return
        }

        nativeLog("warn", "attachEffects(session=$sessionId) failed after retries")
    }

    private fun releaseEffects() {
        try { equalizer?.release()  } catch (_: Exception) {}
        try { loudness?.release()   } catch (_: Exception) {}
        try { bassBoost?.release()  } catch (_: Exception) {}
        try { virtualizer?.release()} catch (_: Exception) {}
        try { reverb?.release()     } catch (_: Exception) {}
        equalizer   = null
        loudness    = null
        bassBoost   = null
        virtualizer = null
        reverb      = null
    }
    private fun setEqualizerEnabled(enabled: Boolean) { eqEnabled = enabled; try { equalizer?.enabled = enabled } catch (_: Exception) {} }
    private fun setEqualizerBandGain(band: Short, gain: Short) { bandGains[band] = gain; try { equalizer?.let { it.setBandLevel(band, gain.coerceIn(it.bandLevelRange[0], it.bandLevelRange[1])) } } catch (_: Exception) {} }
    private fun setLoudnessTargetGain(gainMb: Float) { loudnessTargetMb = gainMb; try { loudness?.setTargetGain(gainMb.toInt()) } catch (_: Exception) {} }
    private fun setLoudnessEnabled(enabled: Boolean) { loudnessEnabled = enabled; try { loudness?.enabled = enabled } catch (_: Exception) {} }

    // ── Bass Boost controls ────────────────────────────────────────────────────
    private fun nativeBassBoostEnabled(enabled: Boolean) {
        bassBoostEnabled = enabled
        try { bassBoost?.enabled = enabled } catch (_: Exception) {}
    }
    private fun nativeBassBoostStrength(strength: Short) {
        bassBoostStrength = strength
        try { bassBoost?.setStrength(strength) } catch (_: Exception) {}
        if (bassBoostEnabled != (strength > 0)) nativeBassBoostEnabled(strength > 0)
    }

    // ── Virtualizer controls ───────────────────────────────────────────────────
    private fun nativeVirtualizerEnabled(enabled: Boolean) {
        virtualizerEnabled = enabled
        try {
            virtualizer?.run {
                if (enabled) {
                    setStrength(virtualizerStrength)
                    this.enabled = true
                } else {
                    this.enabled = false
                }
            }
        } catch (_: Exception) {}
    }
    private fun nativeVirtualizerStrength(strength: Short) {
        virtualizerStrength = strength
        try { if (virtualizerEnabled) virtualizer?.setStrength(strength) } catch (_: Exception) {}
    }

    // ── Preset Reverb controls ────────────────────────────────────────────────
    private fun nativeReverbPreset(preset: Short) {
        reverbPreset = preset
        try {
            reverb?.run {
                this.preset  = toAndroidReverbPreset(preset)
                this.enabled = preset > 0
            }
        } catch (_: Exception) {}
    }

    private fun toAndroidReverbPreset(preset: Short): Short = when (preset.toInt()) {
        1    -> PresetReverb.PRESET_SMALLROOM
        2    -> PresetReverb.PRESET_MEDIUMROOM
        3    -> PresetReverb.PRESET_LARGEROOM
        4    -> PresetReverb.PRESET_MEDIUMHALL
        5    -> PresetReverb.PRESET_LARGEHALL
        6    -> PresetReverb.PRESET_PLATE
        else -> PresetReverb.PRESET_NONE
    }

    // ── Effect-type availability check ────────────────────────────────────────
    //
    // MIUI 12 / Android 11: AudioEffect.queryEffects() returns the list of
    // hardware-supported effects. Some MIUI builds only support a subset of the
    // standard Android effects (e.g., no virtualizer), so we check before
    // attempting to create the effect to avoid noisy exceptions.

    private fun isEffectTypeAvailable(type: java.util.UUID): Boolean =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) true
        else try {
            AudioEffect.queryEffects()?.any { it.type == type } ?: false
        } catch (_: Exception) { false }

    // ── Crossfade helpers ─────────────────────────────────────────────────────
    //
    // True simultaneous crossfade uses a lazy standby ExoPlayer only while
    // crossfade is enabled. The standby player is never attached to the
    // MediaSession; promotion moves the MediaSession to the prepared player,
    // detaches the old player's queue tail to prevent native auto-advance, and
    // fades old/new players in opposite directions before clearing the old queue.

    private fun preloadNextTrack(force: Boolean = false) {
        if (crossfadeDurationSec <= 0f || queue.isEmpty()) return
        val current = activePlayer ?: return
        val standby = ensureStandbyPlayer() ?: return
        if (standby === current) return

        val nextIndex = current.nextMediaItemIndex
        if (nextIndex == C.INDEX_UNSET || nextIndex !in queue.indices) {
            clearStandbyQueue()
            return
        }
        if (!force && standby.mediaItemCount > 0 && preloadedQueueIndex == nextIndex) return

        try {
            standby.pause()
            standby.stop()
            standby.clearMediaItems()
            standby.volume = 0f
            standby.repeatMode = current.repeatMode
            standby.shuffleModeEnabled = current.shuffleModeEnabled
            standby.playbackParameters = current.playbackParameters
            standby.setMediaItems(queue.map { mediaItemFrom(it) }, nextIndex, 0L)
            standby.prepare()
            preloadedQueueIndex = nextIndex
            nativeLog("info", "preloadNextTrack → [$nextIndex] '${queue[nextIndex]["title"]}'")
        } catch (e: Exception) {
            preloadedQueueIndex = C.INDEX_UNSET
            nativeLog("warn", "preloadNextTrack failed: ${e.message}")
        }
    }

    private fun promoteSecondaryPlayer() {
        if (crossfadeInProgress) return
        val next = standbyPlayer() ?: return
        val current = activePlayer ?: return
        val nextIndex = preloadedQueueIndex
        if (next.mediaItemCount == 0 || nextIndex !in queue.indices) return

        crossfadeInProgress = true
        promotionTriggered = true
        activeQueueIndex = nextIndex
        nativeLog("info", "Promoting standby player")

        try {
            val currentIndex = current.currentMediaItemIndex
            if (current.mediaItemCount > currentIndex + 1) {
                current.removeMediaItems(currentIndex + 1, current.mediaItemCount)
            }
        } catch (e: Exception) {
            nativeLog("warn", "detach old queue failed: ${e.message}")
        }

        next.volume = 0f
        activePlayer = next
        rebuildMediaSession(next)
        if (requestAudioFocus()) next.play()
        startCrossfadeFadeIn(next, current)
        emitAll()
        refreshNotification()
    }

    private fun rebuildMediaSession(newPlayer: ExoPlayer) {
        session?.release()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        session = MediaSession.Builder(this, newPlayer)
            .setSessionActivity(pendingIntent)
            .build()
    }

    private fun maybeCrossfadeOut() {
        if (crossfadeDurationSec <= 0f || promotionTriggered || crossfadeInProgress) return
        val p = player ?: return
        val dur = p.duration
        if (dur <= 0L || dur == Long.MIN_VALUE || dur == C.TIME_UNSET) return
        if (!p.hasNextMediaItem()) return

        preloadNextTrack()
        val standby = standbyPlayer() ?: return
        if (standby.mediaItemCount == 0) return

        val crossMs = (crossfadeDurationSec * 1000f).toLong().coerceAtLeast(250L)
        val remaining = dur - p.currentPosition
        if (remaining in 1L..crossMs) {
            nativeLog("info", "Triggering promotion at ${remaining}ms")
            promoteSecondaryPlayer()
        }
    }

    private fun startCrossfadeFadeIn(newPlayer: ExoPlayer, oldPlayer: ExoPlayer) {
        crossfadeFadeRunnable?.let { handler.removeCallbacks(it) }
        val durationMs = (crossfadeDurationSec * 1000f).toLong().coerceAtLeast(100L)
        val steps = 25
        val stepMs = (durationMs / steps).coerceAtLeast(8L)
        val targetVol = volumeBeforeDuck.coerceIn(0f, 1f)
        var step = 0
        val runnable = object : Runnable {
            override fun run() {
                if (activePlayer !== newPlayer) return
                if (step >= steps) {
                    newPlayer.volume = targetVol
                    try { oldPlayer.pause() } catch (_: Exception) {}
                    try { oldPlayer.stop() } catch (_: Exception) {}
                    try { oldPlayer.clearMediaItems() } catch (_: Exception) {}
                    crossfadeInProgress = false
                    promotionTriggered = false
                    crossfadeFadeRunnable = null
                    preloadedQueueIndex = C.INDEX_UNSET
                    preloadNextTrack(force = true)
                    return
                }
                val progress = step.toFloat() / steps.toFloat()
                oldPlayer.volume = (targetVol * (1f - progress)).coerceIn(0f, 1f)
                newPlayer.volume = (targetVol * progress).coerceIn(0f, 1f)
                step++
                handler.postDelayed(this, stepMs)
            }
        }
        crossfadeFadeRunnable = runnable
        handler.post(runnable)
    }

    private fun equalizerParameters(): Map<String, Any> {
        return try {
            val sessionId = player?.audioSessionId ?: 0
            val eq = equalizer ?: if (sessionId > 0) {
                Equalizer(0, sessionId).also { equalizer = it }
            } else {
                null
            }
            if (eq == null) {
                mapOf("minDecibels" to -15.0, "maxDecibels" to 15.0, "bands" to listOf(0, 1, 2, 3, 4))
            } else {
                mapOf(
                    "minDecibels" to eq.bandLevelRange[0] / 100.0,
                    "maxDecibels" to eq.bandLevelRange[1] / 100.0,
                    "bands" to List(eq.numberOfBands.toInt()) { it }
                )
            }
        } catch (e: Exception) {
            android.util.Log.e("Media3", "Equalizer params error", e)
            mapOf("minDecibels" to -15.0, "maxDecibels" to 15.0, "bands" to listOf(0, 1, 2, 3, 4))
        }
    }
    private fun nativeLog(level: String, msg: String) = NativeLogs.emit(level, "Media3", msg)

    companion object {
        var instance: Media3PlaybackService? = null
        private const val CHANNEL_ID      = "media3_playback"
        private const val NOTIFICATION_ID = 1001

        // Transport-control actions broadcast to the service via PendingIntent.
        const val ACTION_PLAY_PAUSE = "com.example.musicplayer.ACTION_PLAY_PAUSE"
        const val ACTION_SKIP_NEXT  = "com.example.musicplayer.ACTION_SKIP_NEXT"
        const val ACTION_SKIP_PREV  = "com.example.musicplayer.ACTION_SKIP_PREV"
        const val ACTION_STOP = "com.example.musicplayer.ACTION_STOP"
    }
    object Events {
        private val sinks = mutableMapOf<String, EventChannel.EventSink?>()
        fun handler(name: String) = object : EventChannel.StreamHandler { override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sinks[name] = events; instance?.emitAll() }; override fun onCancel(arguments: Any?) { sinks[name] = null } }
        fun emit(name: String, value: Any?) { sinks[name]?.success(value) }
    }
    object NativeLogs {
        private var sink: EventChannel.EventSink? = null
        fun handler() = object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        }
        fun emit(level: String, category: String, message: String) {
            sink?.success(mapOf("level" to level, "category" to category, "message" to message))
        }
    }
}
