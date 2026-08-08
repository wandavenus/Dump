package dev.wndavenz.music

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
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.common.PlaybackException
import dev.wndavenz.music.audio_focus.AudioFocusManager
import dev.wndavenz.music.audio_offload.AudioOffloadManager
import dev.wndavenz.music.crossfade.CrossfadeController
import dev.wndavenz.music.crossfade.PreloadManager
import dev.wndavenz.music.effects.AudioEffectsManager
import dev.wndavenz.music.events.EventEmitter
import dev.wndavenz.music.events.NativeLogger
import dev.wndavenz.music.events.ServiceReadyGate
import dev.wndavenz.music.notification.PlaybackNotificationManager
import dev.wndavenz.music.queue.QueueManager
import dev.wndavenz.music.queue.QueueSync
import dev.wndavenz.music.sleep_timer.SleepTimerManager
import dev.wndavenz.music.transport.PlayPauseFadeController
import dev.wndavenz.music.transport.TransportCommands
import dev.wndavenz.music.transport.TransportState
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
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.ToFloatPcmAudioProcessor
import androidx.media3.common.audio.ToInt16PcmAudioProcessor
import dev.wndavenz.music.diagnostics.CrossfadeTimelineLogger
import dev.wndavenz.music.effects.NativeDspAudioProcessor
import dev.wndavenz.music.effects.StereoWideningAudioProcessor
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.flac.FlacExtractor
import androidx.media3.session.CommandButton
import dev.wndavenz.music.effects.StereoWidthManager

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

    // ── Bit-Perfect Mode: dedicated processing-free player ────────────────────
    // A third ExoPlayer instance with zero custom AudioProcessors and zero
    // attached AudioEffects, used only while Bit-Perfect Mode is enabled. It
    // never runs concurrently with primaryPlayer/secondaryPlayer — crossfade
    // is force-cancelled and the standby player released before switching to
    // it, and it is switched away from before crossfade/effects can resume.
    private var bitPerfectPlayer:    ExoPlayer? = null
    private var bitPerfectModeOn:    Boolean = false
    private var preBitPerfectPlayer: ExoPlayer? = null

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
    private lateinit var playPauseFadeController: PlayPauseFadeController
    private lateinit var offloadManager:       AudioOffloadManager
    private lateinit var shutdownCoordinator:  ServiceShutdownCoordinator
    // ART-01: artwork cache shared between notification and full-player pipelines.
    private lateinit var serviceArtworkCache:  ArtworkCacheManager

    // Single-thread executor for off-main-thread I/O (URI metadata reads, etc.).
    // Shut down in onDestroy() so tasks don't outlive the service.
    private val ioExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()

    // ── Listener registry (prevents double-attach / leaks) ────────────────────
    private val playerListeners      = IdentityHashMap<ExoPlayer, Player.Listener>()
    private val analyticsListeners   = IdentityHashMap<ExoPlayer, AnalyticsListener>()

    /** Decoder name stored by onAudioDecoderInitialized for the active player.
     *  Read by onTracksChanged to include in the audioFormat EventChannel event. */
    @Volatile private var activeDecoderName: String = ""
    @Volatile private var activeDecoderIsHardware: Boolean = false
    private val statsListeners       = IdentityHashMap<ExoPlayer, PlaybackStatsListener>()  // Item 6
    private val playerProcessors     = IdentityHashMap<ExoPlayer, StereoWideningAudioProcessor>() // Item 8
    private val playerStretchProcessors = IdentityHashMap<ExoPlayer, dev.wndavenz.music.effects.SignalsmithStretchAudioProcessor>()

    // Phase 9 — last audio MIME per player, tracked from onAudioInputFormatChanged
    // so onAudioDecoderInitialized can include it in the "ffmpegDecoderInfo" event
    // without needing to query the player synchronously off the analytics thread.
    private val lastAudioMimeType    = IdentityHashMap<ExoPlayer, String>()

    // ── Item 3 & 8: capability receiver and stereo width manager ─────────────
    private var audioCapReceiver: AudioCapabilitiesReceiver? = null
    private lateinit var stereoWidthManager: StereoWidthManager

    // Signalsmith Stretch — playback speed + pitch shift, replacing Sonic.
    // See StretchManager doc for why this needs its own manager (per-instance
    // native state, unlike the shared-global NativeDspAudioProcessor pipeline).
    private lateinit var stretchManager: dev.wndavenz.music.effects.StretchManager

    // ── CRIT-01 fix: session player proxy ─────────────────────────────────────
    // activePlayerProxy is always the MediaSession's player. It dynamically
    // delegates to the current active ExoPlayer and routes transport commands
    // through TransportCommands so audio focus / crossfade handling is consistent.
    private lateinit var activePlayerProxy: ActivePlayerProxy

    // ── LOW-07 fix: track the active offload listener so it can be removed ────
    private var activeOffloadListener: ExoPlayer.AudioOffloadListener? = null

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
        /**
         * Sent by NowPlayingOverlayActivity when the user opens an audio file
         * from a file manager or another app. Triggers immediate native playback
         * without requiring the Flutter UI to be ready.
         */
        const val ACTION_PLAY_URI = "dev.wndavenz.music.ACTION_PLAY_URI"
        const val EXTRA_URI       = "uri"

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
        stretchManager = dev.wndavenz.music.effects.StretchManager()

        // Create primary player — always physical stream slot 0.
        primaryPlayer = createConfiguredPlayer(streamSlot = 0)
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
        // LOW-07 fix: track the initial offload listener so it can be removed before
        // adding a new one on crossfade completion (prevents listener accumulation).
        activeOffloadListener = offloadManager.makeOffloadListener()
        val initialPlayer   = primaryPlayer   ?: return
        val offloadListener = activeOffloadListener ?: return
        initialPlayer.addAudioOffloadListener(offloadListener)

        // Build MediaSession
        // CRIT-01 fix: MediaSession always uses activePlayerProxy — never replaced by a raw
        // ExoPlayer. ActivePlayerProxy.switchTo() migrates MediaSession/AVRCP listeners to the
        // new player on crossfade promotion so lock-screen and BT controllers remain in sync.
        // transportCommands is lateinit but fully initialised before any external controller
        // can connect (connections only happen after onCreate() returns).
        activePlayerProxy = ActivePlayerProxy(
            initialPlayer = initialPlayer,
            onPlay        = { transportCommands.playNative() },
            onPause       = { transportCommands.pauseNative() },
            onSkipNext    = { transportCommands.skipNextNative() },
            onSkipPrev    = { transportCommands.skipPrevNative() },
            onSeek        = { transportCommands.seekNative(it) },
            onSetTrack    = { transportCommands.setTrackNative(it) },
        )
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val sessionBuilder = MediaSession.Builder(this, activePlayerProxy)
            // Explicit unique ID prevents "Session ID must be unique" crash when
            // Media3PlaybackService and MediaKitPlaybackService are both alive briefly
            // during an engine switch (both would otherwise default to ID="").
            .setId("media3_playback_session")
            // Use FallbackBitmapLoader so MediaSessionLegacyStub (Bluetooth / lock screen)
            // can load album art even for songs whose embedded artwork has not been indexed
            // by MediaStore (e.g. FLAC files from Telegram).  The loader tries the standard
            // albumart content URI first, then falls back to MediaMetadataRetriever.
            .setBitmapLoader(FallbackBitmapLoader(this))
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

        // ART-01: initialise artwork cache for notification fallback pipeline.
        // Shares the same on-disk WebP cache ({filesDir}/artwork/) as MainActivity's
        // ArtworkCacheManager so cache hits from Full Player warm-up are reused here.
        serviceArtworkCache = ArtworkCacheManager(this)

        // Wire feature modules ────────────────────────────────────────────────

        audioFocusManager = AudioFocusManager(
            audioManager           = getSystemService(Context.AUDIO_SERVICE) as AudioManager,
            getPlayer              = { activePlayer },
            startTicker            = { transportState.startPositionTicker() },
            stopTicker             = { transportState.stopPositionTicker() },
            onFocusEvent           = { transportState.emitAll() },
            getCrossfadeInProgress = { crossfadeController.crossfadeInProgress },
            // HIGH-01 fix: cancel any in-progress crossfade when audio focus is lost.
            // Without this, AUDIOFOCUS_LOSS only paused the new (active) player while
            // the old promotionOwner player continued producing audio through a call.
            onFocusLoss = {
                if (::crossfadeController.isInitialized && crossfadeController.crossfadeInProgress) {
                    NativeLogger.emit("warn", "AudioFocus",
                        "Audio focus lost during crossfade — cancelling crossfade")
                    crossfadeController.cancel(resetVolume = true)
                }
            },
        )

        notificationManager = PlaybackNotificationManager(
            service              = this,
            handler              = handler,
            getSession           = { session },
            getIsPlaying         = { activePlayer?.isPlaying ?: false },
            getCurrentTrack      = { transportState.currentTrackMap() },
            serviceClass         = Media3PlaybackService::class.java,
            // ART-01: inject shared artwork cache so notification uses same pipeline as Full Player.
            artworkCacheManager  = serviceArtworkCache,
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
            // The standby player being (re)built always lands in whichever
            // physical slot is not currently active — see setStandbyPlayer
            // below, which places it into primaryPlayer or secondaryPlayer
            // accordingly. Slot must match here so its NativeDspAudioProcessor
            // is tagged correctly BEFORE it starts decoding.
            createPlayer       = {
                val slot = if (activePlayer === primaryPlayer) 1 else 0
                createConfiguredPlayer(streamSlot = slot)
            },
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
                // CRIT-01 fix: update the proxy's wrapped player instead of calling
                // session.setPlayer(). The MediaSession stays bound to activePlayerProxy
                // permanently; listeners are migrated to the new ExoPlayer by switchTo().
                try { activePlayerProxy.switchTo(newPlayer) }
                catch (e: Exception) {
                    NativeLogger.emit("warn", "Media3", "ActivePlayerProxy.switchTo failed: ${e.message}")
                }
            },
            preloadManager      = preloadManager,
            getVolumeBeforeDuck = { audioFocusManager.volumeBeforeDuck },
            getEffectiveVolume  = { audioFocusManager.effectiveVolume() },
            hasAudioFocus       = { audioFocusManager.hasAudioFocus() },
            requestAudioFocus   = { audioFocusManager.request() },
            getQueue            = { queueManager.queue },
            getActiveQueueIndex = { queueManager.activeQueueIndex },
            setActiveQueueIndex = { idx -> queueManager.setActiveQueueIndex(idx) },
            onCrossfadeComplete = {
                // ── Dropout investigation: snapshot player state at the start of this callback.
                // Everything from here through the end of the lambda is a potential dropout cause.
                val p0 = activePlayer
                CrossfadeTimelineLogger.stamp(
                    "onCrossfadeComplete CB: ENTER" +
                    " session=${p0?.audioSessionId} items=${p0?.mediaItemCount}", p0)

                // CE-03 fix: rebuild full queue on promoted player (non-interrupting).
                // *** SUSPECT #1: setMediaItems() on playing player may force decoder rebuild ***
                CrossfadeTimelineLogger.stamp(
                    "onCrossfadeComplete CB: calling rebuildPlayerQueue() START", p0)
                queueManager.rebuildPlayerQueue()
                val p1 = activePlayer
                CrossfadeTimelineLogger.stamp(
                    "onCrossfadeComplete CB: rebuildPlayerQueue() DONE" +
                    " items=${p1?.mediaItemCount}", p1)

                queueSync.save()

                // Re-attach all audio effects to the new active player's audio session.
                // The new player was a "cold" secondary player with no effects attached.
                // *** SUSPECT #2: releaseEffects() + AudioEffect constructors against live session ***
                val newSessionId = activePlayer?.audioSessionId ?: 0
                CrossfadeTimelineLogger.stamp(
                    "onCrossfadeComplete CB: calling attachEffects(session=$newSessionId) START", activePlayer)
                if (newSessionId > 0) {
                    effectsManager.attachEffects(newSessionId)
                    NativeLogger.emit("info", "Media3",
                        "Post-crossfade effects reattach → session=$newSessionId")
                }
                CrossfadeTimelineLogger.stamp(
                    "onCrossfadeComplete CB: attachEffects DONE session=$newSessionId", activePlayer)

                // Re-evaluate offload state on the newly promoted player.
                // Also attach the offload listener to the new active player so OS
                // grant/reject events are still reported after player promotion.
                offloadManager.onCrossfadeComplete()
                // LOW-07 fix: remove the old offload listener before adding the new one.
                // Previously a new listener was added on every crossfade without removing
                // the previous one, causing accumulation across many crossfades.
                val newOffloadListener = offloadManager.makeOffloadListener()
                activeOffloadListener?.let { activePlayer?.removeAudioOffloadListener(it) }
                activeOffloadListener = newOffloadListener
                activePlayer?.addAudioOffloadListener(newOffloadListener)

                CrossfadeTimelineLogger.stamp(
                    "onCrossfadeComplete CB: EXIT (offload listener swapped)", activePlayer)
            },
            emitAll             = { transportState.emitAll() },
            refreshNotification = { notificationManager.refresh() },
            // Disable offload scheduling before the first 16 ms Handler tick so the
            // equal-power fade runs with reliable timing on the main looper.
            onCrossfadeStarting = { offloadManager.onCrossfadeStarting() },
            // Patch B (RC-3): pre-load next track's artwork during the 1500 ms Phase 1
            // prewarm window so refresh() at crossfade start finds a bitmapCache hit.
            prewarmNotificationArtwork = { songId, artUri ->
                notificationManager.prewarmArtwork(songId, artUri)
            },
        )

        effectsManager = AudioEffectsManager(handler)

        // Play/pause volume fade — shares the same main-thread Handler as
        // CrossfadeController and defers to it whenever a crossfade is active,
        // so the two can never write player.volume at the same time.
        playPauseFadeController = PlayPauseFadeController(
            handler          = handler,
            getTargetVolume  = { audioFocusManager.volumeBeforeDuck },
            isCrossfadeActive = { crossfadeController.crossfadeInProgress },
        )

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
            playPauseFadeController = playPauseFadeController,

            // Bit-Perfect Mode: wired to the existing Dart bitPerfectMode
            // toggle (AudioEffectsService.setBitPerfectMode) via
            // TransportCommands' "setBitPerfectMode" MethodChannel method.
            setBitPerfectMode = { enabled -> setBitPerfectMode(enabled) },

            // Signalsmith Stretch — speed + pitch, replacing Sonic. Delegates
            // to StretchManager which updates every live processor instance
            // (primary + secondary/crossfade) atomically.
            onSpeedChanged = { speed -> stretchManager.setSpeed(speed) },
            onPitchSemitonesChanged = { semitones -> stretchManager.setPitchSemitones(semitones) },

            // Item 8: stereo widening — delegate to StereoWidthManager which
            // updates all ChannelMixingAudioProcessor instances atomically,
            // then echo the confirmed state back to Flutter so the UI stays
            // in sync with any future code path that updates widening without
            // going through the TransportCommands MethodChannel.
            onStereoWideningChanged = { enabled, strength ->
                stereoWidthManager.setStereoWidening(enabled, strength)
                EventEmitter.emit(
                    "stereoWidening",
                    mapOf("enabled" to enabled, "strength" to strength),
                )
            },

            // Item 6: return current PlaybackStats for the active player session.
            getPlaybackStats = {
                val statsListener = statsListeners[activePlayer]
                statsListener?.getPlaybackStats()?.let { stats ->
                    // totalBufferingTimeMs and totalErrorCount were removed in Media3 1.10.1;
                    // return 0 so the Flutter UI still renders the stats sheet correctly.
                    mapOf(
                        "totalPlayTimeMs"      to stats.totalPlayTimeMs,
                        "totalBufferingTimeMs" to 0L,
                        "totalRebufferCount"   to stats.totalRebufferCount,
                        "totalErrorCount"      to 0,
                    )
                }
            },
        )

        // When Flutter subscribes to any event stream, push the full current state
        EventEmitter.setOnSubscribeCallback { transportState.emitAll(emitQueue = true) }

        // Attach listener to primary player
        primaryPlayer?.let { attachPlayerListener(it) }

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
            // bind Equalizer / BassBoost etc.
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

        shutdownCoordinator = ServiceShutdownCoordinator(
            cancelCrossfade        = { rv -> crossfadeController.cancel(resetVolume = rv) },
            cancelSleepTimer       = { sleepTimerManager.cancel() },
            stopPositionTicker     = { transportState.stopPositionTicker() },
            emitAll                = { transportState.emitAll() },
            abandonAudioFocus      = { audioFocusManager.abandon() },
            stopForeground         = { notificationManager.stopForeground() },
            saveQueue              = { queueSync.save() },
            releaseEffects         = { effectsManager.releaseEffects() },
            clearHandlerCallbacks  = { handler.removeCallbacksAndMessages(null) },
            unregisterReceivers    = {
                try { unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
                try { audioCapReceiver?.unregister() } catch (_: Exception) {}
            },
            releasePrimaryPlayer   = { primaryPlayer?.release() },
            releaseSecondaryPlayer = { secondaryPlayer?.release() },
            releaseMediaSession    = { session?.release() },
            releaseBitPerfectPlayer = {
                bitPerfectPlayer?.let { detachPlayerListener(it); it.release() }
            },
        )

        instance = this

        restoreQueueFromPrefs()

        NativeLogger.emit(
            "info", "Media3",
            "onCreate: ExoPlayer ready (Android SDK ${Build.VERSION.SDK_INT} / MIUI=${isMiui()})"
        )
        transportState.emitAll()

        // Cold-start race fix: everything above (player, session, managers,
        // transportCommands, queue restore) is fully wired at this point — only
        // now is it safe for Dart to push settings that reach into effectsManager /
        // queueManager / crossfadeController. See ServiceReadyGate doc comment.
        ServiceReadyGate.markReady()
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

        // 1. Taruh variabel penanda ini di bagian atas class Service lu (di luar fungsi)
    private var isPreviewMode = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        
        // 2. Cek apakah ini panggilan dari overlay preview
        isPreviewMode = intent?.getBooleanExtra("IS_OVERLAY_PREVIEW", false) ?: false

        if (intent?.action == ACTION_PLAY_URI) {
            val uriStr = intent.getStringExtra(EXTRA_URI)
            if (!uriStr.isNullOrBlank() &&
                (uriStr.startsWith("file://") || uriStr.startsWith("content://") ||
                 !uriStr.contains("://"))) {
                handlePlayUri(uriStr)
            }
        } else {
            handleNotificationAction(intent?.action)
        }
        return START_STICKY
    }


    /**
     * Plays a URI opened from a file manager / external app.
     * Calls ensureMediaForeground() immediately (before any I/O) to satisfy
     * Android's 5-second foreground-service deadline, then reads metadata on a
     * background thread and triggers playback on the main thread.
     */
        private fun handlePlayUri(uriStr: String) {
        // Cuma tampilin notifikasi kalau BUKAN dalam mode preview
        if (!isPreviewMode) {
            notificationManager.ensureMediaForeground()
        }
        
        ioExecutor.execute {
            val songMap = buildSongMapFromUri(uriStr)
            handler.post {
                try {
                    crossfadeController.cancel(resetVolume = true)
                    preloadManager.releaseStandbyPlayer()
                    queueManager.setQueue(listOf(songMap), 0)
                    transportCommands.playNative()
                    NativeLogger.emit("info", "Media3",
                        "ACTION_PLAY_URI → '${songMap["title"]}'")
                } catch (e: Exception) {
                    NativeLogger.emit("error", "Media3", "handlePlayUri failed: $e")
                }
            }
        }
    }


    /** Reads title / artist / album / duration via MediaMetadataRetriever. */
    private fun buildSongMapFromUri(uriStr: String): Map<String, Any?> {
        var title     = uriStr.substringAfterLast('/').let {
            if (it.contains('?')) it.substringBefore('?') else it
        }.let { if (it.contains('.')) it.substringBeforeLast('.') else it }
            .ifBlank { "Unknown Title" }
        var artist    = "Unknown Artist"
        var album     = "Unknown Album"
        var durationMs = 0L
        val r = android.media.MediaMetadataRetriever()
        try {
            if (uriStr.startsWith("content://")) {
                r.setDataSource(applicationContext, android.net.Uri.parse(uriStr))
            } else {
                val path = if (uriStr.startsWith("file://"))
                    android.net.Uri.parse(uriStr).path ?: uriStr else uriStr
                r.setDataSource(path)
            }
            r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_TITLE)
                ?.takeIf { it.isNotBlank() }?.let { title = it }
            r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_ARTIST)
                ?.takeIf { it.isNotBlank() }?.let { artist = it }
            r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_ALBUM)
                ?.takeIf { it.isNotBlank() }?.let { album = it }
            r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()?.let { durationMs = it }
        } catch (e: Exception) {
            NativeLogger.emit("warn", "Media3", "buildSongMapFromUri metadata read failed: $e")
        } finally {
            r.release()
        }
        return mapOf(
            "id"       to 0,
            "title"    to title,
            "artist"   to artist,
            "album"    to album,
            "albumId"  to 0,
            "path"     to uriStr,
            "duration" to durationMs,
        )
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        NativeLogger.emit("info", "Media3", "onTaskRemoved — service continues (stopWithTask=false)")
    }

    override fun onDestroy() {
        // Unconditionally release the sleep timer's Handler runnables before
        // performTeardown() clears the players. This prevents timerRunnable /
        // tickRunnable / fadeRunnable from firing against a released ExoPlayer
        // when the system kills the service without a prior prepareShutdown().
        if (::sleepTimerManager.isInitialized) sleepTimerManager.release()

        // Shut down URI-metadata I/O executor (H-02 fix).
        ioExecutor.shutdown()

        // Delegate the teardown sequence to ServiceShutdownCoordinator.
        // performTeardown() is idempotent — safe even when prepareShutdown() ran
        // first (the "release" MethodChannel path) or when the system kills the
        // service without a prior prepareShutdown() (system-kill path).
        shutdownCoordinator.performTeardown()
        // The next onCreate() must go through the same wiring before it's safe
        // for Dart to push settings again — see ServiceReadyGate doc comment.
        ServiceReadyGate.reset()
        // Null out service-level fields that the coordinator cannot clear
        // because it holds lambdas, not direct field references.
        audioCapReceiver     = null
        instance             = null
        primaryPlayer        = null
        secondaryPlayer      = null
        bitPerfectPlayer     = null
        preBitPerfectPlayer  = null
        bitPerfectModeOn     = false
        activePlayer         = null
        session              = null
        super.onDestroy()
    }

    // ── MethodChannel entry point ─────────────────────────────────────────────

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        // "release" is handled here rather than in TransportCommands because it
        // must call stopSelf() — a service-level operation not available to
        // TransportCommands.  This mirrors the ACTION_STOP notification-button
        // path which already correctly triggers onDestroy() via stopSelf().
        if (call.method == "release") {
            NativeLogger.emit("info", "Media3",
                "release: complete service teardown initiated (engine switch)")
            // Phase 1: quiesce all in-flight work via ServiceShutdownCoordinator.
            // prepareShutdown() cancels crossfade/sleep-timer, stops the position
            // ticker, abandons audio focus, removes the notification, and emits a
            // final state snapshot to Flutter.
            shutdownCoordinator.prepareShutdown()
            // Acknowledge Dart before stopSelf() so the MethodChannel result is
            // delivered while the service is still fully alive.
            result.success(null)
            // stopSelf() schedules service destruction on the main looper.
            // onDestroy() then calls shutdownCoordinator.performTeardown() which
            // releases: effects, handler callbacks, receivers, both ExoPlayers,
            // and the MediaSession.  The teardownPerformed guard ensures none of
            // these are released twice even if onDestroy fires unexpectedly.
            stopSelf()
            return
        }
        transportCommands.dispatch(call, result)
    }

    // ── Notification / BT transport actions ───────────────────────────────────

    /**
     * Routes notification / Bluetooth transport button intents to [TransportCommands].
     *
     * Previously this duplicated skip/play/pause logic inline. Now every action goes
     * through the same TransportCommands path as the Flutter MethodChannel, so audio
     * focus, crossfade cleanup, and preload management are handled
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

    // streamSlot: 0 or 1 (see dsp_stream.h) — identifies which of the two
    // concurrently-possible physical players (primaryPlayer var vs
    // secondaryPlayer var) this instance is being built for, so its
    // NativeDspAudioProcessor tags every buffer with the right slot and the
    // native pipeline's per-stream runtime state (comp/limiter/peq/crossfeed/
    // loudness) never collides between the two during crossfade. Slot
    // assignment is by PHYSICAL VARIABLE, not by "active/standby" role,
    // because active/standby flips on every crossfade promotion while the
    // underlying ExoPlayer object (and its already-constructed
    // NativeDspAudioProcessor) does not change.
    private fun createConfiguredPlayer(streamSlot: Int = 0): ExoPlayer {
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

        // Phase 4.5: one NativeDspAudioProcessor per ExoPlayer instance, mirroring
        // the StereoWideningAudioProcessor pattern. BaseAudioProcessor is stateful
        // so instances must not be shared. All instances call into the same global
        // C pipeline state (gain/bypass/enable apply uniformly to both the primary
        // and secondary crossfade players — this is the intended behaviour).
        //
        // NativeDspAudioProcessor is active only for ENCODING_PCM_FLOAT (float32).
        // ToFloatPcmAudioProcessor below guarantees that format explicitly. The
        // sink's own float-output branch stays disabled because that branch omits
        // this custom AudioProcessorChain for high-resolution decoder output.
        //
        // If libnative_audio_runtime.so is absent or the Dart-side pipeline has not
        // yet been initialised, audio passes through unmodified (fail-open).
        val nativeDspProc = NativeDspAudioProcessor(streamSlot)

        // Option B: explicit format-guard processors bracketing the custom chain.
        // ToFloatPcmAudioProcessor forces PCM_FLOAT into NativeDsp/StereoWiden/Stretch
        // regardless of what the decoder actually emits (isActive() is a transparent
        // no-op when the input is already PCM_FLOAT). ToInt16PcmAudioProcessor converts
        // back to 16-bit before Media3's internal SilenceSkipping/Sonic stage, so the
        // custom chain's float-domain assumptions never leak downstream. Both are
        // public @UnstableApi BaseAudioProcessor subclasses (Media3 1.10.1,
        // androidx.media3.exoplayer.audio / androidx.media3.common.audio) — stateful,
        // so a fresh instance is required per ExoPlayer/player build, same as the
        // other processors in this chain.
        val toFloatProc = ToFloatPcmAudioProcessor()
        val toInt16Proc = ToInt16PcmAudioProcessor()

        // Item 8: each player gets its own StereoWideningAudioProcessor so
        // stereo widening can be applied/updated atomically during crossfade.
        val channelMixingProc: StereoWideningAudioProcessor =
            if (::stereoWidthManager.isInitialized) stereoWidthManager.createProcessor()
            else StereoWideningAudioProcessor()

        // Signalsmith Stretch — replaces Sonic for both playback speed and
        // pitch shift (see StretchManager / SignalsmithStretchAudioProcessor
        // docs). Placed last in the chain, exactly where Sonic used to sit.
        val stretchProc: dev.wndavenz.music.effects.SignalsmithStretchAudioProcessor =
            if (::stretchManager.isInitialized) stretchManager.createProcessor()
            else dev.wndavenz.music.effects.SignalsmithStretchAudioProcessor()

        // Custom DefaultRenderersFactory that injects the custom processor chain.
        //
        // IMPORTANT: DefaultAudioSink's float-output branch adds its internal
        // ToFloat processor but does NOT append the custom AudioProcessorChain.
        // Leaving float output enabled therefore bypasses NativeDsp, stereo
        // widening, and Signalsmith for high-resolution decoder output such as
        // FFmpeg FLAC at 44.1 kHz.
        //
        // The explicit chain below still converts every input to float, applies
        // the custom processors, then converts back to PCM16.
        //
        // NativeDspAudioProcessor runs first: PCM is routed through the native DSP
        // pipeline (C: dsp_pipeline.c + gain_processor.c) in-place via JNI
        // GetDirectBufferAddress() — zero further copy after the initial bulk-copy
        // required by BaseAudioProcessor's contract.
        //
        // Item 2: setEnableDecoderFallback(true) — on MIUI 12, hardware audio
        // decoders (OMX.qcom.audio.*) occasionally crash on FLAC or long files.
        // With fallback enabled, ExoPlayer silently retries with the software
        // decoder (FFmpeg extension) instead of surfacing an error to the user.
        //
        // buildAudioSink() is the officially supported extension point in
        // DefaultRenderersFactory for injecting custom AudioProcessors.
        //
        // DefaultAudioSink.DefaultAudioProcessorChain is the official public API in
        // Media3 1.10.1. It accepts a vararg of user AudioProcessors to insert BEFORE
        // its own SilenceSkippingAudioProcessor and SonicAudioProcessor. All features
        // — native DSP, stereo widening, skip-silence, and playback speed — are preserved.
        val renderersFactory = object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean,
            ): DefaultAudioSink {
                NativeLogger.emit(
                    "info", "Stretch",
                    "[Stretch] audio sink processor chain created order=[ToFloat,NativeDsp,StereoWiden,Stretch,ToInt16(+SilenceSkip,Sonic)] " +
                        "floatOutputEnabled=$enableFloatOutput audioTrackPlaybackParamsEnabled=$enableAudioTrackPlaybackParams " +
                        "stretchHash=${System.identityHashCode(stretchProc)} chain=StretchAwareAudioProcessorChain",
                )
                return DefaultAudioSink.Builder(context)
                    // Force the sink to use the custom chain for every input
                    // format. ToFloatPcmAudioProcessor below still guarantees
                    // float input to all custom processors.
                    .setEnableFloatOutput(false)
                    .setEnableAudioOutputPlaybackParameters(enableAudioTrackPlaybackParams)
                    // Chain order (Option B): ToFloat → NativeDsp → StereoWiden →
                    // Stretch (speed+pitch) → ToInt16 → SilenceSkip. ToFloat guarantees
                    // the custom DSP/widening/stretch stages always see PCM_FLOAT
                    // (transparent no-op if the decoder already emits float); ToInt16
                    // converts back before Media3's own internal SilenceSkipping/Sonic
                    // stage so nothing downstream has to reason about float input.
                    // Stretch fully replaces Sonic here — DefaultAudioProcessorChain's own
                    // internal Sonic/TeeAudioProcessor still exists downstream but is a
                    // transparent no-op as long as PlaybackParameters.speed/pitch stay at
                    // their ExoPlayer defaults (1.0/1.0), which TransportCommands now
                    // enforces — see StretchManager wiring below.
                    //
                    // StretchAwareAudioProcessorChain extends DefaultAudioProcessorChain and
                    // overrides getMediaDuration() to incorporate Signalsmith's actual I/O
                    // frame ratio before passing to Sonic (inactive → identity).  This fixes
                    // two bugs: currentPositionUs drift and READY↔BUFFERING oscillation at
                    // speed ≠ 1.0.  See StretchAwareAudioProcessorChain for the full proof.
                    .setAudioProcessorChain(
                        dev.wndavenz.music.effects.StretchAwareAudioProcessorChain(
                            stretchProc,
                            toFloatProc, nativeDspProc, channelMixingProc, stretchProc, toInt16Proc
                        )
                    )
                    .build()
            }
        }
            // Do not let DefaultAudioSink select its float-only fast branch:
            // that branch omits the custom AudioProcessorChain entirely.
            .setEnableAudioFloatOutput(false)
            // ALAC must use the bundled FFmpeg software renderer when present.
            // EXTENSION_RENDERER_MODE_PREFER places extension renderers before
            // MediaCodec renderers, avoiding devices that advertise an ALAC
            // platform decoder but output silence. Decoder fallback remains enabled
            // so Media3 can still try lower-priority decoders if initialization fails.
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            .setEnableDecoderFallback(true)  // Item 2

        // DefaultTrackSelector with explicit audio preferences.
        // For typical local music files (single audio track) this is a no-op, but for
        // multi-track containers (MKV/MP4) it ensures the highest-quality track is chosen.
        val trackSelector = DefaultTrackSelector(this).apply {
            setParameters(
                buildUponParameters()
                    .setMaxAudioChannelCount(Int.MAX_VALUE) // never downmix surround
                    .setForceLowestBitrate(false)           // prefer quality over economy
                    .build()
            )
        }

        // Item 10: CustomDefaultExtractorsFactory.
        // FLAG_DISABLE_ID3_METADATA on FLAC: jaudiotagger already reads all tags
        // (title, artist, album, lyrics) so ExoPlayer's ID3 parse during demuxing
        // is redundant overhead — especially on long FLAC files (>100 MB) where
        // the ID3 scan measurably delays the initial seek.
        // Media3 1.11.0: disable embedded-artwork parsing (MP3/MP4/FLAC).
        // Nothing reads MediaItem.mediaMetadata.artworkData — artwork is served by
        // ArtworkCacheManager / FallbackBitmapLoader via MediaMetadataRetriever —
        // so skipping it saves memory on large libraries with embedded covers.
        val extractorsFactory = DefaultExtractorsFactory()
            .setDisableArtworkMetadata(true)
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
                // Attach the offload listener when available (offloadManager is initialised
                // after the primary player in onCreate; secondary players are always created
                // after that point so the guard below covers the race-free case).
                if (::offloadManager.isInitialized) {
                    addAudioOffloadListener(offloadManager.makeOffloadListener())
                }
            }

        val ffmpegStatus = dev.wndavenz.music.ffmpeg.FfmpegCapabilityProbe.queryStatus()
        NativeLogger.emit(
            if (ffmpegStatus.available) "info" else "warn",
            "Ffmpeg",
            "Renderer config: extensionRendererMode=PREFER " +
                "decoderFallback=true moduleLinked=${BuildConfig.MEDIA3_FFMPEG_DECODER_LINKED} " +
                "classLinked=${ffmpegStatus.moduleLinked} available=${ffmpegStatus.available} " +
                "version=${ffmpegStatus.version ?: "unknown"} " +
                "supported=${ffmpegStatus.supportedCodecs.joinToString()} " +
                "playerRenderers=${(0 until player.rendererCount).joinToString { idx ->
                    "#${idx}:type=${player.getRendererType(idx)}"
                }}",
        )

        // Track the processor for this player so it can be removed from
        // StereoWidthManager when the player is released (via detachPlayerListener).
        if (::stereoWidthManager.isInitialized) {
            playerProcessors[player] = channelMixingProc
        }
        if (::stretchManager.isInitialized) {
            playerStretchProcessors[player] = stretchProc
        }

        return player
    }

    /**
     * Bit-Perfect Mode: builds a dedicated ExoPlayer with an empty audio
     * processor chain — no [NativeDspAudioProcessor], no
     * [StereoWideningAudioProcessor] — and float output disabled, since
     * nothing in this chain needs float PCM and skipping the int↔float round
     * trip avoids an unnecessary precision-loss step.
     *
     * Never registered with [stereoWidthManager] and never given an
     * [ExoPlayer.AudioOffloadListener] — this player is single-purpose and
     * only exists while Bit-Perfect Mode is on. [AudioEffectsManager] effects
     * (EQ, LoudnessEnhancer, BassBoost) are never attached to its
     * session either — see [switchToBitPerfectPlayer].
     */
    private fun createBitPerfectPlayer(): ExoPlayer {
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(15_000, 50_000, 1_500, 3_000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val renderersFactory = object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean,
            ): DefaultAudioSink = DefaultAudioSink.Builder(context)
                .setEnableFloatOutput(enableFloatOutput)
                .setEnableAudioOutputPlaybackParameters(enableAudioTrackPlaybackParams)
                // No custom AudioProcessors. Media3's own SilenceSkipping/Sonic
                // processors are still present internally (they're built into
                // DefaultAudioSink, not this chain) but are transparent no-ops
                // as long as skipSilenceEnabled=false and speed/pitch=1.0 —
                // both are forced below / left at their ExoPlayer defaults.
                .setAudioProcessorChain(DefaultAudioSink.DefaultAudioProcessorChain())
                .build()
        }
            .setEnableAudioFloatOutput(false)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            .setEnableDecoderFallback(true)

        val trackSelector = DefaultTrackSelector(this).apply {
            setParameters(
                buildUponParameters()
                    .setMaxAudioChannelCount(Int.MAX_VALUE)
                    .setForceLowestBitrate(false)
                    .build()
            )
        }

        // Media3 1.11.0: disable embedded-artwork parsing (MP3/MP4/FLAC).
        // Nothing reads MediaItem.mediaMetadata.artworkData — artwork is served by
        // ArtworkCacheManager / FallbackBitmapLoader via MediaMetadataRetriever —
        // so skipping it saves memory on large libraries with embedded covers.
        val extractorsFactory = DefaultExtractorsFactory()
            .setDisableArtworkMetadata(true)
            .setFlacExtractorFlags(FlacExtractor.FLAG_DISABLE_ID3_METADATA)
        val mediaSourceFactory = DefaultMediaSourceFactory(this, extractorsFactory)

        val player = ExoPlayer.Builder(this, renderersFactory)
            .setLoadControl(loadControl)
            .setTrackSelector(trackSelector)
            .setMediaSourceFactory(mediaSourceFactory)
            .setSeekBackIncrementMs(10_000L)
            .setSeekForwardIncrementMs(30_000L)
            .build()
            .apply {
                val attrs = androidx.media3.common.AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build()
                setAudioAttributes(attrs, false)
                setHandleAudioBecomingNoisy(false)
                setWakeMode(C.WAKE_MODE_LOCAL)
            }

        NativeLogger.emit("info", "Media3",
            "BitPerfect: dedicated clean player created (no AudioProcessors, floatOutput=false)")

        return player
    }

    // ── Player listener (glue between ExoPlayer events and feature modules) ───

    private fun attachPlayerListener(p: ExoPlayer) {
        // De-dupe listeners only — intentionally does NOT call detachPlayerListener()
        // here. detachPlayerListener() also removes the StereoWideningAudioProcessor
        // from StereoWidthManager (via playerProcessors), which leaves processors=0
        // and makes stereo widening silently inoperative for the lifetime of the
        // service. Processor cleanup belongs only in the true release path:
        // the detachListener callback passed to CrossfadeController (line 312) and
        // onDestroy. Listener de-duplication is kept here to prevent double-attach.
        playerListeners.remove(p)?.let { p.removeListener(it) }
        analyticsListeners.remove(p)?.let { p.removeAnalyticsListener(it) }
        statsListeners.remove(p)?.let { p.removeAnalyticsListener(it) }

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

    if (playbackState == Player.STATE_ENDED &&
        sleepTimerManager.sleepTimerActive &&
        sleepTimerManager.sleepEndOfSong &&
        !crossfadeController.crossfadeInProgress) {
        handler.post {
            sleepTimerManager.triggerStop()
        }
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
                // ── Dropout investigation: if the audio session ID changes AFTER the
                // crossfade completes and the player is already audible, it means
                // Android recreated the AudioTrack (and implicitly the decoder).
                // This is one of the clearest signals of a pipeline restart.
                CrossfadeTimelineLogger.stamp(
                    "onAudioSessionIdChanged: NEW session=$audioSessionId (active player)", p)
                NativeLogger.emit("info", "Media3",
                    "audioSessionId → $audioSessionId  thread=${Thread.currentThread().name}")
                // Bit-Perfect Mode: never attach AudioEffects to the dedicated
                // clean player's session — that would defeat the whole point
                // of the mode. switchFromBitPerfectPlayer() re-attaches
                // effects explicitly once we're back on a normal player.
                if (p !== bitPerfectPlayer) {
                    effectsManager.attachEffects(audioSessionId)
                }
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
                    "decoderName"  to activeDecoderName,
                    "isHardware"   to activeDecoderIsHardware,
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

            /**
             * HIGH-02 fix: Previously missing. Unhandled player errors left the
             * queue halted permanently on a corrupted or missing file.
             *
             * Behaviour:
             *  - Always logs the error and emits it to Flutter via EventChannel.
             *  - Schedules an auto-skip 500 ms later if another item is available,
             *    giving Media3 time to settle before touching the playlist.
             *  - The 500 ms delay is intentional: calling seekToNextMediaItem()
             *    synchronously inside onPlayerError causes re-entrancy issues on
             *    some Media3 versions.
             */
            override fun onPlayerError(error: PlaybackException) {
                if (!isActiveEvent()) return
                NativeLogger.emit("error", "Media3",
                    "PlayerError code=${error.errorCode}: ${error.message}")
                EventEmitter.emit("error", mapOf(
                    "code"    to error.errorCode,
                    "message" to (error.message ?: "Unknown player error"),
                ))
                if (p.hasNextMediaItem()) {
                    handler.postDelayed({
                        if (p === activePlayer &&
                            p.playbackState != Player.STATE_READY &&
                            p.hasNextMediaItem()) {
                            NativeLogger.emit("info", "Media3",
                                "Auto-skip after player error (code=${error.errorCode})")
                            p.seekToNextMediaItem()
                        }
                    }, 500L)
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
             * Fired when the audio renderer is enabled (starts processing audio).
             * During normal playback this fires once at the start.  If it fires
             * AGAIN after a crossfade completes while the player is already audible,
             * something forced the audio renderer to restart — a clear dropout cause.
             */
            override fun onAudioEnabled(
                eventTime: AnalyticsListener.EventTime,
                counters: androidx.media3.exoplayer.DecoderCounters,
            ) {
                val active = p === activePlayer
                val wall   = System.currentTimeMillis()
                CrossfadeTimelineLogger.stamp(
                    "AnalyticsListener.onAudioEnabled: isActive=$active" +
                    " wall=${wall}ms  thread=${Thread.currentThread().name}", p)
                NativeLogger.emit(
                    "info", "Media3",
                    "AudioRenderer ENABLED isActive=$active  thread=${Thread.currentThread().name}")
            }

            /**
             * Fired when the audio renderer is disabled (stops producing audio).
             * If this fires on the ACTIVE player after crossfade completes, the
             * renderer was torn down and will be restarted — that IS the dropout.
             */
            override fun onAudioDisabled(
                eventTime: AnalyticsListener.EventTime,
                counters: androidx.media3.exoplayer.DecoderCounters,
            ) {
                val active = p === activePlayer
                CrossfadeTimelineLogger.stamp(
                    "AnalyticsListener.onAudioDisabled: isActive=$active" +
                    "  decoderInitCount=${counters.decoderInitCount}" +
                    "  decoderReleaseCount=${counters.decoderReleaseCount}", p)
                NativeLogger.emit(
                    "warn", "Media3",
                    "AudioRenderer DISABLED isActive=$active" +
                    "  thread=${Thread.currentThread().name}")
            }

            /**
             * Fired when the decoder's input format changes — this triggers codec
             * reconfiguration which can force an AudioTrack flush or restart.
             * If this fires immediately after setMediaItems() or attachEffects(),
             * it is the direct cause of the dropout.
             */
            override fun onAudioInputFormatChanged(
                eventTime: AnalyticsListener.EventTime,
                format: androidx.media3.common.Format,
                decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?,
            ) {
                val active    = p === activePlayer
                val reuseStr  = decoderReuseEvaluation?.let {
                    "reuse=${it.result} discardReasons=${it.discardReasons}"
                } ?: "reuseEval=null"
                format.sampleMimeType?.let { lastAudioMimeType[p] = it }
                CrossfadeTimelineLogger.stamp(
                    "AnalyticsListener.onAudioInputFormatChanged: isActive=$active" +
                    "  mime=${format.sampleMimeType}" +
                    "  ${format.sampleRate}Hz ${format.channelCount}ch" +
                    "  $reuseStr", p)
                NativeLogger.emit(
                    "info", "Media3",
                    "Selected renderer/input format: isActive=$active" +
                    "  mime=${format.sampleMimeType} codec=${format.codecs ?: ""}" +
                    "  ${format.sampleRate}Hz ${format.channelCount}ch" +
                    "  $reuseStr  thread=${Thread.currentThread().name}")
            }

            /**
             * Logs the audio decoder name and initialisation duration.
             *
             * CRITICAL: If this fires AFTER the crossfade standby player is already
             * audible, it means the decoder was NOT pre-initialized during prewarm —
             * or it was torn down by a subsequent operation (setMediaItems / effects).
             * The initializationDurationMs is the direct acoustic dropout duration.
             */
            override fun onAudioDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long,
            ) {
                val active = p === activePlayer
                if (active) {
                    activeDecoderName = decoderName
                    activeDecoderIsHardware = !dev.wndavenz.music.ffmpeg.FfmpegCapabilityProbe
                        .isFfmpegDecoderName(decoderName)
                }
                CrossfadeTimelineLogger.stamp(
                    "AnalyticsListener.onAudioDecoderInitialized: isActive=$active" +
                    "  decoder=$decoderName initDuration=${initializationDurationMs}ms", p)
                NativeLogger.emit(
                    "info", "Media3",
                    "Selected decoder: isActive=$active" +
                    "  decoder=$decoderName" +
                    "  mime=${lastAudioMimeType[p] ?: "unknown"}" +
                    "  codec=${if (dev.wndavenz.music.ffmpeg.FfmpegCapabilityProbe.isFfmpegDecoderName(decoderName)) "FFmpeg software" else "MediaCodec/platform"}" +
                    "  hardwareSoftware=${if (dev.wndavenz.music.ffmpeg.FfmpegCapabilityProbe.isFfmpegDecoderName(decoderName)) "software" else "platform"}" +
                    "  init=${initializationDurationMs}ms" +
                    "  thread=${Thread.currentThread().name}",
                )

                // Phase 9 — FFmpeg decoder diagnostics. Consumed exclusively by
                // FfmpegDecoderBridge on the Dart side (musicplayer/ffmpeg_decoder_events).
                // Only the active player's selection is reported; the standby/prewarm
                // player's decoder init is an implementation detail, not a user-visible
                // "now playing" decoder switch.
                if (active) {
                    val mimeType = lastAudioMimeType[p]
                    val isFfmpeg = dev.wndavenz.music.ffmpeg.FfmpegCapabilityProbe
                        .isFfmpegDecoderName(decoderName)
                    val reason = dev.wndavenz.music.ffmpeg.FfmpegCapabilityProbe
                        .describeSelection(decoderName, mimeType)
                    EventEmitter.emit("ffmpegDecoderInfo", mapOf(
                        "decoderName"              to decoderName,
                        "mimeType"                 to mimeType,
                        "isFfmpegDecoder"          to isFfmpeg,
                        "initializationDurationMs" to initializationDurationMs,
                        "reason"                   to reason,
                        "rendererMode"             to "PREFER",
                        "hardwareSoftware"         to if (isFfmpeg) "software" else "platform",
                    ))
                }
            }

            /**
             * Fired when the decoder is released.  If this fires on the active player
             * during or just after a crossfade, the decoder was torn down while
             * audio was already being produced — that is the dropout.
             */
            override fun onAudioDecoderReleased(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
            ) {
                val active = p === activePlayer
                CrossfadeTimelineLogger.stamp(
                    "AnalyticsListener.onAudioDecoderReleased: isActive=$active decoder=$decoderName", p)
                NativeLogger.emit(
                    "warn", "Media3",
                    "AudioDecoder RELEASED isActive=$active decoder=$decoderName" +
                    "  thread=${Thread.currentThread().name}")
            }

            /**
             * Fired when ExoPlayer's DefaultAudioSink creates a new AudioTrack.
             * A new AudioTrack after crossfade completion means the audio output
             * pipeline was fully recreated — the platform must fill the new
             * AudioTrack's buffer before audio resumes, which is the dropout gap.
             *
             * Verified against Media3 1.10.1 source:
             *   AnalyticsListener.java line 1148–1150
             *   AudioSink.AudioTrackConfig fields: encoding, sampleRate, offload, bufferSize
             */
            override fun onAudioTrackInitialized(
                eventTime: AnalyticsListener.EventTime,
                audioTrackConfig: AudioSink.AudioTrackConfig,
            ) {
                val active = p === activePlayer
                CrossfadeTimelineLogger.stamp(
                    "AnalyticsListener.onAudioTrackInitialized: isActive=$active" +
                    "  encoding=${audioTrackConfig.encoding}" +
                    "  sampleRate=${audioTrackConfig.sampleRate}" +
                    "  offload=${audioTrackConfig.offload}" +
                    "  bufferSize=${audioTrackConfig.bufferSize}", p)
                NativeLogger.emit(
                    "info", "Media3",
                    "AudioTrack initialized / PCM sink ready: isActive=$active" +
                    "  encoding=${audioTrackConfig.encoding}" +
                    "  ${audioTrackConfig.sampleRate}Hz offload=${audioTrackConfig.offload}" +
                    "  thread=${Thread.currentThread().name}")
            }

            /**
             * Fired when the AudioTrack is released.  Pairing with onAudioTrackInitialized
             * pinpoints which operation in the post-crossfade callback chain forced an
             * AudioTrack recreation.
             *
             * Verified against Media3 1.10.1 source:
             *   AnalyticsListener.java line 1159–1161
             */
            override fun onAudioTrackReleased(
                eventTime: AnalyticsListener.EventTime,
                audioTrackConfig: AudioSink.AudioTrackConfig,
            ) {
                val active = p === activePlayer
                CrossfadeTimelineLogger.stamp(
                    "AnalyticsListener.onAudioTrackReleased: isActive=$active" +
                    "  encoding=${audioTrackConfig.encoding}" +
                    "  sampleRate=${audioTrackConfig.sampleRate}" +
                    "  offload=${audioTrackConfig.offload}", p)
                NativeLogger.emit(
                    "warn", "Media3",
                    "AudioTrack RELEASED isActive=$active" +
                    "  encoding=${audioTrackConfig.encoding} ${audioTrackConfig.sampleRate}Hz" +
                    "  thread=${Thread.currentThread().name}")
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
                CrossfadeTimelineLogger.stamp(
                    "AnalyticsListener.onAudioUnderrun: isActive=${p === activePlayer}" +
                    "  size=${bufferSize}B dur=${bufferSizeMs}ms sinceLastFeed=${elapsedSinceLastFeedMs}ms", p)
                NativeLogger.emit(
                    "warn", "Media3",
                    "AudioUnderrun: size=${bufferSize}B " +
                    "duration=${bufferSizeMs}ms " +
                    "elapsedSinceLastFeed=${elapsedSinceLastFeedMs}ms",
                )
            }

            /**
             * Audio sink errors (e.g. AudioTrack write failure, AudioFlinger
             * disconnect).
             */
            override fun onAudioSinkError(
                eventTime: AnalyticsListener.EventTime,
                audioSinkError: Exception,
            ) {
                CrossfadeTimelineLogger.stamp(
                    "AnalyticsListener.onAudioSinkError: isActive=${p === activePlayer}" +
                    "  ${audioSinkError.message}", p)
                NativeLogger.emit("warn", "Media3", "AudioSink error: ${audioSinkError.message}")
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
        // Signalsmith Stretch: same rationale, for the speed/pitch processor.
        playerStretchProcessors.remove(p)?.let { stretchManager.removeProcessor(it) }
        // Phase 9: drop the cached MIME type for this player.
        lastAudioMimeType.remove(p)
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

    // ── Bit-Perfect Mode ──────────────────────────────────────────────────────

    /**
     * Entry point called by [TransportCommands] for the "setBitPerfectMode"
     * MethodChannel method. Wired into the existing Dart bitPerfectMode toggle
     * (`AudioEffectsService.setBitPerfectMode`) — no new UI is involved.
     */
    fun setBitPerfectMode(enabled: Boolean) {
        if (enabled) switchToBitPerfectPlayer() else switchFromBitPerfectPlayer()
    }

    /**
     * Switches playback onto [bitPerfectPlayer] — a dedicated ExoPlayer with
     * no custom AudioProcessors and no attached AudioEffects. Crossfade is
     * cancelled and the standby player released first, since Bit-Perfect Mode
     * and the dual-player crossfade architecture are mutually exclusive.
     */
    private fun switchToBitPerfectPlayer() {
        if (bitPerfectModeOn) return
        val current = activePlayer ?: return
        NativeLogger.emit("info", "Media3", "BitPerfect: enabling — switching to clean player")

        // Dual-player crossfade and Bit-Perfect Mode never run together.
        crossfadeController.cancel(resetVolume = true)
        preloadManager.releaseStandbyPlayer()

        val wasPlaying = current.isPlaying
        val positionMs = current.currentPosition
        current.pause()

        // No AudioEffects during bit-perfect playback.
        effectsManager.releaseEffects()

        preBitPerfectPlayer = current

        val clean = bitPerfectPlayer ?: createBitPerfectPlayer().also {
            bitPerfectPlayer = it
            attachPlayerListener(it)
        }

        activePlayer = clean
        try {
            activePlayerProxy.switchTo(clean)
        } catch (e: Exception) {
            NativeLogger.emit("warn", "Media3", "BitPerfect: switchTo(clean) failed: ${e.message}")
        }

        if (queueManager.queue.isNotEmpty()) {
            queueManager.setQueue(queueManager.queue, queueManager.activeQueueIndex, positionMs)
        }
        if (wasPlaying) clean.play()

        bitPerfectModeOn = true
        transportState.emitAll()
        notificationManager.refresh()
        NativeLogger.emit("info", "Media3",
            "BitPerfect: active — session=${clean.audioSessionId} pos=${positionMs}ms playing=$wasPlaying")
    }

    /**
     * Restores normal playback: switches back to the dual-player pipeline
     * (the player that was active before Bit-Perfect Mode was enabled) and
     * re-attaches AudioEffects for whichever settings AudioEffectsService
     * restores next.
     */
    private fun switchFromBitPerfectPlayer() {
        if (!bitPerfectModeOn) return
        val clean = bitPerfectPlayer
        if (clean == null) { bitPerfectModeOn = false; return }
        NativeLogger.emit("info", "Media3", "BitPerfect: disabling — restoring normal pipeline")

        val wasPlaying = clean.isPlaying
        val positionMs = clean.currentPosition
        clean.pause()

        val restored = preBitPerfectPlayer ?: primaryPlayer ?: createConfiguredPlayer(streamSlot = 0).also {
            primaryPlayer = it
            attachPlayerListener(it)
        }
        preBitPerfectPlayer = null

        activePlayer = restored
        try {
            activePlayerProxy.switchTo(restored)
        } catch (e: Exception) {
            NativeLogger.emit("warn", "Media3", "BitPerfect: switchTo(restored) failed: ${e.message}")
        }

        if (queueManager.queue.isNotEmpty()) {
            queueManager.setQueue(queueManager.queue, queueManager.activeQueueIndex, positionMs)
        }

        // Re-attach AudioEffects for the restored session — the
        // onAudioSessionIdChanged listener only fires when the numeric
        // session ID actually changes, which is not guaranteed here, so
        // attach explicitly (mirrors the onCrossfadeComplete callback).
        val sid = restored.audioSessionId
        if (sid > 0) effectsManager.attachEffects(sid)

        if (wasPlaying) restored.play()

        bitPerfectModeOn = false
        transportState.emitAll()
        notificationManager.refresh()
        NativeLogger.emit("info", "Media3",
            "BitPerfect: deactivated — session=$sid pos=${positionMs}ms playing=$wasPlaying")
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

    // ── Utility ───────────────────────────────────────────────────────────────

    private fun isMiui(): Boolean = try {
        val cls = Class.forName("android.os.SystemProperties")
        val get = cls.getMethod("get", String::class.java)
        (get.invoke(cls, "ro.miui.ui.version.name") as? String)?.isNotEmpty() == true
    } catch (_: Exception) { false }
}
