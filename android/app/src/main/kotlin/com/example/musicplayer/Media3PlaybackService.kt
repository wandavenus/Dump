package com.example.musicplayer

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.example.musicplayer.audio_focus.AudioFocusManager
import com.example.musicplayer.audio_offload.AudioOffloadManager
import com.example.musicplayer.crossfade.CrossfadeController
import com.example.musicplayer.crossfade.PreloadManager
import com.example.musicplayer.effects.AudioEffectsManager
import com.example.musicplayer.events.EventEmitter
import com.example.musicplayer.events.NativeLogger
import com.example.musicplayer.notification.PlaybackNotificationManager
import com.example.musicplayer.queue.QueueManager
import com.example.musicplayer.queue.QueueSync
import com.example.musicplayer.sleep_timer.SleepTimerManager
import com.example.musicplayer.transport.TransportCommands
import com.example.musicplayer.transport.TransportState
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.IdentityHashMap

/**
 * Thin orchestration layer.
 *
 * Responsibilities:
 *  - Owns the two ExoPlayer instances (primary / secondary for crossfade).
 *  - Owns the MediaSession.
 *  - Creates, wires, and tears down all feature modules.
 *  - Routes MethodChannel calls to TransportCommands.
 *  - Routes notification / BT transport intents.
 *  - Manages the Player.Listener glue that connects ExoPlayer events to modules.
 *
 * All playback logic lives in the feature modules under
 * transport/, queue/, crossfade/, audio_focus/, sleep_timer/, notification/, effects/.
 */
@UnstableApi
class Media3PlaybackService : MediaSessionService() {

    // ── Dual-player state ─────────────────────────────────────────────────────
    private var primaryPlayer:   ExoPlayer? = null
    private var secondaryPlayer: ExoPlayer? = null
    private var activePlayer:    ExoPlayer? = null
    private val player: ExoPlayer? get() = activePlayer
    private fun standbyPlayer(): ExoPlayer? =
        if (activePlayer === primaryPlayer) secondaryPlayer else primaryPlayer

    // ── Session ───────────────────────────────────────────────────────────────
    private var session: MediaSession? = null
    private val handler = Handler(Looper.getMainLooper())

    // ── Feature modules ───────────────────────────────────────────────────────
    private lateinit var audioFocusManager:    AudioFocusManager
    private lateinit var notificationManager:  PlaybackNotificationManager
    private lateinit var sleepTimerManager:    SleepTimerManager
    private lateinit var queueManager:         QueueManager
    private lateinit var queueSync:            QueueSync
    private lateinit var preloadManager:       PreloadManager
    private lateinit var crossfadeController:  CrossfadeController
    private lateinit var effectsManager:       AudioEffectsManager
    private lateinit var transportState:       TransportState
    private lateinit var transportCommands:    TransportCommands
    private lateinit var offloadManager:       AudioOffloadManager

    // ── Listener registry (prevents double-attach / leaks) ────────────────────
    private val playerListeners = IdentityHashMap<ExoPlayer, Player.Listener>()

    // ── Companion ─────────────────────────────────────────────────────────────
    companion object {
        /**
         * Backward-compatible aliases so MainActivity can keep referencing
         *   Media3PlaybackService.Events.handler(name)
         *   Media3PlaybackService.NativeLogs.handler()
         * without any changes.
         */
        val Events    get() = EventEmitter
        val NativeLogs get() = NativeLogger

        // Constants forwarded from modules for any external references
        const val CHANNEL_ID        = PlaybackNotificationManager.CHANNEL_ID
        const val NOTIFICATION_ID   = PlaybackNotificationManager.NOTIFICATION_ID
        const val ACTION_PLAY_PAUSE = PlaybackNotificationManager.ACTION_PLAY_PAUSE
        const val ACTION_SKIP_NEXT  = PlaybackNotificationManager.ACTION_SKIP_NEXT
        const val ACTION_SKIP_PREV  = PlaybackNotificationManager.ACTION_SKIP_PREV
        const val ACTION_STOP       = PlaybackNotificationManager.ACTION_STOP
        const val PREFS_NAME        = QueueSync.PREFS_NAME

        @Volatile var instance: Media3PlaybackService? = null
    }

    // ── Noisy receiver (headphone unplug → pause) ─────────────────────────────
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                // Cancel any in-progress crossfade first so both players stop cleanly
                if (crossfadeController.crossfadeInProgress) {
                    crossfadeController.cancel(resetVolume = true)
                }
                player?.pause()
                transportState.stopPositionTicker()
                audioFocusManager.abandon()
                transportState.emitAll()
                NativeLogger.emit("info", "Media3", "Noisy event: headphones unplugged → paused")
            }
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()

        // Create primary player
        primaryPlayer = createConfiguredPlayer()
        activePlayer  = primaryPlayer

        // ── Audio Offload Manager ─────────────────────────────────────────────
        // Must be created before CrossfadeController and TransportCommands so that
        // both can reference it.  Starts with scheduling disabled; TransportCommands
        // will call onCrossfadeDurationChanged() when the user sets a duration, which
        // re-evaluates eligibility at the right time.
        offloadManager = AudioOffloadManager(
            // Read crossfadeDurationSec directly from the controller so
            // onCrossfadeComplete() always gets the live, authoritative value.
            getCrossfadeDurationSec  = { crossfadeController.crossfadeDurationSec },
            // Media3 1.10.1: experimentalSetOffloadSchedulingEnabled removed;
            // scheduling is now managed internally.  Only osGranted is reported.
            onOffloadStateChanged    = { osGranted ->
                EventEmitter.emit(
                    "offloadState",
                    mapOf("osGranted" to osGranted),
                )
            },
        )
        primaryPlayer!!.addAudioOffloadListener(offloadManager.makeOffloadListener())

        // Build MediaSession
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val sessionBuilder = MediaSession.Builder(this, primaryPlayer!!)
        if (launchIntent != null) {
            sessionBuilder.setSessionActivity(
                PendingIntent.getActivity(
                    this, 0, launchIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        }
        session = sessionBuilder.build()

        // Wire feature modules ────────────────────────────────────────────────

        audioFocusManager = AudioFocusManager(
            audioManager           = getSystemService(Context.AUDIO_SERVICE) as AudioManager,
            getPlayer              = { activePlayer },
            startTicker            = { transportState.startPositionTicker() },
            stopTicker             = { transportState.stopPositionTicker() },
            onFocusEvent           = { transportState.emitAll() },
            getCrossfadeInProgress = { crossfadeController.crossfadeInProgress },
        )

        notificationManager = PlaybackNotificationManager(
            service         = this,
            handler         = handler,
            getSession      = { session },
            getPlayer       = { activePlayer },
            getCurrentTrack = { transportState.currentTrackMap() },
        )
        notificationManager.ensureChannel()

        sleepTimerManager = SleepTimerManager(
            handler    = handler,
            getPlayer  = { activePlayer },
            stopTicker = { transportState.stopPositionTicker() },
            emitAll    = { transportState.emitAll() },
        )

        queueManager = QueueManager(
            getPlayer             = { activePlayer },
            isCrossfadeInProgress = { crossfadeController.crossfadeInProgress },
            saveQueue             = { queueSync.save() },
            emitAll               = { eq -> transportState.emitAll(eq) },
        )

        queueSync = QueueSync(
            context                 = this,
            handler                 = handler,
            getQueue                = { queueManager.queue },
            getActiveQueueIndex     = { queueManager.activeQueueIndex },
            getPlayer               = { activePlayer },
            getCrossfadeDurationSec = { crossfadeController.crossfadeDurationSec },
        )

        preloadManager = PreloadManager(
            getActivePlayer    = { activePlayer },
            getStandbyPlayer   = { standbyPlayer() },
            createPlayer       = { createConfiguredPlayer() },
            attachListener     = { attachPlayerListener(it) },
            detachListener     = { detachPlayerListener(it) },
            setStandbyPlayer   = { newStandby ->
                // Place the new standby into whichever slot is not currently active
                if (activePlayer === primaryPlayer) secondaryPlayer = newStandby
                else primaryPlayer = newStandby
            },
            getActivePlayerRef = { activePlayer },
            getCrossfadeDurationSec = { crossfadeController.crossfadeDurationSec },
            getQueue           = { queueManager.queue },
        )

        crossfadeController = CrossfadeController(
            handler            = handler,
            getActivePlayer    = { activePlayer },
            getStandbyPlayer   = { standbyPlayer() },
            setActivePlayer    = { newPlayer -> activePlayer = newPlayer },
            switchSessionPlayer = { newPlayer ->
                try { session?.setPlayer(newPlayer) }
                catch (e: Exception) {
                    NativeLogger.emit("warn", "Media3", "MediaSession player switch failed: ${e.message}")
                }
            },
            preloadManager      = preloadManager,
            getVolumeBeforeDuck = { audioFocusManager.volumeBeforeDuck },
            hasAudioFocus       = { audioFocusManager.hasAudioFocus() },
            requestAudioFocus   = { audioFocusManager.request() },
            getQueue            = { queueManager.queue },
            getActiveQueueIndex = { queueManager.activeQueueIndex },
            setActiveQueueIndex = { idx -> queueManager.setActiveQueueIndex(idx) },
            onCrossfadeComplete = {
                // CE-03 fix: rebuild full queue on promoted player (non-interrupting).
                queueManager.rebuildPlayerQueue()
                queueSync.save()
                // Re-attach all audio effects to the new active player's audio session.
                // The new player was a "cold" secondary player with no effects attached.
                val newSessionId = activePlayer?.audioSessionId ?: 0
                if (newSessionId > 0) {
                    effectsManager.attachEffects(newSessionId)
                    NativeLogger.emit("info", "Media3",
                        "Post-crossfade effects reattach → session=$newSessionId")
                }
                // Re-evaluate offload scheduling on the newly promoted player.
                // Also attach the offload listener to the new active player so OS
                // grant/reject events are still reported after player promotion.
                offloadManager.onCrossfadeComplete()
                activePlayer?.addAudioOffloadListener(offloadManager.makeOffloadListener())
            },
            emitAll             = { transportState.emitAll() },
            refreshNotification = { notificationManager.refresh() },
            // Disable offload scheduling before the first 16 ms Handler tick so the
            // equal-power fade runs with reliable timing on the main looper.
            onCrossfadeStarting = { offloadManager.onCrossfadeStarting() },
        )

        effectsManager = AudioEffectsManager(handler)

        transportState = TransportState(
            handler             = handler,
            getPlayer           = { activePlayer },
            queueManager        = queueManager,
            crossfadeController = crossfadeController,
            sleepTimerManager   = sleepTimerManager,
        )

        transportCommands = TransportCommands(
            getPlayer             = { activePlayer },
            audioFocusManager     = audioFocusManager,
            crossfadeController   = crossfadeController,
            preloadManager        = preloadManager,
            queueManager          = queueManager,
            queueSync             = queueSync,
            transportState        = transportState,
            notificationManager   = notificationManager,
            sleepTimerManager     = sleepTimerManager,
            effectsManager        = effectsManager,
            ensureMediaForeground = { notificationManager.ensureMediaForeground() },
            offloadManager        = offloadManager,
        )

        // When Flutter subscribes to any event stream, push the full current state
        EventEmitter.setOnSubscribeCallback { transportState.emitAll(emitQueue = true) }

        // Attach listener to primary player
        attachPlayerListener(primaryPlayer!!)

        registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        instance = this

        restoreQueueFromPrefs()

        NativeLogger.emit(
            "info", "Media3",
            "onCreate: ExoPlayer ready (Android SDK ${Build.VERSION.SDK_INT} / MIUI=${isMiui()})"
        )
        transportState.emitAll()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    /**
     * Block Media3's DefaultMediaNotificationProvider from managing the foreground
     * notification. Starting from Media3 1.3, MediaSessionService automatically
     * creates and posts its own notification (default ID 1001 — same as ours),
     * which would conflict with our custom PlaybackNotificationManager on MIUI 12.
     * By overriding with an empty body we retain full control of the notification
     * lifecycle; PlaybackNotificationManager.ensureMediaForeground() is still the
     * single code path that calls startForeground().
     */
    override fun onUpdateNotification(session: MediaSession, startInForegroundRequired: Boolean) {
        // Intentionally empty — PlaybackNotificationManager owns the notification.
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        handleNotificationAction(intent?.action)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        NativeLogger.emit("info", "Media3", "onTaskRemoved — service continues (stopWithTask=false)")
    }

    override fun onDestroy() {
        crossfadeController.cancel(resetVolume = true)
        NativeLogger.emit("info", "Media3", "onDestroy: releasing resources")
        queueSync.save()
        sleepTimerManager.cancel()
        effectsManager.releaseEffects()
        handler.removeCallbacksAndMessages(null)
        try { unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
        audioFocusManager.abandon()
        instance = null
        primaryPlayer?.release()
        secondaryPlayer?.release()
        primaryPlayer   = null
        secondaryPlayer = null
        activePlayer    = null
        session?.release()
        session = null
        super.onDestroy()
    }

    // ── MethodChannel entry point ─────────────────────────────────────────────

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        transportCommands.dispatch(call, result)
    }

    // ── Notification / BT transport actions ───────────────────────────────────

    private fun handleNotificationAction(action: String?) {
        val p = player
        when (action) {
            ACTION_PLAY_PAUSE -> {
                if (p != null) {
                    if (p.isPlaying) {
                        p.pause()
                        transportState.stopPositionTicker()
                        audioFocusManager.abandon()
                        NativeLogger.emit("info", "Media3", "transport: pause (notification/BT)")
                    } else {
                        if (audioFocusManager.request()) {
                            if (p.playbackState == Player.STATE_ENDED && p.mediaItemCount > 0) {
                                p.seekToDefaultPosition(0)
                                p.prepare()
                            }
                            p.play()
                            notificationManager.ensureMediaForeground()
                            notificationManager.refresh()
                            transportState.startPositionTicker()
                            NativeLogger.emit("info", "Media3", "transport: play (notification/BT)")
                        }
                    }
                    transportState.emitAll()
                    notificationManager.refresh()
                }
            }
            ACTION_SKIP_NEXT -> {
                sleepTimerManager.cancel()
                crossfadeController.cancel(resetVolume = true)
                preloadManager.clearStandbyQueue()
                if (p != null) {
                    if (p.playbackState == Player.STATE_ENDED) {
                        val nextIndex = p.nextMediaItemIndex
                        if (nextIndex != C.INDEX_UNSET) {
                            p.seekToDefaultPosition(nextIndex); p.prepare()
                        } else if (p.mediaItemCount > 0) {
                            p.seekToDefaultPosition(0); p.prepare()
                        }
                    } else {
                        p.seekToNextMediaItem()
                    }
                }
                NativeLogger.emit("info", "Media3", "transport: skipNext (notification/BT)")
                transportState.emitAll()
                notificationManager.refresh()
            }
            ACTION_SKIP_PREV -> {
                sleepTimerManager.cancel()
                crossfadeController.cancel(resetVolume = true)
                preloadManager.clearStandbyQueue()
                if (p != null) {
                    if (p.playbackState == Player.STATE_ENDED) {
                        val prevIndex = p.previousMediaItemIndex
                        if (prevIndex != C.INDEX_UNSET) {
                            p.seekToDefaultPosition(prevIndex); p.prepare()
                        } else if (p.mediaItemCount > 0) {
                            p.seekToDefaultPosition(0); p.prepare()
                        }
                    } else {
                        p.seekToPreviousMediaItem()
                    }
                }
                NativeLogger.emit("info", "Media3", "transport: skipPrev (notification/BT)")
                transportState.emitAll()
                notificationManager.refresh()
            }
            ACTION_STOP -> {
                sleepTimerManager.cancel()
                NativeLogger.emit("info", "Media3", "transport: stop (notification/BT)")
                crossfadeController.cancel(resetVolume = true)
                primaryPlayer?.pause();   primaryPlayer?.seekTo(0)
                secondaryPlayer?.pause(); secondaryPlayer?.seekTo(0)
                transportState.stopPositionTicker()
                audioFocusManager.abandon()
                notificationManager.stopForeground()
                transportState.emitAll()
                stopSelf()
            }
            else -> {
                if ((p?.mediaItemCount ?: 0) > 0) {
                    notificationManager.ensureMediaForeground()
                }
            }
        }
    }

    // ── Player factory ────────────────────────────────────────────────────────

    private fun createConfiguredPlayer(): ExoPlayer {
        // Tuned for local (offline) file playback:
        //  - 15 s min buffer  : local reads are near-instant; no need to buffer more before play.
        //  - 50 s max buffer  : keeps enough audio pre-decoded for smooth gapless / crossfade.
        //  - 1.5 s for playback start  : snappy initial start.
        //  - 3 s after rebuffer : quick recovery if a slow storage device causes a hiccup.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                /* minBufferMs                        */ 15_000,
                /* maxBufferMs                        */ 50_000,
                /* bufferForPlaybackMs                */  1_500,
                /* bufferForPlaybackAfterRebufferMs   */  3_000,
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        return ExoPlayer.Builder(this)
            .setLoadControl(loadControl)
            .build()
            .apply {
                val attrs = androidx.media3.common.AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build()
                setAudioAttributes(attrs, false)
                // false: we handle ACTION_AUDIO_BECOMING_NOISY ourselves via noisyReceiver.
                // With two simultaneous players (crossfade), setting this to true on both would
                // cause both players to register independent BroadcastReceivers for the noisy
                // intent, resulting in double-pause events and state corruption on MIUI 12.
                setHandleAudioBecomingNoisy(false)
                // Acquire a partial wake lock for the duration of local-file playback.
                // Critical on MIUI 12: the aggressive battery manager may suspend the CPU
                // mid-track without this, causing playback to stall while the screen is off.
                setWakeMode(C.WAKE_MODE_LOCAL)
                // Attach the offload listener when available (offloadManager is initialised
                // after the primary player in onCreate; secondary players are always created
                // after that point so the guard below covers the race-free case).
                if (::offloadManager.isInitialized) {
                    addAudioOffloadListener(offloadManager.makeOffloadListener())
                }
            }
    }

    // ── Player listener (glue between ExoPlayer events and feature modules) ───

    private fun attachPlayerListener(p: ExoPlayer) {
        detachPlayerListener(p)
        val listener = object : Player.Listener {
            private fun isActiveEvent(): Boolean = p === activePlayer

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (!isActiveEvent()) return
                transportState.emitAll()
                notificationManager.refresh()
                if (playbackState == Player.STATE_READY &&
                    crossfadeController.crossfadeDurationSec > 0f) {
                    preloadManager.preloadNextTrack()
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (!isActiveEvent()) return
                if (isPlaying) transportState.startPositionTicker()
                else           transportState.stopPositionTicker()
                transportState.emitAll()
                notificationManager.refresh()
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                NativeLogger.emit("debug", "Media3",
                    "Player transition reason=$reason active=${p === activePlayer}")

                // Ignore transitions fired by the old player during promotion
                if (p === crossfadeController.promotionOwner &&
                    crossfadeController.crossfadeInProgress) {
                    NativeLogger.emit("debug", "Media3",
                        "Ignored transition from old player during promotion")
                    return
                }
                if (!isActiveEvent()) return

                // Manual skip cancels end-of-song sleep timer
                if (reason != Player.MEDIA_ITEM_TRANSITION_REASON_AUTO &&
                    sleepTimerManager.sleepTimerActive &&
                    sleepTimerManager.sleepEndOfSong) {
                    sleepTimerManager.cancel()
                }

                // End-of-song sleep timer fires on auto-transition
                if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO &&
                    sleepTimerManager.sleepEndOfSong &&
                    sleepTimerManager.sleepTimerActive) {
                    NativeLogger.emit("info", "Media3",
                        "Sleep timer (end-of-song): stopping at track boundary")
                    handler.post { sleepTimerManager.triggerStop() }
                    return
                }

                if (!crossfadeController.crossfadeInProgress && p.currentMediaItemIndex >= 0) {
                    queueManager.setActiveQueueIndex(p.currentMediaItemIndex)
                    crossfadeController.resetPromotionState()
                    if (crossfadeController.crossfadeDurationSec > 0f) {
                        preloadManager.preloadNextTrack(force = true)
                    }
                }
                queueSync.save()
                transportState.emitAll()
                notificationManager.refresh()
            }

            override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) {
                if (!isActiveEvent()) return
                EventEmitter.emit("shuffleMode", shuffleModeEnabled)
                queueSync.save()
            }

            override fun onRepeatModeChanged(repeatMode: Int) {
                if (!isActiveEvent()) return
                // DE-06 fix: emitRepeatMode deduplicates against lastEmittedRepeatMode
                transportState.emitRepeatMode(repeatMode)
                queueSync.save()
            }

            override fun onAudioSessionIdChanged(audioSessionId: Int) {
                if (!isActiveEvent()) return
                NativeLogger.emit("info", "Media3", "audioSessionId → $audioSessionId")
                effectsManager.attachEffects(audioSessionId)
                transportState.emitAll()
            }
        }
        playerListeners[p] = listener
        p.addListener(listener)
    }

    private fun detachPlayerListener(p: ExoPlayer) {
        playerListeners.remove(p)?.let { p.removeListener(it) }
    }

    // ── Queue persistence ─────────────────────────────────────────────────────

    private fun restoreQueueFromPrefs() {
        val restored = queueSync.restore() ?: return
        queueManager.setQueue(restored.items, restored.index, restored.posMs)
        val p = activePlayer ?: return
        p.repeatMode         = restored.repeat
        p.shuffleModeEnabled = restored.shuffle
        // Restored in paused state — user resumes manually
        NativeLogger.emit("info", "Media3",
            "Restored queue: ${restored.items.size} tracks idx=${restored.index} " +
            "pos=${restored.posMs}ms repeat=${restored.repeat} shuffle=${restored.shuffle}")
        transportState.emitAll(emitQueue = true)
    }

    // ── Utility ───────────────────────────────────────────────────────────────

    private fun isMiui(): Boolean = try {
        val cls = Class.forName("android.os.SystemProperties")
        val get = cls.getMethod("get", String::class.java)
        (get.invoke(cls, "ro.miui.ui.version.name") as? String)?.isNotEmpty() == true
    } catch (_: Exception) { false }
}
