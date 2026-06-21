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
import kotlin.math.sqrt
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
import kotlin.concurrent.thread
import org.json.JSONArray
import org.json.JSONObject
import java.util.IdentityHashMap
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class Media3PlaybackService : MediaSessionService() {

    // ── Dual-player fields ─────────────────────────────────────────────────────
    private var primaryPlayer: ExoPlayer? = null
    private var secondaryPlayer: ExoPlayer? = null
    private var activePlayer: ExoPlayer? = null
    private val player: ExoPlayer? get() = activePlayer

    private fun standbyPlayer(): ExoPlayer? =
        if (activePlayer === primaryPlayer) secondaryPlayer else primaryPlayer

    // ── Session / transport ────────────────────────────────────────────────────
    private var session: MediaSession? = null
    private var queue: List<Map<String, Any?>> = emptyList()
    private val handler = Handler(Looper.getMainLooper())
    private val positionUpdateMs = 200L

    // ── Audio focus ────────────────────────────────────────────────────────────
    private lateinit var audioManager: AudioManager
    private var focusRequest: AudioFocusRequest? = null
    private var hasAudioFocus = false
    private var resumeAfterFocusGain = false
    private var volumeBeforeDuck = 1f

    // ── Effects ────────────────────────────────────────────────────────────────
    private var equalizer: Equalizer? = null
    private var loudness: LoudnessEnhancer? = null
    private var eqEnabled = false
    private val bandGains = mutableMapOf<Short, Short>()
    private var loudnessEnabled = false
    private var loudnessTargetMb = 0f
    private var bassBoost: BassBoost? = null
    private var bassBoostStrength: Short = 0
    private var bassBoostEnabled: Boolean = false
    private var bassBoostSupported: Boolean = false
    private var virtualizer: Virtualizer? = null
    private var virtualizerStrength: Short = 1000
    private var virtualizerEnabled: Boolean = false
    private var virtualizerSupported: Boolean = false
    private var reverb: PresetReverb? = null
    private var reverbPreset: Short = 0
    private var reverbSupported: Boolean = false

    // ── Crossfade ──────────────────────────────────────────────────────────────
    private var crossfadeDurationSec: Float = 0f
    private var crossfadeFadeRunnable: Runnable? = null
    private var promotionTriggered = false
    private var crossfadeInProgress = false
    private var promotionOwner: ExoPlayer? = null
    private var preloadedQueueIndex = C.INDEX_UNSET
    private var activeQueueIndex = 0
    private val playerListeners = IdentityHashMap<ExoPlayer, Player.Listener>()

    // ── Sleep timer ────────────────────────────────────────────────────────────
    private var sleepTimerRunnable: Runnable? = null
    private var sleepTimerTickRunnable: Runnable? = null
    private var sleepTimerEndMs: Long = 0L
    private var sleepTimerActive: Boolean = false
    private var sleepEndOfSong: Boolean = false

    // ── Foreground guard ───────────────────────────────────────────────────────
    // Android 11 / MIUI 12: call startForeground() exactly ONCE per lifecycle.
    // All subsequent notification updates use NotificationManager.notify().
    private var isForeground = false

    // ── Effects handler ────────────────────────────────────────────────────────
    private var lastAttachedSessionId = -1
    private val effectHandler = Handler(Looper.getMainLooper())

    // ── Queue persistence keys ─────────────────────────────────────────────────
    companion object {
        const val CHANNEL_ID       = "media3_playback"
        const val NOTIFICATION_ID  = 1001
        const val ACTION_PLAY_PAUSE = "com.example.musicplayer.ACTION_PLAY_PAUSE"
        const val ACTION_SKIP_NEXT  = "com.example.musicplayer.ACTION_SKIP_NEXT"
        const val ACTION_SKIP_PREV  = "com.example.musicplayer.ACTION_SKIP_PREV"
        const val ACTION_STOP       = "com.example.musicplayer.ACTION_STOP"
        const val PREFS_NAME        = "media3_queue_prefs"
        const val KEY_QUEUE         = "queue_json"
        const val KEY_INDEX         = "queue_index"
        const val KEY_POS_MS        = "position_ms"
        const val KEY_REPEAT_MODE   = "repeat_mode"
        const val KEY_SHUFFLE       = "shuffle_enabled"

        @Volatile var instance: Media3PlaybackService? = null
    }

    // ── Position ticker ────────────────────────────────────────────────────────
    private val positionTicker = object : Runnable {
        override fun run() {
            emitAll(emitQueue = false)
            maybeCrossfadeOut()
            if (player?.isPlaying == true) {
                handler.postDelayed(this, positionUpdateMs)
            }
        }
    }

    private fun startPositionTicker() {
        handler.removeCallbacks(positionTicker)
        if (player?.isPlaying == true) handler.post(positionTicker)
    }

    private fun stopPositionTicker() {
        handler.removeCallbacks(positionTicker)
    }

    // ── Noisy receiver ─────────────────────────────────────────────────────────
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                player?.pause()
                stopPositionTicker()
                emitAll()
            }
        }
    }

    // ── Audio focus listener ───────────────────────────────────────────────────
    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { change ->
        val p = player ?: return@OnAudioFocusChangeListener
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                p.volume = volumeBeforeDuck
                if (resumeAfterFocusGain) {
                    resumeAfterFocusGain = false
                    p.play()
                    startPositionTicker()
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                resumeAfterFocusGain = p.isPlaying
                p.pause()
                stopPositionTicker()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                volumeBeforeDuck = p.volume
                p.volume = (p.volume * 0.25f).coerceAtMost(0.25f)
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeAfterFocusGain = false
                p.pause()
                stopPositionTicker()
                abandonAudioFocus()
            }
        }
        emitAll()
    }

    // ── Foreground service / notification ──────────────────────────────────────

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        when (intent?.action) {
            ACTION_PLAY_PAUSE -> {
                val p = player
                if (p != null) {
                    if (p.isPlaying) {
                        p.pause()
                        stopPositionTicker()
                        abandonAudioFocus()
                        nativeLog("info", "transport: pause (notification/BT)")
                    } else {
                        if (requestAudioFocus()) {
                            p.play()

                            ensureMediaForeground()
                            refreshNotification()
                            
                            startPositionTicker()
                            nativeLog("info", "transport: play (notification/BT)")
                        }
                    }
                    emitAll()
                    refreshNotification()
                }
            }
            ACTION_SKIP_NEXT -> {
    cancelSleepTimer()  // <-- tambahkan
    cancelCrossfade(resetVolume = true)
    clearStandbyQueue()
    player?.seekToNextMediaItem()
    nativeLog("info", "transport: skipNext (notification/BT)")
    emitAll()
    refreshNotification()
}
ACTION_SKIP_PREV -> {
    cancelSleepTimer()  // <-- tambahkan
    cancelCrossfade(resetVolume = true)
    clearStandbyQueue()
    player?.seekToPreviousMediaItem()
    nativeLog("info", "transport: skipPrev (notification/BT)")
    emitAll()
    refreshNotification()
}
            ACTION_STOP -> {
    cancelSleepTimer()
  nativeLog("info", "transport: stop (notification/BT)")

    cancelCrossfade(resetVolume = true)

    primaryPlayer?.pause()
    secondaryPlayer?.pause()

    primaryPlayer?.seekTo(0)
    secondaryPlayer?.seekTo(0)

    stopPositionTicker()
    abandonAudioFocus()

    stopForeground(STOP_FOREGROUND_REMOVE)
    // PATCH: isForeground gak direset → kalau service somehow re-entry sebelum
    // bener2 destroyed, refreshNotification() bakal salah pakai .notify() padahal
    // udah bukan foreground lagi (harus startForeground() ulang).
    isForeground = false

    getSystemService(NotificationManager::class.java)
        ?.cancel(NOTIFICATION_ID)
    emitAll()
    stopSelf()
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
        nativeLog("info", "onTaskRemoved — service continues (stopWithTask=false)")
    }

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

    // Called ONCE per lifecycle — satisfies Android 11's 5-second startForeground window.
    private fun ensureMediaForeground() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    if (isForeground) return

    val p = player ?: return
    ensureNotificationChannel()

    val sess = session
    val t = currentTrackMap()
    val title = t?.get("title") as? String ?: "Music Player"
    val artist = t?.get("artist") as? String ?: ""
    val isPlaying = p.isPlaying

    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
    val pendingIntent = if (launchIntent != null) {
        PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    } else null

    val builder = NotificationCompat.Builder(this, CHANNEL_ID)
        // PATCH: sebelumnya pakai android.R.drawable.ic_media_play di sini tapi
        // refreshNotification() pakai R.drawable.ic_notification → icon kedip ganti
        // begitu update pertama lewat refreshNotification(). Disamain.
        .setSmallIcon(R.drawable.ic_notification)
        .setContentTitle(title)
        .setContentText(artist)
        .setOngoing(true)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

    if (pendingIntent != null) {
        builder.setContentIntent(pendingIntent)
    }

    if (sess != null) {
        builder
            .addAction(NotificationCompat.Action(R.drawable.ic_prev, "Previous",
                buildTransportPendingIntent(ACTION_SKIP_PREV, 1)))
            .addAction(NotificationCompat.Action(
                if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play,
                if (isPlaying) "Pause" else "Play",
                buildTransportPendingIntent(ACTION_PLAY_PAUSE, 2)))
            .addAction(NotificationCompat.Action(R.drawable.ic_next, "Next",
                buildTransportPendingIntent(ACTION_SKIP_NEXT, 3)))
            .addAction(NotificationCompat.Action(R.drawable.ic_stop, "Stop",
                buildTransportPendingIntent(ACTION_STOP, 4)))
            .setStyle(
                MediaStyleNotificationHelper.MediaStyle(sess)
                    .setShowActionsInCompactView(0, 1, 2)
            )
    }

    val notification = builder.build()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(
            NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        )
    } else {
        startForeground(NOTIFICATION_ID, notification)
    }
    isForeground = true
}

    // For all subsequent notification updates — uses NotificationManager.notify()
    // to avoid repeated startForeground() calls (MIUI 12 / Android 11 safety).
    private fun refreshNotification() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val sess = session ?: return
    val p = player ?: return

    ensureNotificationChannel()

    val t = currentTrackMap()
    val title = t?.get("title") as? String ?: "Music Player"
    val artist = t?.get("artist") as? String ?: ""
    val isPlaying = p.isPlaying

    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
    val pendingIntent = if (launchIntent != null) {
        PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    } else null

    val builder = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_notification)
        .setContentTitle(title)
        .setContentText(artist)
        .setOngoing(isPlaying)
        .setOnlyAlertOnce(true)
        .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .addAction(NotificationCompat.Action(R.drawable.ic_prev, "Previous",
            buildTransportPendingIntent(ACTION_SKIP_PREV, 1)))
        .addAction(NotificationCompat.Action(
            if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play,
            if (isPlaying) "Pause" else "Play",
            buildTransportPendingIntent(ACTION_PLAY_PAUSE, 2)))
        .addAction(NotificationCompat.Action(R.drawable.ic_next, "Next",
            buildTransportPendingIntent(ACTION_SKIP_NEXT, 3)))
        .addAction(NotificationCompat.Action(R.drawable.ic_stop, "Stop",
            buildTransportPendingIntent(ACTION_STOP, 4)))
        .setStyle(
            MediaStyleNotificationHelper.MediaStyle(sess)
                .setShowActionsInCompactView(0, 1, 2)
        )

    if (pendingIntent != null) {
        builder.setContentIntent(pendingIntent)
    }

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
                }
            }
        } catch (_: Exception) {}
    }

    try {
        val notification = builder.build()
        if (!isForeground) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isForeground = true
        } else {
            getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, notification)
        }
    } catch (e: Exception) {
        nativeLog("warn", "refreshNotification failed: ${e.message}")
    }
}

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Music Playback",
                    NotificationManager.IMPORTANCE_LOW).apply {
                    setSound(null, null)
                    enableVibration(false)
                }
            )
        }
    }

    // ── Player factory ─────────────────────────────────────────────────────────

    private fun createConfiguredPlayer(): ExoPlayer = ExoPlayer.Builder(this).build().apply {
        val attrs = androidx.media3.common.AudioAttributes.Builder()
            .setUsage(androidx.media3.common.C.USAGE_MEDIA)
            .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()
        setAudioAttributes(attrs, false)
        setHandleAudioBecomingNoisy(true)
    }

    // ── Player listeners ───────────────────────────────────────────────────────

    private fun attachPlayerListener(player: ExoPlayer) {
        detachPlayerListener(player)
        val listener = object : Player.Listener {
            private fun isActiveEvent(): Boolean = player === activePlayer

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (!isActiveEvent()) return
                emitAll()
                refreshNotification()
                if (playbackState == Player.STATE_READY && crossfadeDurationSec > 0f) {
                    preloadNextTrack()
                }
                
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (!isActiveEvent()) return
                if (isPlaying) startPositionTicker() else stopPositionTicker()
                emitAll()
                refreshNotification()
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
    nativeLog("debug", "Player transition reason=$reason active=${player === activePlayer}")
    if (player === promotionOwner && crossfadeInProgress) {
        nativeLog("debug", "Ignored transition from old player during promotion")
        return
    }
    if (!isActiveEvent()) return

    // Jika user mengubah lagu secara manual (bukan auto), batalkan sleep timer end-of-song
    if (reason != Player.MEDIA_ITEM_TRANSITION_REASON_AUTO && sleepTimerActive && sleepEndOfSong) {
        cancelSleepTimer()
    }

    // End-of-song sleep timer: hanya jika transisi AUTO dan mode end-of-song aktif
    if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO && sleepEndOfSong && sleepTimerActive) {
        nativeLog("info", "Sleep timer (end-of-song): stopping at track boundary")
        handler.post { triggerSleepStop() }
        return  // keluar agar tidak lanjut ke logika di bawah
    }

    if (!crossfadeInProgress && player.currentMediaItemIndex >= 0) {
        activeQueueIndex = player.currentMediaItemIndex
        promotionTriggered = false
        if (crossfadeDurationSec > 0f) preloadNextTrack(force = true)
    }
    saveQueueToPrefs()
    emitAll()
    refreshNotification()
}
            override fun onShuffleModeEnabledChanged(
    shuffleModeEnabled: Boolean
) {
    if (!isActiveEvent()) return

    Events.emit("shuffleMode", shuffleModeEnabled)
    saveQueueToPrefs()
}

            override fun onRepeatModeChanged(repeatMode: Int) {
    if (!isActiveEvent()) return

    val repeat = when (repeatMode) {
        Player.REPEAT_MODE_ONE -> "one"
        Player.REPEAT_MODE_ALL -> "all"
        else -> "off"
    }

    Events.emit("repeatMode", repeat)
    saveQueueToPrefs()
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

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        primaryPlayer = createConfiguredPlayer()
        activePlayer  = primaryPlayer
        attachPlayerListener(primaryPlayer!!)

        // PATCH: sebelumnya launchIntent gak di-null-check di sini (beda sama
        // ensureMediaForeground()/refreshNotification() yang udah benar) → berpotensi
        // NPE/crash kalau packageManager.getLaunchIntentForPackage() return null.
        val launchIntent   = packageManager.getLaunchIntentForPackage(packageName)
        val sessionBuilder = MediaSession.Builder(this, primaryPlayer!!)
        if (launchIntent != null) {
            val pendingIntent = PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            sessionBuilder.setSessionActivity(pendingIntent)
        }
        session = sessionBuilder.build()

        registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        instance = this

     // Restore persisted queue so music continues after app restart.
restoreQueueFromPrefs()

nativeLog(
    "info",
    "onCreate: ExoPlayer ready (Android SDK ${Build.VERSION.SDK_INT} / MIUI=${isMiui()})"
)
emitAll()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onDestroy() {
        cancelCrossfade(resetVolume = true) 
        nativeLog("info", "onDestroy: releasing resources")
        saveQueueToPrefs()
        cancelSleepTimer()
        effectHandler.removeCallbacksAndMessages(null)
        handler.removeCallbacks(positionTicker)
        try { unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
        abandonAudioFocus()
        releaseEffects()
        instance = null
        primaryPlayer?.release()
        secondaryPlayer?.release()
        primaryPlayer  = null
        secondaryPlayer = null
        activePlayer   = null
        session?.release()
        session = null
        super.onDestroy()
    }

    // ── Queue persistence ──────────────────────────────────────────────────────

    private fun saveQueueToPrefs() {
    if (queue.isEmpty()) return

    // ambil snapshot di main thread dulu
    val p = player
    val idx = if (crossfadeDurationSec > 0f)
        activeQueueIndex
    else
        (p?.currentMediaItemIndex ?: activeQueueIndex)

    val posMs = p?.currentPosition?.coerceAtLeast(0L) ?: 0L
    val repeatMode = p?.repeatMode ?: Player.REPEAT_MODE_OFF
    val shuffle = p?.shuffleModeEnabled ?: false
    // PATCH: sebelumnya thread { } baca property `queue` langsung, bukan snapshot →
    // kalau ada mutasi queue (insertNext/removeFromQueue/dst) pas background thread
    // belum sempat jalan, data yang ke-save bisa gak sinkron sama idx/posMs di atas.
    val queueSnapshot = queue

    thread {
        try {
            val arr = JSONArray()

            for (song in queueSnapshot) {
                val obj = JSONObject()

                for ((k, v) in song) {
                    when (v) {
                        null -> obj.put(k, JSONObject.NULL)
                        is Number -> obj.put(k, v)
                        is Boolean -> obj.put(k, v)
                        else -> obj.put(k, v.toString())
                    }
                }

                arr.put(obj)
            }

            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_QUEUE, arr.toString())
                .putInt(
                    KEY_INDEX,
                    idx.coerceIn(0, (queueSnapshot.size - 1).coerceAtLeast(0))
                )
                .putLong(KEY_POS_MS, posMs)
                .putInt(KEY_REPEAT_MODE, repeatMode)
                .putBoolean(KEY_SHUFFLE, shuffle)
                .apply()

        } catch (e: Exception) {
            handler.post {
                nativeLog("warn", "saveQueueToPrefs: ${e.message}")
            }
        }
    }
}
    private fun restoreQueueFromPrefs() {
        try {
            val prefs    = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val json     = prefs.getString(KEY_QUEUE, null) ?: return
            val savedIdx = prefs.getInt(KEY_INDEX, 0)
            val savedPos = prefs.getLong(KEY_POS_MS, 0L)
            val savedRepeat  = prefs.getInt(KEY_REPEAT_MODE, Player.REPEAT_MODE_OFF)
            val savedShuffle = prefs.getBoolean(KEY_SHUFFLE, false)

            val arr   = JSONArray(json)
            val items = mutableListOf<Map<String, Any?>>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val map = mutableMapOf<String, Any?>()
                for (key in obj.keys()) {
                    val v = obj.get(key)
                    map[key] = if (v == JSONObject.NULL) null else v
                }
                items.add(map)
            }
            if (items.isEmpty()) return

            queue = items
            activeQueueIndex = savedIdx.coerceIn(0, (items.size - 1).coerceAtLeast(0))

            val p = player ?: return
            p.setMediaItems(items.map { mediaItemFrom(it) }, activeQueueIndex, savedPos)
            p.repeatMode         = savedRepeat
            p.shuffleModeEnabled = savedShuffle
            p.prepare()
            // Do NOT call play() — restored in paused state; user resumes manually.

            nativeLog("info",
                "Restored queue: ${items.size} tracks idx=$activeQueueIndex pos=${savedPos}ms " +
                "repeat=$savedRepeat shuffle=$savedShuffle")
            emitAll(emitQueue = true)
        } catch (e: Exception) {
            nativeLog("warn", "restoreQueueFromPrefs: ${e.message}")
        }
    }

    // ── Sleep timer ────────────────────────────────────────────────────────────

    private fun startSleepTimerDuration(durationMs: Long) {
        cancelSleepTimerInternal()
        if (durationMs <= 0L) return
        sleepTimerActive  = true
        sleepEndOfSong    = false
        sleepTimerEndMs   = System.currentTimeMillis() + durationMs

        // Tick every second so Dart can show a live countdown.
        val tick = object : Runnable {
            override fun run() {
                if (!sleepTimerActive) return
                emitSleepTimer()
                handler.postDelayed(this, 1000L)
            }
        }
        sleepTimerTickRunnable = tick
        handler.postDelayed(tick, 1000L)

        sleepTimerRunnable = Runnable { triggerSleepStop() }
        handler.postDelayed(sleepTimerRunnable!!, durationMs)

        emitSleepTimer()
        nativeLog("info", "Sleep timer started: ${durationMs}ms")
    }

    private fun startSleepTimerEndOfSong() {
        cancelSleepTimerInternal()
        sleepTimerActive = true
        sleepEndOfSong   = true
        sleepTimerEndMs  = 0L
        emitSleepTimer()
        nativeLog("info", "Sleep timer: end-of-song mode")
    }

    private fun triggerSleepStop() {
    if (!sleepTimerActive) return  // <-- tambahkan guard
    nativeLog("info", "Sleep timer fired — pausing")
    player?.pause()
    stopPositionTicker()
    cancelSleepTimerInternal()
    emitAll()
}

    private fun checkEndOfSongSleepTimer() {
        if (sleepTimerActive && sleepEndOfSong) {
            nativeLog("info", "Sleep timer (end-of-song): STATE_ENDED → stopping")
            triggerSleepStop()
        }
    }

    private fun cancelSleepTimerInternal() {
        sleepTimerRunnable?.let { handler.removeCallbacks(it) }
        sleepTimerTickRunnable?.let { handler.removeCallbacks(it) }
        sleepTimerRunnable     = null
        sleepTimerTickRunnable = null
        sleepTimerActive  = false
        sleepEndOfSong    = false
        sleepTimerEndMs   = 0L
    }

    private fun cancelSleepTimer() {
    if (!sleepTimerActive) {
        nativeLog("verbose", "cancelSleepTimer called but no active timer")
        return
    }
    cancelSleepTimerInternal()
    emitSleepTimer()
    nativeLog("info", "Sleep timer cancelled")
}

    private fun emitSleepTimer() {
        val remaining = if (sleepTimerActive && !sleepEndOfSong) {
            (sleepTimerEndMs - System.currentTimeMillis()).coerceAtLeast(0L)
        } else 0L
        Events.emit("sleepTimer", mapOf(
            "active"      to sleepTimerActive,
            "endOfSong"   to sleepEndOfSong,
            "remainingMs" to remaining,
        ))
    }

    // ── State emission ─────────────────────────────────────────────────────────

    private fun emitAll(emitQueue: Boolean = false) {
        val p = player ?: return
        val state = when (p.playbackState) {
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_READY     -> "ready"
            Player.STATE_ENDED     -> "completed"
            else                   -> "idle"
        }
        val repeatStr = when (p.repeatMode) {
            Player.REPEAT_MODE_ONE -> "one"
            Player.REPEAT_MODE_ALL -> "all"
            else                   -> "off"
        }
        Events.emit("playbackState",  mapOf("playing" to p.isPlaying, "processingState" to state))
        Events.emit("bufferingState", p.playbackState == Player.STATE_BUFFERING)
        Events.emit("position",       p.currentPosition.coerceAtLeast(0L))
        Events.emit("duration",       p.duration.coerceAtLeast(0L))
        Events.emit("currentTrack",   currentTrackMap())
        // PATCH: repeatStr dihitung tapi sebelumnya gak pernah di-emit (dead code) →
        // Dart-side gak ke-sync soal repeatMode kecuali pas listener onRepeatModeChanged nyala.
        Events.emit("repeatMode",     repeatStr)
        
        if (emitQueue) Events.emit("queue", queue)
        Events.emit("audioSessionId", p.audioSessionId)
        emitSleepTimer()
    }

    private fun currentTrackMap(): Map<String, Any?>? {
        val p     = player ?: return null
        val index = if (crossfadeDurationSec > 0f) activeQueueIndex else p.currentMediaItemIndex
        val songMap = queue.getOrNull(index) ?: return null
        val albumId = (songMap["albumId"] as? Number)?.toLong() ?: 0L
        val artUri  = if (albumId > 0) "content://media/external/audio/albumart/$albumId" else null
        return songMap + mapOf("index" to index, "artworkUri" to artUri)
    }

    // ── Media item builder ─────────────────────────────────────────────────────

    private fun mediaItemFrom(map: Map<*, *>): MediaItem {
        val path = map["path"] as? String ?: ""
        val uri  = if (path.startsWith("content://") || path.startsWith("file://"))
            path.toUri() else Uri.fromFile(java.io.File(path))

        val albumId    = (map["albumId"] as? Number)?.toLong() ?: 0L
        val artworkUri = if (albumId > 0)
            Uri.parse("content://media/external/audio/albumart/$albumId") else null

        val metaBuilder = MediaMetadata.Builder()
            .setTitle(map["title"] as? String)
            .setArtist(map["artist"] as? String)
            .setAlbumTitle(map["album"] as? String)
        if (artworkUri != null) metaBuilder.setArtworkUri(artworkUri)

        return MediaItem.Builder()
            .setMediaId((map["id"] ?: path).toString())
            .setUri(uri)
            .setMediaMetadata(metaBuilder.build())
            .build()
    }

    // ── MethodChannel handler ──────────────────────────────────────────────────

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        // Sleep timer methods do not require an active player.
        when (call.method) {
            "setSleepTimer" -> {
                val ms = call.argument<Number>("durationMs")?.toLong() ?: 0L
                startSleepTimerDuration(ms)
                result.success(null); return
            }
            "setSleepTimerEndOfSong" -> {
                startSleepTimerEndOfSong()
                result.success(null); return
            }
            "cancelSleepTimer" -> {
                cancelSleepTimer()
                result.success(null); return
            }
        }

        val p = player ?: return result.error("not_ready", "Media3 service is not ready", null)

        when (call.method) {

            // ── Transport ────────────────────────────────────────────────────────
            "play" -> {
                val granted = requestAudioFocus()
                if (granted) {
                    p.play()
                  
                    ensureMediaForeground()
                    refreshNotification()   
                    
                    startPositionTicker()
                    val t = currentTrackMap()
                    nativeLog("info", "play → '${t?.get("title")}' · ${t?.get("artist")} " +
                        "[${p.currentMediaItemIndex + 1}/${queue.size}]")
                } else {
                    nativeLog("warn", "play: audio focus denied")
                }
                result.success(null)
            }

            "pause" -> {
                p.pause()
                stopPositionTicker()
                abandonAudioFocus()
                nativeLog("info", "pause @ ${p.currentPosition}ms")
                result.success(null)
            }

            "stop" -> {
                p.stop()
                stopPositionTicker()
                abandonAudioFocus()
                nativeLog("info", "stop")
                result.success(null)
            }

            "seek" -> {
                val pos = (call.argument<Number>("position")?.toLong() ?: 0L).coerceAtLeast(0L)
                p.seekTo(pos)
                nativeLog("verbose", "seek → ${pos}ms")
                result.success(null)
            }

            "skipPrevious" -> {
    cancelSleepTimer()
    cancelCrossfade(resetVolume = true)
    clearStandbyQueue()
    
    if (p.playbackState == Player.STATE_ENDED) {
        val prevIndex = p.previousMediaItemIndex
        if (prevIndex != C.INDEX_UNSET) {
            p.seekToDefaultPosition(prevIndex)
            p.prepare()
            emitAll()              // <-- TAMBAHKAN
            refreshNotification()  // <-- TAMBAHKAN
            if (!hasAudioFocus) {
                p.pause()
            }
            nativeLog("info", "skipPrevious (from ENDED) → index $prevIndex")
        } else {
            if (p.mediaItemCount > 0) {
                p.seekToDefaultPosition(0)
                p.prepare()
                emitAll()              // <-- TAMBAHKAN
                refreshNotification()  // <-- TAMBAHKAN
                nativeLog("info", "skipPrevious (ENDED, no prev) → restart queue")
            } else {
                nativeLog("warn", "skipPrevious: no previous item, queue empty")
            }
        }
    } else {
        p.seekToPreviousMediaItem()
    }
    result.success(null)
}

"skipNext" -> {
    cancelSleepTimer()
    cancelCrossfade(resetVolume = true)
    clearStandbyQueue()
    
    // Jika player sudah di STATE_ENDED, set ke next secara manual
    if (p.playbackState == Player.STATE_ENDED) {
        val nextIndex = p.nextMediaItemIndex
        if (nextIndex != C.INDEX_UNSET) {
            p.seekToDefaultPosition(nextIndex)
            p.prepare()
            emitAll()              // <-- TAMBAHKAN
            refreshNotification() 
            if (!hasAudioFocus) {
                p.pause()
            }
            nativeLog("info", "skipNext (from ENDED) → index $nextIndex")
        } else {
            // Tidak ada next item, restart dari awal jika queue tidak kosong
            if (p.mediaItemCount > 0) {
                p.seekToDefaultPosition(0)
                p.prepare()
                emitAll()              // <-- TAMBAHKAN
                refreshNotification() 
                nativeLog("info", "skipNext (ENDED, no next) → restart queue")
            } else {
                nativeLog("warn", "skipNext: no next item, queue empty")
            }
        }
    } else {
        p.seekToNextMediaItem()
    }
    result.success(null)
}

            // ── Queue management ─────────────────────────────────────────────────

            "setQueue" -> {
                cancelSleepTimer()  
                @Suppress("UNCHECKED_CAST")
                val items = call.argument<List<Map<String, Any?>>>("queue") ?: emptyList()
                val index = call.argument<Number>("index")?.toInt() ?: 0

                queue = items
                activeQueueIndex = index.coerceIn(0, (items.size - 1).coerceAtLeast(0))

                cancelCrossfade(resetVolume = true)
                releaseStandbyPlayer()

                p.setMediaItems(items.map { mediaItemFrom(it) }, activeQueueIndex, 0L)
                p.prepare()
                if (crossfadeDurationSec > 0f) preloadNextTrack()

                saveQueueToPrefs()

                val firstTitle = items.getOrNull(index)?.get("title") as? String ?: "?"
                nativeLog("info", "setQueue: ${items.size} tracks → [$index] '$firstTitle'")
                emitAll(emitQueue = true)
                refreshNotification()
                result.success(null)
            }

            "setTrack" -> {
                cancelSleepTimer()  
                val target = (call.argument<Number>("index")?.toInt() ?: 0)
                    .coerceIn(0, (queue.size - 1).coerceAtLeast(0))
                cancelCrossfade(resetVolume = true)
                clearStandbyQueue()
                activeQueueIndex = target
                p.seekToDefaultPosition(target)
                if (crossfadeDurationSec > 0f) preloadNextTrack()
                saveQueueToPrefs()
                result.success(null)
            }

            // ── Queue mutations (native owns queue, mutations sync immediately) ──

            "insertNext" -> {
    // PATCH: tipe sebelumnya Map<String, Any> gak konsisten sama tipe queue
    // (List<Map<String, Any?>>) — field kayak albumId/artworkUri boleh null.
    val item = call.argument<Map<String, Any?>>("item") ?: run { result.success(null); return }
    val mutable = queue.toMutableList()
    
    // Pake +1 ini udah standar industri beb, paling logis buat UX
    val insertIdx = (activeQueueIndex + 1).coerceIn(0, queue.size)
    
    mutable.add(insertIdx, item)
    queue = mutable
    
    // Kunci buat jaga biar ga crash pas transisi
    if (!crossfadeInProgress) {
        p.addMediaItem(insertIdx, mediaItemFrom(item))
    } else {
        nativeLog("info", "insertNext: list updated, skipping p.addMediaItem for safety")
    }

    saveQueueToPrefs()
    emitAll(emitQueue = true)
    result.success(null)
}

            "appendToQueue" -> {
    // PATCH: sama kayak insertNext, samain tipe ke Any? biar konsisten.
    val item = call.argument<Map<String, Any?>>("item") ?: run { result.success(null); return }
    val mutable = queue.toMutableList()
    mutable.add(item)
    queue = mutable
    
    // KUNCI DISINI JUGA (ノಠ益ಠ)ノ
    if (!crossfadeInProgress) {
        p.addMediaItem(mediaItemFrom(item))
    } else {
        nativeLog("warn", "skip appendToQueue ke exoplayer, lagi crossfade beb")
    }

    if (crossfadeDurationSec > 0f) preloadNextTrack(force = true)
    saveQueueToPrefs()
    emitAll(emitQueue = true)
    result.success(null)
}


            "removeFromQueue" -> {
    val index = call.argument<Number>("index")?.toInt() ?: run { result.success(null); return }
    if (index !in queue.indices) { result.success(null); return }

    val mutable = queue.toMutableList()
    mutable.removeAt(index)
    queue = mutable

    if (index < activeQueueIndex) {
        activeQueueIndex--
    } else if (index == activeQueueIndex) {
        if (queue.isEmpty()) {
            activeQueueIndex = 0
        } else if (activeQueueIndex >= queue.size) {
            activeQueueIndex = queue.size - 1
        }
    }

    if (activeQueueIndex !in queue.indices) {
        activeQueueIndex = (queue.size - 1).coerceAtLeast(0)
    }

    if (!crossfadeInProgress) {
        p.removeMediaItem(index)
    } else {
        nativeLog("warn", "skip removeMediaItem ke exoplayer, lagi crossfade beb")
    }

    if (crossfadeDurationSec > 0f) preloadNextTrack(force = true)
    saveQueueToPrefs()
    emitAll(emitQueue = true)
    nativeLog("info", "removeFromQueue: idx=$index remaining=${queue.size}")
    result.success(null)
}

            "reorderQueue" -> {
    val oldIndex = call.argument<Number>("oldIndex")?.toInt() ?: run { result.success(null); return }
    val newIndex = call.argument<Number>("newIndex")?.toInt() ?: run { result.success(null); return }

    if (oldIndex !in queue.indices || newIndex !in queue.indices || oldIndex == newIndex) {
        result.success(null); return
    }

    val mutable = queue.toMutableList()
    val item = mutable.removeAt(oldIndex)
    mutable.add(newIndex, item)
    queue = mutable

    if (!crossfadeInProgress) {
        p.moveMediaItem(oldIndex, newIndex)
    } else {
        nativeLog("warn", "skip moveMediaItem ke exoplayer, lagi crossfade beb")
    }

    activeQueueIndex = when {
        oldIndex == activeQueueIndex -> newIndex
        oldIndex < activeQueueIndex && newIndex >= activeQueueIndex -> activeQueueIndex - 1
        oldIndex > activeQueueIndex && newIndex <= activeQueueIndex -> activeQueueIndex + 1
        else -> activeQueueIndex
    }

    if (activeQueueIndex !in queue.indices) {
        activeQueueIndex = (queue.size - 1).coerceAtLeast(0)
    }

    if (crossfadeDurationSec > 0f) preloadNextTrack(force = true)
    saveQueueToPrefs()
    emitAll(emitQueue = true)
    nativeLog("info", "reorderQueue: [$oldIndex] → [$newIndex]")
    result.success(null)
}

            // ── Playback modes ───────────────────────────────────────────────────

            "setRepeatMode" -> {
                p.repeatMode = when (call.argument<String>("mode")) {
                    "one" -> Player.REPEAT_MODE_ONE
                    "all" -> Player.REPEAT_MODE_ALL
                    else  -> Player.REPEAT_MODE_OFF
                }
                clearStandbyQueue()
                if (crossfadeDurationSec > 0f) preloadNextTrack(force = true)
                saveQueueToPrefs()
                emitAll(emitQueue = true)
                result.success(null)
            }

            "setShuffleMode" -> {
                p.shuffleModeEnabled = call.argument<Boolean>("enabled") ?: false
                clearStandbyQueue()
                if (crossfadeDurationSec > 0f) preloadNextTrack(force = true)
                saveQueueToPrefs()
                emitAll(emitQueue = true)
                result.success(null)
            }

            "setVolume" -> {
                p.volume        = (call.argument<Number>("volume")?.toFloat() ?: 1f).coerceIn(0f, 1f)
                volumeBeforeDuck = p.volume
                result.success(null)
            }

            // ── Playback parameters ──────────────────────────────────────────────

            "setSpeed" -> {
                val speed = (call.argument<Number>("speed")?.toFloat() ?: 1f).coerceIn(0.25f, 4f)
                p.playbackParameters = PlaybackParameters(speed, p.playbackParameters.pitch)
                result.success(null)
            }

            "setPitch" -> {
                val pitch = (call.argument<Number>("pitch")?.toFloat() ?: 1f).coerceIn(0.5f, 2f)
                p.playbackParameters = PlaybackParameters(p.playbackParameters.speed, pitch)
                result.success(null)
            }

            // ── Effects ──────────────────────────────────────────────────────────

            "setEqualizerEnabled"   -> { setEqualizerEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }
            "setEqualizerBandGain"  -> {
                setEqualizerBandGain(
                    (call.argument<Number>("band")?.toInt() ?: 0).toShort(),
                    ((call.argument<Number>("gainDb")?.toDouble() ?: 0.0) * 100).toInt().toShort()
                )
                result.success(null)
            }
            "setLoudnessTargetGain" -> { setLoudnessTargetGain(call.argument<Number>("gainMb")?.toFloat() ?: 0f); result.success(null) }
            "setLoudnessEnabled"    -> { setLoudnessEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }

            "setTrackGain" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val gainMb  = (call.argument<Number>("gainDb")?.toFloat() ?: 0f) * 100f
                setLoudnessTargetGain(gainMb)
                setLoudnessEnabled(enabled)
                result.success(null)
            }

            "setBassBoostEnabled"    -> { nativeBassBoostEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }
            "setBassBoostStrength"   -> { nativeBassBoostStrength((call.argument<Number>("strength")?.toInt() ?: 0).toShort()); result.success(null) }
            "setVirtualizerEnabled"  -> { nativeVirtualizerEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }
            "setVirtualizerStrength" -> { nativeVirtualizerStrength((call.argument<Number>("strength")?.toInt() ?: 1000).toShort()); result.success(null) }
            "setReverbPreset"        -> { nativeReverbPreset((call.argument<Number>("preset")?.toInt() ?: 0).toShort()); result.success(null) }

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

            // ── Query ────────────────────────────────────────────────────────────

            "getEffectSupport" -> result.success(mapOf(
                "virtualizerSupported" to virtualizerSupported,
                "bassBoostSupported"   to bassBoostSupported,
                "reverbSupported"      to reverbSupported,
            ))

            "getEqualizerParameters" -> result.success(equalizerParameters())

            "getPlaybackSnapshot" -> {
                val state = when (p.playbackState) {
                    Player.STATE_BUFFERING -> "buffering"
                    Player.STATE_READY     -> "ready"
                    Player.STATE_ENDED     -> "completed"
                    else                   -> "idle"
                }
                val repeatStr = when (p.repeatMode) {
                    Player.REPEAT_MODE_ONE -> "one"
                    Player.REPEAT_MODE_ALL -> "all"
                    else                   -> "off"
                }
                result.success(mapOf(
                    "queue"            to queue,
                    "currentIndex"     to (if (crossfadeDurationSec > 0f) activeQueueIndex
                                         else p.currentMediaItemIndex),
                    "isPlaying"        to p.isPlaying,
                    "processingState"  to state,
                    "positionMs"       to p.currentPosition.coerceAtLeast(0L),
                    "durationMs"       to p.duration.coerceAtLeast(0L),
                    "audioSessionId"   to p.audioSessionId,
                    "shuffleEnabled"   to p.shuffleModeEnabled,
                    "repeatMode"       to repeatStr,
                    "sleepTimerActive" to sleepTimerActive,
                    "sleepTimerRemainingMs" to if (sleepTimerActive && !sleepEndOfSong)
                        (sleepTimerEndMs - System.currentTimeMillis()).coerceAtLeast(0L)
                    else 0L,
                ))
            }

            else -> result.notImplemented()
        }

        if (call.method != "getPlaybackSnapshot" && call.method != "getEqualizerParameters") {
            emitAll()
        }
    }

    // ── Audio focus ────────────────────────────────────────────────────────────

    private fun requestAudioFocus(): Boolean {
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

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusChangeListener)
        }
        focusRequest  = null
        hasAudioFocus = false
    }

    // ── Audio effects ──────────────────────────────────────────────────────────

    private fun attachEffects(sessionId: Int, attempt: Int = 0) {
        if (sessionId <= 0) return
        if (sessionId == lastAttachedSessionId) {
            nativeLog("verbose", "attachEffects skipped session=$sessionId")
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
            nativeLog("warn", "Equalizer init failed (session=$sessionId a${attempt + 1}): ${e.message}")
        }

        try {
            loudness = LoudnessEnhancer(sessionId).apply {
                setTargetGain(loudnessTargetMb.toInt())
                enabled = loudnessEnabled
            }
            leOk = true
        } catch (e: Exception) {
            nativeLog("warn", "LoudnessEnhancer init failed (session=$sessionId a${attempt + 1}): ${e.message}")
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
                nativeLog("warn", "BassBoost init failed (a${attempt + 1}): ${e.message}")
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
                nativeLog("warn", "Virtualizer init failed (a${attempt + 1}): ${e.message}")
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
                nativeLog("warn", "PresetReverb init failed (a${attempt + 1}): ${e.message}")
            }
        }

        if (eqOk || leOk) {
            lastAttachedSessionId = sessionId
            nativeLog("info",
                "attachEffects(session=$sessionId) ok a${attempt + 1} " +
                "bass=$bassBoostSupported virt=$virtualizerSupported reverb=$reverbSupported")
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

    private fun setEqualizerEnabled(enabled: Boolean)          { eqEnabled = enabled; try { equalizer?.enabled = enabled } catch (_: Exception) {} }
    private fun setEqualizerBandGain(band: Short, gain: Short) {
        bandGains[band] = gain
        try { equalizer?.let { it.setBandLevel(band, gain.coerceIn(it.bandLevelRange[0], it.bandLevelRange[1])) } } catch (_: Exception) {}
    }
    private fun setLoudnessTargetGain(gainMb: Float) { loudnessTargetMb = gainMb; try { loudness?.setTargetGain(gainMb.toInt()) } catch (_: Exception) {} }
    private fun setLoudnessEnabled(enabled: Boolean) { loudnessEnabled = enabled; try { loudness?.enabled = enabled } catch (_: Exception) {} }

    private fun nativeBassBoostEnabled(enabled: Boolean)      { bassBoostEnabled = enabled; try { bassBoost?.enabled = enabled } catch (_: Exception) {} }
    private fun nativeBassBoostStrength(strength: Short)      {
        bassBoostStrength = strength
        try { bassBoost?.setStrength(strength) } catch (_: Exception) {}
        if (bassBoostEnabled != (strength > 0)) nativeBassBoostEnabled(strength > 0)
    }
    private fun nativeVirtualizerEnabled(enabled: Boolean)    {
        virtualizerEnabled = enabled
        try { virtualizer?.run { if (enabled) { setStrength(virtualizerStrength); this.enabled = true } else { this.enabled = false } } } catch (_: Exception) {}
    }
    private fun nativeVirtualizerStrength(strength: Short)    { virtualizerStrength = strength; try { if (virtualizerEnabled) virtualizer?.setStrength(strength) } catch (_: Exception) {} }
    private fun nativeReverbPreset(preset: Short)             {
        reverbPreset = preset
        try { reverb?.run { this.preset = toAndroidReverbPreset(preset); this.enabled = preset > 0 } } catch (_: Exception) {}
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

    private fun isEffectTypeAvailable(type: java.util.UUID): Boolean =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) true
        else try { AudioEffect.queryEffects()?.any { it.type == type } ?: false } catch (_: Exception) { false }

    private fun equalizerParameters(): Map<String, Any> = try {
    val sessionId = player?.audioSessionId ?: 0
    if (sessionId <= 0) {
        mapOf(
            "minDecibels" to -15.0,
            "maxDecibels" to 15.0,
            "bands" to listOf(0, 1, 2, 3, 4)
        )
    } else {
        val temp = if (equalizer == null) Equalizer(0, sessionId) else null
        val eq = equalizer ?: temp
        if (eq == null) {
            mapOf(
                "minDecibels" to -15.0,
                "maxDecibels" to 15.0,
                "bands" to listOf(0, 1, 2, 3, 4)
            )
        } else {
            val result = mapOf(
                "minDecibels" to eq.bandLevelRange[0] / 100.0,
                "maxDecibels" to eq.bandLevelRange[1] / 100.0,
                "bands" to List(eq.numberOfBands.toInt()) { it }
            )
            if (temp != null) {
                try { temp.release() } catch (_: Exception) {}
            }
            result
        }
    }
} catch (_: Exception) {
    mapOf(
        "minDecibels" to -15.0,
        "maxDecibels" to 15.0,
        "bands" to listOf(0, 1, 2, 3, 4)
    )
}

    // ── Crossfade helpers ──────────────────────────────────────────────────────

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
            try { standby.pause() }           catch (_: Exception) {}
            try { standby.stop() }            catch (_: Exception) {}
            try { standby.clearMediaItems() } catch (_: Exception) {}
        }
        preloadedQueueIndex = C.INDEX_UNSET
    }

    private fun releaseStandbyPlayer() {
        val standby = standbyPlayer() ?: return
        detachPlayerListener(standby)
        try { standby.release() } catch (_: Exception) {}
        if (standby === primaryPlayer)  primaryPlayer  = null
        if (standby === secondaryPlayer) secondaryPlayer = null
        preloadedQueueIndex = C.INDEX_UNSET
    }

    private fun cancelCrossfade(resetVolume: Boolean) {
        crossfadeFadeRunnable?.let { handler.removeCallbacks(it) }
        crossfadeFadeRunnable = null
        crossfadeInProgress   = false
        promotionTriggered    = false
        promotionOwner        = null
        if (resetVolume) player?.volume = volumeBeforeDuck
    }

    private fun preloadNextTrack(force: Boolean = false) {
        if (crossfadeDurationSec <= 0f || queue.isEmpty()) return
        val current = activePlayer ?: return
        val standby = ensureStandbyPlayer() ?: return
        if (standby === current) return

        val nextIndex = current.nextMediaItemIndex
        if (nextIndex == C.INDEX_UNSET || nextIndex !in queue.indices) {
            clearStandbyQueue(); return
        }
        if (!force && standby.mediaItemCount > 0 && preloadedQueueIndex == nextIndex) return

        try {
            standby.pause()
            standby.stop()
            standby.clearMediaItems()
            standby.volume              = 0f
            standby.repeatMode          = current.repeatMode
            standby.shuffleModeEnabled  = current.shuffleModeEnabled
            standby.playbackParameters  = current.playbackParameters
            standby.setMediaItem(mediaItemFrom(queue[nextIndex]))
            standby.prepare()
            preloadedQueueIndex = nextIndex
            nativeLog("info", "preloadNextTrack → [$nextIndex] '${queue[nextIndex]["title"]}'")
        } catch (e: Exception) {
            preloadedQueueIndex = C.INDEX_UNSET
            nativeLog("warn", "preloadNextTrack failed: ${e.message}")
        }
    }

    private fun maybeCrossfadeOut() {
    if (crossfadeDurationSec <= 0f || promotionTriggered || crossfadeInProgress) return
    val p   = player ?: return
    val dur = p.duration
    if (dur <= 0L || dur == Long.MIN_VALUE || dur == C.TIME_UNSET) return
    if (!p.hasNextMediaItem()) return

    preloadNextTrack()
    val standby = standbyPlayer() ?: return
    if (standby.mediaItemCount == 0) return

    val crossMs   = (crossfadeDurationSec * 1000f).toLong().coerceAtLeast(250L)
    val bufferMs  = 200L
    val remaining = dur - p.currentPosition

    // ── SYARAT: sisa waktu tidak boleh 0, dan ≤ crossMs + buffer ──
    if (remaining in 1L..(crossMs + bufferMs)) {
        // Hitung durasi fade sebenarnya = min(crossMs, remaining)
        val actualFadeMs = minOf(crossMs, remaining)
        nativeLog("info", "Triggering crossfade: remaining=${remaining}ms, actualFade=${actualFadeMs}ms")
        promoteSecondaryPlayer(actualFadeMs)
    }
}

    private fun promoteSecondaryPlayer(actualFadeMs: Long) {
    if (crossfadeInProgress) return
    val next      = standbyPlayer() ?: return
    val current   = activePlayer   ?: return
    val nextIndex = preloadedQueueIndex
    if (next.mediaItemCount == 0 || nextIndex !in queue.indices) return

    crossfadeInProgress = true
    promotionTriggered  = true
    promotionOwner      = current
    activeQueueIndex    = nextIndex
    nativeLog("info", "Promoting standby player → [$nextIndex]")

    try {
        val ci = current.currentMediaItemIndex
        if (current.mediaItemCount > ci + 1) {
            current.removeMediaItems(ci + 1, current.mediaItemCount)
        }
    } catch (e: Exception) {
        nativeLog("warn", "detach old queue tail: ${e.message}")
    }

    next.volume  = 0f
    activePlayer = next
    switchMediaSessionPlayer(next)

    if (hasAudioFocus) {
        next.play()
    } else if (requestAudioFocus()) {
        next.play()
    }
    // Kirim durasi aktual ke fade function
    startCrossfadeFadeIn(next, current, actualFadeMs)
    emitAll()
    refreshNotification()
}

    private fun switchMediaSessionPlayer(newPlayer: ExoPlayer) {
        try {
            session?.setPlayer(newPlayer)
        } catch (e: Exception) {
            nativeLog("warn", "MediaSession player switch failed: ${e.message}")
        }
    }

    private fun restoreQueueOnActivePlayer(active: ExoPlayer) {
        if (queue.isEmpty()) return
        val wasPlaying = active.isPlaying
        val position   = active.currentPosition.coerceAtLeast(0L)
        val repeatMode = active.repeatMode
        val shuffle    = active.shuffleModeEnabled
        val params     = active.playbackParameters
        try {
            active.setMediaItems(
                queue.map { mediaItemFrom(it) },
                activeQueueIndex.coerceIn(0, queue.lastIndex),
                position
            )
            active.repeatMode         = repeatMode
            active.shuffleModeEnabled = shuffle
            active.playbackParameters = params
            active.prepare()
            if (wasPlaying) active.play()
        } catch (e: Exception) {
            nativeLog("warn", "restoreQueueOnActivePlayer: ${e.message}")
        }
    }

    private fun startCrossfadeFadeIn(newPlayer: ExoPlayer, oldPlayer: ExoPlayer, actualFadeMs: Long) {
    crossfadeFadeRunnable?.let { handler.removeCallbacks(it) }
    val durationMs = actualFadeMs.coerceAtLeast(100L) // minimal 100ms
    // PATCH: sebelumnya steps di-hardcode 100 sementara stepMs di-floor minimal 8ms →
    // buat fade pendek (mis. durationMs=100ms) total waktu fade asli jadi
    // 100 * 8ms = 800ms, 8x lebih lama dari target. Ini bisa bikin crossfade
    // overlap/glitch pas trigger-nya mepet banget ke akhir lagu.
    // Sekarang steps dihitung dari durationMs supaya steps * stepMs ≈ durationMs,
    // tetap dijaga stepMs >= 8ms (biar gak nge-spam Handler) dan steps <= 100 (biar mulus).
    val minStepMs  = 8L
    val steps      = (durationMs / minStepMs).coerceIn(8L, 100L).toInt()
    val stepMs     = (durationMs / steps).coerceAtLeast(minStepMs)
    val targetVol  = volumeBeforeDuck.coerceIn(0f, 1f)
    var step       = 0

    val runnable = object : Runnable {
        override fun run() {
            if (activePlayer !== newPlayer) {
                crossfadeInProgress = false
                promotionTriggered  = false
                promotionOwner      = null
                crossfadeFadeRunnable = null
                nativeLog("warn", "Crossfade cancelled — player switched")
                return
            }
            if (step >= steps) {
                newPlayer.volume = targetVol
                try { oldPlayer.pause() }           catch (_: Exception) {}
                try { oldPlayer.stop() }            catch (_: Exception) {}
                try { oldPlayer.clearMediaItems() } catch (_: Exception) {}
                restoreQueueOnActivePlayer(newPlayer)
                crossfadeInProgress   = false
                promotionTriggered    = false
                promotionOwner        = null
                crossfadeFadeRunnable = null
                preloadedQueueIndex   = C.INDEX_UNSET
                saveQueueToPrefs()
                nativeLog("debug", "Crossfade completed (${durationMs}ms)")
                preloadNextTrack(force = true)
                return
            }
            val progress = step.toFloat() / steps.toFloat()
            oldPlayer.volume = (targetVol * sqrt(1f - progress)).coerceIn(0f, 1f)
            newPlayer.volume = (targetVol * sqrt(progress)).coerceIn(0f, 1f)
            step++
            handler.postDelayed(this, stepMs)
        }
    }
    crossfadeFadeRunnable = runnable
    handler.post(runnable)
    nativeLog("debug", "Crossfade fade-in started (${durationMs}ms, $steps steps)")
}
    // ── Utilities ──────────────────────────────────────────────────────────────

    private fun isMiui(): Boolean = try {
        val cls = Class.forName("android.os.SystemProperties")
        val get = cls.getMethod("get", String::class.java)
        (get.invoke(cls, "ro.miui.ui.version.name") as? String)?.isNotEmpty() == true
    } catch (_: Exception) { false }

    private fun nativeLog(level: String, msg: String) = NativeLogs.emit(level, "Media3", msg)

    // ── EventChannel registry ──────────────────────────────────────────────────

    object Events {
        private val sinks = mutableMapOf<String, EventChannel.EventSink?>()

        fun handler(name: String) = object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sinks[name] = events
                instance?.emitAll(emitQueue = true)
            }
            override fun onCancel(arguments: Any?) { sinks[name] = null }
        }

        fun emit(name: String, value: Any?) {
    
        sinks[name]?.success(value)
      }
     
    }

    object NativeLogs {
    private var sink: EventChannel.EventSink? = null

    fun handler() = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
        override fun onCancel(arguments: Any?) { sink = null }
    }

    fun emit(level: String, category: String, message: String) {
        sink?.success(
            mapOf(
                "level" to level,
                "category" to category,
                "message" to message
            )
        )
    }
}

}
