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
import androidx.media3.common.ForwardingPlayer
import com.example.musicplayer.audio_focus.AudioFocusManager
import com.example.musicplayer.audio_offload.AudioOffloadManager
import com.example.musicplayer.crossfade.CrossfadeController
import com.example.musicplayer.crossfade.PreloadManager
import com.example.musicplayer.effects.AudioEffectsManager
import com.example.musicplayer.events.EventEmitter
import com.example.musicplayer.events.NativeLogger
import com.example.musicplayer.events.SessionAuditLogger
import com.example.musicplayer.notification.PlaybackNotificationManager
import com.example.musicplayer.queue.QueueManager
import com.example.musicplayer.queue.QueueSync
import com.example.musicplayer.sleep_timer.SleepTimerManager
import com.example.musicplayer.transport.TransportCommands
import com.example.musicplayer.transport.TransportState
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Collections
import java.util.IdentityHashMap
import androidx.media3.common.Format
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.analytics.PlaybackStatsListener
import androidx.media3.exoplayer.audio.AudioCapabilitiesReceiver
import androidx.media3.exoplayer.audio.ChannelMixingAudioProcessor
import androidx.media3.exoplayer.audio.DefaultAudioProcessorChain
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.flac.FlacExtractor
import androidx.media3.session.CommandButton
import com.example.musicplayer.effects.StereoWidthManager

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
    private val playerListeners      = IdentityHashMap<ExoPlayer, Player.Listener>()
    private val analyticsListeners   = IdentityHashMap<ExoPlayer, AnalyticsListener>()
    private val statsListeners       = IdentityHashMap<ExoPlayer, PlaybackStatsListener>()  // Item 6
    private val playerProcessors     = IdentityHashMap<ExoPlayer, ChannelMixingAudioProcessor>() // Item 8

    // ── Item 1: skip silence — persisted so new standby players inherit state ─
    private var skipSilenceEnabled = false

    // ── Item 5: tunneling — persisted so new standby players inherit state ────
    private var tunnelingEnabled = false

    // ── Item 3 & 8: capability receiver and stereo width manager ─────────────
    private var audioCapReceiver: AudioCapabilitiesReceiver? = null
    private lateinit var stereoWidthManager: StereoWidthManager

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

        // Item 8: StereoWidthManager MUST be initialised before the first
        // createConfiguredPlayer() call so the primary player's processor is
        // correctly tracked from the start.
        stereoWidthManager = StereoWidthManager()

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
        // ForwardingPlayer intercepts transport commands from external controllers
        // (Bluetooth, OS widgets) and routes them through transportCommands.*Native()
        // so audio focus, crossfade, and state emission are handled correctly.
        // transportCommands is lateinit but always initialised before any external
        // controller can connect (which only happens after onCreate() returns).
        val sessionPlayer = object : ForwardingPlayer(primaryPlayer!!) {
            override fun play()                    { transportCommands.playNative() }
            override fun pause()                   { transportCommands.pauseNative() }
            override fun seekToNextMediaItem()     { transportCommands.skipNextNative() }
            override fun seekToPreviousMediaItem() { transportCommands.skipPrevNative() }
            override fun seekTo(mediaItemIndex: Int, positionMs: Long) {
                transportCommands.seekNative(positionMs)
            }
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val sessionBuilder = MediaSession.Builder(this, sessionPlayer)
        if (launchIntent != null) {
            sessionBuilder.setSessionActivity(
                PendingIntent.getActivity(
                    this, 0, launchIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        }
        session = sessionBuilder.build()

        // Media3 1.4+: setMediaButtonPreferences controls which buttons external OS
        // surfaces show (lock screen widget, Android Auto, Wear OS, Bluetooth AVRCP).
        // This does NOT affect our custom PlaybackNotificationManager notification —
        // that is fully controlled by onUpdateNotification() override (empty body).
        session?.setMediaButtonPreferences(listOf(
            CommandButton.Builder(CommandButton.ICON_PREVIOUS)
                .setPlayerCommand(Player.COMMAND_SEEK_TO_PREVIOUS)
                .setDisplayName("Previous")
                .build(),
            CommandButton.Builder(CommandButton.ICON_PLAY)
                .setPlayerCommand(Player.COMMAND_PLAY_PAUSE)
                .setDisplayName("Play / Pause")
                .build(),
            CommandButton.Builder(CommandButton.ICON_NEXT)
                .setPlayerCommand(Player.COMMAND_SEEK_TO_NEXT)
                .setDisplayName("Next")
                .build(),
        ))

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
                // Open a fresh audit chapter for the newly promoted track.
                // SessionAuditLogger.onCrossfadeComplete() was already called inside
                // CrossfadeController.runEqualPowerFade before this callback fires,
                // so the fade-complete line appears in the outgoing chapter first.
                val promotedMap = queueManager.queue.getOrNull(queueManager.activeQueueIndex)
                SessionAuditLogger.openChapter(
                    title          = promotedMap?.get("title")  as? String ?: "Unknown",
                    artist         = promotedMap?.get("artist") as? String ?: "",
                    audioSessionId = newSessionId,
                )
                // Re-evaluate offload state on the newly promoted player.
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
            // WD-01: stuck-playback recovery.
            // retry 1 → re-prepare current item (resets codec pipeline without skipping).
            // retry 2 → skip to next track (permanently bad / undecodable file).
            onStuck = { retryCount ->
                val p = activePlayer
                if (p != null) {
                    val pos = p.currentPosition
                    NativeLogger.emit("warn", "Watchdog",
                        "Recovery attempt $retryCount — pos=${pos}ms " +
                        "state=${p.playbackState} crossfade=${crossfadeController.crossfadeInProgress}")
                    SessionAuditLogger.warn("Watchdog",
                        "stuck at ${pos}ms retry=$retryCount")
                    if (retryCount <= 1) {
                        // Attempt 1: re-initialise the decoder pipeline for the current item.
                        // This resolves transient hardware codec freezes and post-call pipeline
                        // corruption without losing the user's playback position.
                        NativeLogger.emit("warn", "Watchdog", "Re-preparing decoder pipeline")
                        p.prepare()
                    } else {
                        // Attempt 2: the file itself is undecodable — skip it.
                        NativeLogger.emit("warn", "Watchdog",
                            "Re-prepare had no effect — skipping to next track")
                        transportCommands.skipNextNative()
                    }
                }
            },
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

            // Item 1: skip silence — applied to ALL live players atomically so
            // both active and standby behave identically during crossfade overlap.
            applySkipSilence = { enabled ->
                skipSilenceEnabled = enabled
                forEachLivePlayer { it.skipSilenceEnabled = enabled }
                NativeLogger.emit("info", "Media3",
                    "skipSilence=$enabled applied to all live players")
            },

            // Item 5: tunneling — updates TrackSelectionParameters on all live
            // players and stores flag so new standby players inherit the state.
            onTunnelingChanged = { enabled -> applyTunnelingToAllPlayers(enabled) },

            // Item 8: stereo widening — delegate to StereoWidthManager which
            // updates all ChannelMixingAudioProcessor instances atomically.
            onStereoWideningChanged = { enabled, strength ->
                stereoWidthManager.setStereoWidening(enabled, strength)
            },

            // Item 6: return current PlaybackStats for the active player session.
            getPlaybackStats = {
                val statsListener = statsListeners[activePlayer]
                statsListener?.getPlaybackStats()?.let { stats ->
                    mapOf(
                        "totalPlayTimeMs"      to stats.totalPlayTimeMs,
                        "totalBufferingTimeMs" to stats.totalBufferingTimeMs,
                        "totalRebufferCount"   to stats.totalRebufferCount,
                        "totalErrorCount"      to stats.totalErrorCount,
                    )
                }
            },
        )

        // When Flutter subscribes to any event stream, push the full current state
        EventEmitter.setOnSubscribeCallback { transportState.emitAll(emitQueue = true) }

        // Attach listener to primary player
        attachPlayerListener(primaryPlayer!!)

        registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))

        // Item 3: AudioCapabilitiesReceiver — reacts to audio output device changes
        // (BT connect/disconnect, HDMI plug) that can invalidate the software effects
        // chain on MIUI 12 without changing the numeric AudioSession ID.
        // All callback work runs on the main Handler so it is safe to access ExoPlayer
        // state and call effectsManager.resetAndReattach() directly.
        audioCapReceiver = AudioCapabilitiesReceiver(this) { _ ->
            NativeLogger.emit(
                "info", "AudioCap",
                "Audio capabilities changed (output device may have changed) — " +
                "re-evaluating track selection and scheduling effects reattach",
            )
            // Force a track re-selection on all live players so Media3 can adapt
            // to any new passthrough / tunneling capabilities on the new output device.
            forEachLivePlayer { p ->
                p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().build()
            }
            // MIUI 12: delay the effects re-attach slightly so the new AudioSession
            // (if any) has time to be published by AudioFlinger before we attempt to
            // bind Equalizer / BassBoost / Virtualizer etc.
            handler.postDelayed({
                val sessionId = activePlayer?.audioSessionId ?: 0
                if (sessionId > 0) {
                    effectsManager.resetAndReattach(sessionId)
                }
            }, 500L)
            // Notify Flutter so the UI can refresh device-specific info if needed.
            EventEmitter.emit("audioCapabilitiesChanged",
                mapOf("timestamp" to System.currentTimeMillis()))
        }.also { it.register() }

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
        // Item 3: unregister AudioCapabilitiesReceiver to prevent BroadcastReceiver leaks.
        try { audioCapReceiver?.unregister() } catch (_: Exception) {}
        audioCapReceiver = null
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

    /**
     * Routes notification / Bluetooth transport button intents to [TransportCommands].
     *
     * Previously this duplicated skip/play/pause logic inline. Now every action goes
     * through the same TransportCommands path as the Flutter MethodChannel, so audio
     * focus, crossfade cleanup, SessionAuditLogger, and preload management are handled
     * identically regardless of how the user triggers the action.
     */
    private fun handleNotificationAction(action: String?) {
        when (action) {
            ACTION_PLAY_PAUSE -> {
                val playing = player?.isPlaying ?: false
                if (playing) transportCommands.pauseNative()
                else         transportCommands.playNative()
                NativeLogger.emit("info", "Media3",
                    "transport: ${if (playing) "pause" else "play"} (notification/BT)")
            }
            ACTION_SKIP_NEXT -> {
                transportCommands.skipNextNative()
                NativeLogger.emit("info", "Media3", "transport: skipNext (notification/BT)")
            }
            ACTION_SKIP_PREV -> {
                transportCommands.skipPrevNative()
                NativeLogger.emit("info", "Media3", "transport: skipPrev (notification/BT)")
            }
            ACTION_STOP -> {
                // STOP is not a standard TransportCommands flow — it tears down the
                // foreground service.  Keep the inline logic here.
                sleepTimerManager.cancel()
                crossfadeController.cancel(resetVolume = true)
                primaryPlayer?.pause();   primaryPlayer?.seekTo(0)
                secondaryPlayer?.pause(); secondaryPlayer?.seekTo(0)
                transportState.stopPositionTicker()
                audioFocusManager.abandon()
                notificationManager.stopForeground()
                transportState.emitAll()
                NativeLogger.emit("info", "Media3", "transport: stop (notification/BT)")
                stopSelf()
            }
            else -> {
                if ((player?.mediaItemCount ?: 0) > 0) {
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

        // Item 8: each player gets its own ChannelMixingAudioProcessor so
        // stereo widening can be applied/updated atomically during crossfade.
        val channelMixingProc: ChannelMixingAudioProcessor =
            if (::stereoWidthManager.isInitialized) stereoWidthManager.createProcessor()
            else ChannelMixingAudioProcessor()

        // Custom DefaultRenderersFactory that injects channelMixingProc into the
        // DefaultAudioSink's processor chain so stereo widening runs before
        // SonicAudioProcessor (which handles skip-silence and speed/pitch).
        //
        // Item 2: setEnableDecoderFallback(true) — on MIUI 12, hardware audio
        // decoders (OMX.qcom.audio.*) occasionally crash on FLAC or long files.
        // With fallback enabled, ExoPlayer silently retries with the software
        // decoder (FFmpeg extension) instead of surfacing an error to the user.
        //
        // Item 8 (continued): buildAudioSink() is the officially supported
        // extension point in DefaultRenderersFactory for injecting custom
        // AudioProcessors into the pipeline.
        val renderersFactory = object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean,
            ): DefaultAudioSink = DefaultAudioSink.Builder(context)
                .setEnableFloatOutput(enableFloatOutput)
                .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                // DefaultAudioProcessorChain wraps our processor first, then adds
                // the built-in SonicAudioProcessor (handles skip-silence / speed).
                .setAudioProcessorChain(DefaultAudioProcessorChain(channelMixingProc))
                .build()
        }
            .setEnableAudioFloatOutput(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            .setEnableDecoderFallback(true)  // Item 2

        // DefaultTrackSelector with explicit audio preferences.
        // For typical local music files (single audio track) this is a no-op, but for
        // multi-track containers (MKV/MP4) it ensures the highest-quality track is chosen.
        //
        // Item 5: setTunnelingEnabled reads the service-level flag so that standby
        // players created lazily by PreloadManager inherit the current tunneling state.
        val trackSelector = DefaultTrackSelector(this).apply {
            setParameters(
                buildUponParameters()
                    .setMaxAudioChannelCount(Int.MAX_VALUE) // never downmix surround
                    .setForceLowestBitrate(false)           // prefer quality over economy
                    .setTunnelingEnabled(tunnelingEnabled)  // Item 5
                    .build()
            )
        }

        // Item 10: CustomDefaultExtractorsFactory.
        // FLAG_DISABLE_ID3_METADATA on FLAC: jaudiotagger already reads all tags
        // (title, artist, album, lyrics) so ExoPlayer's ID3 parse during demuxing
        // is redundant overhead — especially on long FLAC files (>100 MB) where
        // the ID3 scan measurably delays the initial seek.
        val extractorsFactory = DefaultExtractorsFactory()
            .setFlacExtractorFlags(FlacExtractor.FLAG_DISABLE_ID3_METADATA)
        val mediaSourceFactory = DefaultMediaSourceFactory(this, extractorsFactory)

        val player = ExoPlayer.Builder(this, renderersFactory)
            .setLoadControl(loadControl)
            .setTrackSelector(trackSelector)
            .setMediaSourceFactory(mediaSourceFactory)  // Item 10
            .setSeekBackIncrementMs(10_000L)            // Item 7: 10 s back (headset 2× press)
            .setSeekForwardIncrementMs(30_000L)         // Item 7: 30 s forward (headset 3× press)
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
                // Item 1: apply current skip-silence state so standby players always
                // match the active player — no gap in skip-silence behaviour mid-crossfade.
                skipSilenceEnabled = this@Media3PlaybackService.skipSilenceEnabled
                // Attach the offload listener when available (offloadManager is initialised
                // after the primary player in onCreate; secondary players are always created
                // after that point so the guard below covers the race-free case).
                if (::offloadManager.isInitialized) {
                    addAudioOffloadListener(offloadManager.makeOffloadListener())
                }
            }

        // Track the processor for this player so it can be removed from
        // StereoWidthManager when the player is released (via detachPlayerListener).
        if (::stereoWidthManager.isInitialized) {
            playerProcessors[player] = channelMixingProc
        }

        return player
    }

    // ── Player listener (glue between ExoPlayer events and feature modules) ───

    private fun attachPlayerListener(p: ExoPlayer) {
        detachPlayerListener(p)

        // Item 6: PlaybackStatsListener — accumulates per-session metrics for
        // getPlaybackStats(). keepHistory=false: we only need the running totals
        // (totalPlayTimeMs / totalBufferingTimeMs / totalRebufferCount /
        // totalErrorCount) so there is no need to retain per-sample history in RAM.
        val statsListener = PlaybackStatsListener(/* keepHistory= */ false) { _, _ -> }
        p.addAnalyticsListener(statsListener)
        statsListeners[p] = statsListener

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
                    // Open a new audit chapter for this track transition.
                    // Done here (inside the non-crossfade guard) so crossfade promotions
                    // open their chapter from the onCrossfadeComplete callback instead,
                    // avoiding a double-open on the same track.
                    val trackMap = queueManager.queue.getOrNull(queueManager.activeQueueIndex)
                    SessionAuditLogger.openChapter(
                        title          = trackMap?.get("title")  as? String ?: "Unknown",
                        artist         = trackMap?.get("artist") as? String ?: "",
                        audioSessionId = p.audioSessionId,
                    )
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
                SessionAuditLogger.onAudioSessionAssigned(audioSessionId)
                effectsManager.attachEffects(audioSessionId)
                transportState.emitAll()
            }

            // ── Media3 1.10.1 — additional Player.Listener callbacks ──────────

            /**
             * Fired whenever ExoPlayer's software volume changes (e.g. during
             * ducking or user-initiated setVolume).  Emits a state snapshot so
             * Flutter's volume indicator stays in sync without a separate poll.
             */
            override fun onVolumeChanged(volume: Float) {
                if (!isActiveEvent()) return
                NativeLogger.emit("verbose", "Media3", "volume → $volume")
                transportState.emitAll()
            }

            /**
             * Fired when the AudioAttributes on the ExoPlayer instance change.
             * In this app they are set once at construction and never mutated,
             * so this is primarily a diagnostic log.
             */
            override fun onAudioAttributesChanged(
                audioAttributes: androidx.media3.common.AudioAttributes,
            ) {
                if (!isActiveEvent()) return
                NativeLogger.emit(
                    "info", "Media3",
                    "audioAttributes → usage=${audioAttributes.usage} " +
                    "contentType=${audioAttributes.contentType} " +
                    "flags=${audioAttributes.flags}",
                )
            }

            /**
             * Fires when skip-silence is toggled on the player.
             * Emitted to Flutter via the "skipSilence" EventChannel so the UI
             * toggle stays in sync with the native player state.
             */
            override fun onSkipSilenceEnabledChanged(skipSilenceEnabled: Boolean) {
                if (!isActiveEvent()) return
                NativeLogger.emit("info", "Media3", "skipSilence → $skipSilenceEnabled")
                EventEmitter.emit("skipSilence", skipSilenceEnabled)
            }

            /**
             * Fires when the selected audio track changes — i.e. after decoder
             * initialisation on every new media item.  Emits the active audio
             * format (sample rate, channels, bitrate, MIME type, codecs,
             * PCM encoding) via the "audioFormat" EventChannel for the
             * Flutter UI to display bit-depth / sample-rate info.
             */
            override fun onTracksChanged(tracks: Tracks) {
                if (!isActiveEvent()) return
                val audioGroup = tracks.groups.firstOrNull {
                    it.type == C.TRACK_TYPE_AUDIO && it.isSelected
                }
                val fmt = audioGroup?.let { g ->
                    (0 until g.length)
                        .firstOrNull { i -> g.isTrackSelected(i) }
                        ?.let { i -> g.getTrackFormat(i) }
                }
                val fmtMap: Map<String, Any> = if (fmt != null) mapOf(
                    "sampleRate"   to (fmt.sampleRate.takeIf   { it != Format.NO_VALUE } ?: 0),
                    "channelCount" to (fmt.channelCount.takeIf { it != Format.NO_VALUE } ?: 0),
                    "bitrate"      to (fmt.bitrate.takeIf      { it != Format.NO_VALUE } ?: 0),
                    "mimeType"     to (fmt.sampleMimeType ?: ""),
                    "codecs"       to (fmt.codecs        ?: ""),
                    "pcmEncoding"  to (fmt.pcmEncoding.takeIf  { it != Format.NO_VALUE } ?: 0),
                ) else emptyMap()
                EventEmitter.emit("audioFormat", fmtMap)
                if (fmt != null) {
                    NativeLogger.emit(
                        "info", "Media3",
                        "Audio format: ${fmt.sampleMimeType} " +
                        "${if (fmt.sampleRate    != Format.NO_VALUE) "${fmt.sampleRate}Hz " else ""}" +
                        "${if (fmt.channelCount  != Format.NO_VALUE) "${fmt.channelCount}ch " else ""}" +
                        "${if (fmt.bitrate       != Format.NO_VALUE) "${fmt.bitrate}bps" else ""}",
                    )
                }
            }

            /**
             * Logs seek-driven position discontinuities for session audit.
             * Emits a state snapshot so Flutter position indicator snaps
             * immediately on seek completion instead of waiting for the next
             * position tick.
             */
            override fun onPositionDiscontinuity(
                oldPosition: Player.PositionInfo,
                newPosition: Player.PositionInfo,
                @Player.DiscontinuityReason reason: Int,
            ) {
                if (!isActiveEvent()) return
                if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                    transportState.emitAll()
                    NativeLogger.emit(
                        "verbose", "Media3",
                        "seek discontinuity → " +
                        "${oldPosition.positionMs}ms → ${newPosition.positionMs}ms",
                    )
                }
            }
        }
        playerListeners[p] = listener
        p.addListener(listener)

        // ── AnalyticsListener — ExoPlayer-specific decoder/sink diagnostics ──
        // These events are not surfaced via Player.Listener; they require the
        // ExoPlayer-specific AnalyticsListener interface.
        val analyticsListener = object : AnalyticsListener {

            /**
             * Logs the audio decoder name and initialisation duration.
             * Useful to confirm float-output codecs are being selected (e.g.
             * raw/float decoder for FLAC vs. MediaCodec for AAC/MP3).
             */
            override fun onAudioDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long,
            ) {
                if (p !== activePlayer) return
                NativeLogger.emit(
                    "info", "Media3",
                    "AudioDecoder: $decoderName init=${initializationDurationMs}ms",
                )
            }

            /**
             * Audio underrun = the audio sink ran out of data to write to the
             * hardware. On MIUI 12 this can happen when the OS suspends the CPU
             * mid-track; it does NOT indicate a bug but should be logged.
             */
            override fun onAudioUnderrun(
                eventTime: AnalyticsListener.EventTime,
                bufferSize: Int,
                bufferSizeMs: Long,
                elapsedSinceLastFeedMs: Long,
            ) {
                NativeLogger.emit(
                    "warn", "Media3",
                    "AudioUnderrun: size=${bufferSize}B " +
                    "duration=${bufferSizeMs}ms " +
                    "elapsedSinceLastFeed=${elapsedSinceLastFeedMs}ms",
                )
            }

            /**
             * Audio sink errors (e.g. AudioTrack write failure, AudioFlinger
             * disconnect). Logged and forwarded to the SessionAuditLogger so
             * the full audit trail captures hardware-level failures.
             */
            override fun onAudioSinkError(
                eventTime: AnalyticsListener.EventTime,
                audioSinkError: Exception,
            ) {
                NativeLogger.emit("warn", "Media3", "AudioSink error: ${audioSinkError.message}")
                SessionAuditLogger.warn("AudioSink", audioSinkError.message ?: "unknown")
            }
        }
        analyticsListeners[p] = analyticsListener
        p.addAnalyticsListener(analyticsListener)
    }

    private fun detachPlayerListener(p: ExoPlayer) {
        playerListeners.remove(p)?.let { p.removeListener(it) }
        analyticsListeners.remove(p)?.let { p.removeAnalyticsListener(it) }
        // Item 6: remove PlaybackStatsListener to avoid accumulating stale sessions.
        statsListeners.remove(p)?.let { p.removeAnalyticsListener(it) }
        // Item 8: remove processor from StereoWidthManager so it is no longer updated
        // (prevents updating a ChannelMixingAudioProcessor belonging to a released player).
        playerProcessors.remove(p)?.let { stereoWidthManager.removeProcessor(it) }
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

    // ── Item helpers ──────────────────────────────────────────────────────────

    /**
     * Iterates over every live [ExoPlayer] instance (primary + secondary, deduped).
     *
     * "Live" means the player variable is non-null; it may or may not be the
     * currently active player. Using identity semantics avoids double-applying
     * an operation if primary and active point to the same object.
     */
    private fun forEachLivePlayer(block: (ExoPlayer) -> Unit) {
        val seen = Collections.newSetFromMap(IdentityHashMap<ExoPlayer, Boolean>())
        primaryPlayer?.let   { if (seen.add(it)) block(it) }
        secondaryPlayer?.let { if (seen.add(it)) block(it) }
    }

    /**
     * Item 5: Apply tunneling state to all live ExoPlayer instances and persist
     * the flag so future players created by [createConfiguredPlayer] inherit it.
     *
     * Tunneling bypasses the entire software audio pipeline (EQ, BassBoost,
     * Virtualizer, Reverb, LoudnessEnhancer, ChannelMixingAudioProcessor,
     * SonicAudioProcessor). This is expected and intentional — tunneling routes
     * PCM directly from the decoder to the audio HAL via a shared memory buffer.
     *
     * CrossfadeController's Handler-tick volume manipulation still fires but has
     * no audible effect in the tunneled path.
     */
    private fun applyTunnelingToAllPlayers(enabled: Boolean) {
        tunnelingEnabled = enabled
        if (enabled) {
            NativeLogger.emit("warn", "Media3",
                "Tunneling enabled — EQ/BassBoost/Virtualizer/StereoWidening/" +
                "Crossfade volume ramps are bypassed in the hardware path.")
        }
        forEachLivePlayer { p ->
            p.trackSelectionParameters = p.trackSelectionParameters
                .buildUpon()
                .setTunnelingEnabled(enabled)
                .build()
        }
    }

    // ── Utility ───────────────────────────────────────────────────────────────

    private fun isMiui(): Boolean = try {
        val cls = Class.forName("android.os.SystemProperties")
        val get = cls.getMethod("get", String::class.java)
        (get.invoke(cls, "ro.miui.ui.version.name") as? String)?.isNotEmpty() == true
    } catch (_: Exception) { false }
}
