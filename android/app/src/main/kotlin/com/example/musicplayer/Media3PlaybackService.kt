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
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.PlaybackException
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
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.analytics.PlaybackStatsListener
import androidx.media3.exoplayer.audio.AudioCapabilitiesReceiver
import androidx.media3.exoplayer.audio.DefaultAudioSink
import com.example.musicplayer.effects.StereoWideningAudioProcessor
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
    private val playerProcessors     = IdentityHashMap<ExoPlayer, StereoWideningAudioProcessor>() // Item 8

    // ── Item 1: skip silence — persisted so new standby players inherit state ─
    private var skipSilenceEnabled = false

    // ── Item 3 & 8: capability receiver and stereo width manager ─────────────
    private var audioCapReceiver: AudioCapabilitiesReceiver? = null
    private lateinit var stereoWidthManager: StereoWidthManager

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

        @Volatile var instance: Media3PlaybackService? = null
    }

    // ── CRIT-01 + MED-01 fix: ActivePlayerProxy ──────────────────────────────
    /**
     * A ForwardingPlayer that is permanently set as the MediaSession's player
     * (never replaced by session.setPlayer()). On crossfade promotion, [switchTo]
     * migrates all MediaSession/AVRCP listeners from the old player to the new one
     * so that lock-screen / BT controllers keep receiving correct state events.
     *
     * All transport commands (play, pause, skip, seek) are routed through
     * [TransportCommands] so audio focus, crossfade cancellation, SessionAuditLogger,
     * and position ticker are handled identically regardless of the command source
     * (Flutter MethodChannel, Bluetooth AVRCP, lock screen, Android Auto).
     *
     * MED-01: seekTo() with a non-INDEX_UNSET mediaItemIndex is forwarded as a
     * queue jump (setTrackNative) instead of silently dropping the index.
     */
    private inner class ActivePlayerProxy(initialPlayer: ExoPlayer) : ForwardingPlayer(initialPlayer) {
        private val registeredListeners = mutableListOf<Player.Listener>()
        @Volatile private var _current: ExoPlayer = initialPlayer

        /** Returns the current wrapped player — used for all state queries. */
        override fun getWrappedPlayer(): Player = _current

        /**
         * Migrate all registered listeners from the current wrapped player to [newPlayer].
         * Must be called on the main thread. Invoked by the [switchSessionPlayer] lambda
         * in CrossfadeController when crossfade begins and when promotion completes.
         */
        fun switchTo(newPlayer: ExoPlayer) {
            if (newPlayer === _current) return
            val snapshot = registeredListeners.toList()
            snapshot.forEach { _current.removeListener(it) }
            _current = newPlayer
            snapshot.forEach { _current.addListener(it) }
            NativeLogger.emit("info", "Media3",
                "ActivePlayerProxy.switchTo: migrated ${snapshot.size} listener(s)")
        }

        override fun addListener(listener: Player.Listener) {
            if (listener !in registeredListeners) registeredListeners.add(listener)
            _current.addListener(listener)
        }

        override fun removeListener(listener: Player.Listener) {
            registeredListeners.remove(listener)
            _current.removeListener(listener)
        }

        // ── State-query overrides — delegate to _current, not initialPlayer ──────
        // ForwardingPlayer stores the constructor argument as a final `player` field
        // and uses it for ALL method implementations by default.  After switchTo(),
        // _current points to the promoted standby player, so every state getter must
        // be overridden here or it will return stale data from the original player.
        //
        // CE-05 (crash fix): PlayerWrapper.createPositionInfo() (Media3 1.10.1,
        // line 879) reads THREE values from the proxy and cross-checks them:
        //
        //   currentMediaItemIndex  — index into the current timeline
        //   currentTimeline        — used to look up the window at that index
        //   currentPeriodIndex     — must lie within [window.firstPeriod, window.lastPeriod]
        //
        // If any of those three come from a different ExoPlayer instance they can be
        // mutually inconsistent.  Example crash path:
        //   • Primary player has a 24-item rebuilt queue playing at window 23, period 23.
        //   • Crossfade promotes standby (1-item list, currentMediaItemIndex = 0).
        //   • currentMediaItemIndex → standby = 0  (overridden below ✓)
        //   • currentTimeline       → primary = 24-window timeline  (NOT overridden → BUG)
        //   • currentPeriodIndex    → primary = 23                  (NOT overridden → BUG)
        //   • getWindow(0) in primary timeline → firstPeriod=0, lastPeriod=0
        //   • checkState(23 == constrainValue(23, 0, 0))  →  FATAL IllegalStateException
        //
        // Overriding all three (and the rest of the state surface) ensures every
        // field in createPositionInfo() is sourced from the same ExoPlayer.
        override fun getCurrentTimeline(): Timeline     = _current.currentTimeline
        override fun getCurrentPeriodIndex(): Int       = _current.currentPeriodIndex
        override fun isPlaying(): Boolean               = _current.isPlaying
        override fun getPlaybackState(): Int            = _current.playbackState
        override fun getCurrentMediaItemIndex(): Int    = _current.currentMediaItemIndex
        override fun getCurrentMediaItem(): MediaItem?  = _current.currentMediaItem
        override fun getCurrentPosition(): Long         = _current.currentPosition
        override fun getDuration(): Long                = _current.duration
        override fun getBufferedPosition(): Long        = _current.bufferedPosition
        override fun isLoading(): Boolean               = _current.isLoading
        override fun getVolume(): Float                 = _current.volume
        override fun isCommandAvailable(command: Int): Boolean =
            _current.isCommandAvailable(command)

        // ── Remaining snapshot getters — delegate to _current ──────────────────
        //
        // Every field below is part of the player's observable state surface.
        // If any getter returns stale data from the old (pre-promotion) player
        // after switchTo(), external controllers (OS media widget, lock screen,
        // AVRCP, Android Auto) see an incoherent state.
        //
        // Evaluation notes per method:
        //
        //  getPlaybackSuppressionReason() — dynamic; changes when audio focus
        //    is lost or the app is in the background; per-player.
        //  getPlayWhenReady() — the intent flag may differ between players if
        //    standby was started with play=false during prewarm.
        //  getPlayerError() — errors are tracked per ExoPlayer instance.
        //  getMediaItemCount() — queue length on _current; differs during
        //    crossfade window (standby has 1 item, primary has N).
        //  getMediaItemAt(index) — index lookup must use the same item list as
        //    getCurrentTimeline(); a cross-player read risks IndexOutOfBounds.
        //  getNextMediaItemIndex() / getPreviousMediaItemIndex() — computed from
        //    _current's timeline + shuffle mode; wrong player → wrong track.
        //  hasNextMediaItem() / hasPreviousMediaItem() — derived from timeline.
        //  getTotalBufferedDuration() / getContentPosition() /
        //    getContentBufferedPosition() / getContentDuration() — per-player
        //    buffer accounting.
        //  isPlayingAd() / getCurrentAdGroupIndex() / getCurrentAdIndexInAdGroup()
        //    — part of createPositionInfo(); must be consistent with the timeline
        //    from the same player even though these players never play ads.
        //  getCurrentTracks() / getTrackSelectionParameters() — per-player;
        //    track selection runs independently for each ExoPlayer.
        //  getMediaMetadata() / getPlaylistMetadata() — reflect the loaded item
        //    on _current; stale metadata causes wrong lock-screen artwork.
        //  getPlaybackParameters() — speed/pitch are per-player.
        //  getRepeatMode() / getShuffleModeEnabled() — per-player state flags.
        //  getSeekBack/ForwardIncrement() / getMaxSeekToPreviousPosition() —
        //    configured per-player via DefaultSeekParameters; same value in
        //    practice but delegating avoids surprises if configs diverge.
        //  getAvailableCommands() — command set depends on current player state.
        //  getVideoSize() / getCurrentCues() — per-player; follow _current so
        //    video and subtitle output are always from the active player.

        override fun getPlaybackSuppressionReason(): @Player.PlaybackSuppressionReason Int =
            _current.playbackSuppressionReason
        override fun getPlayWhenReady(): Boolean          = _current.playWhenReady
        override fun getPlayerError(): PlaybackException? = _current.playerError

        override fun getMediaItemCount(): Int              = _current.mediaItemCount
        override fun getMediaItemAt(index: Int): MediaItem = _current.getMediaItemAt(index)
        override fun getNextMediaItemIndex(): Int           = _current.nextMediaItemIndex
        override fun getPreviousMediaItemIndex(): Int       = _current.previousMediaItemIndex
        override fun hasNextMediaItem(): Boolean           = _current.hasNextMediaItem()
        override fun hasPreviousMediaItem(): Boolean       = _current.hasPreviousMediaItem()

        override fun getTotalBufferedDuration(): Long      = _current.totalBufferedDuration
        override fun getContentPosition(): Long            = _current.contentPosition
        override fun getContentBufferedPosition(): Long    = _current.contentBufferedPosition
        override fun getContentDuration(): Long            = _current.contentDuration

        override fun isPlayingAd(): Boolean                = _current.isPlayingAd
        override fun getCurrentAdGroupIndex(): Int         = _current.currentAdGroupIndex
        override fun getCurrentAdIndexInAdGroup(): Int     = _current.currentAdIndexInAdGroup

        override fun getCurrentTracks(): Tracks            = _current.currentTracks
        override fun getTrackSelectionParameters(): TrackSelectionParameters =
            _current.trackSelectionParameters
        override fun getMediaMetadata(): MediaMetadata     = _current.mediaMetadata
        override fun getPlaylistMetadata(): MediaMetadata  = _current.playlistMetadata

        override fun getPlaybackParameters(): PlaybackParameters = _current.playbackParameters
        override fun getRepeatMode(): @Player.RepeatMode Int     = _current.repeatMode
        override fun getShuffleModeEnabled(): Boolean            = _current.shuffleModeEnabled
        override fun getSeekBackIncrement(): Long                = _current.seekBackIncrement
        override fun getSeekForwardIncrement(): Long             = _current.seekForwardIncrement
        override fun getMaxSeekToPreviousPosition(): Long        = _current.maxSeekToPreviousPosition

        override fun getAvailableCommands(): Player.Commands     = _current.availableCommands

        override fun getVideoSize(): VideoSize             = _current.videoSize
        override fun getCurrentCues(): CueGroup            = _current.currentCues

        // Intentionally NOT overriding:
        //   getApplicationLooper() — always the main Looper; identical for all
        //     ExoPlayer instances in this service.
        //   getAudioAttributes()   — all players are built with the same config
        //     in createConfiguredPlayer(); attributes are invariant across players.
        //   getDeviceInfo()        — hardware device descriptor; invariant.
        //   getDeviceVolume() / isDeviceMuted() — system master volume; not
        //     per-player; hardware state is the same regardless of which player
        //     queries it.

        // ── Transport command overrides — always go through TransportCommands ────
        override fun play()                    { transportCommands.playNative() }
        override fun pause()                   { transportCommands.pauseNative() }
        override fun seekToNextMediaItem()     { transportCommands.skipNextNative() }
        override fun seekToPreviousMediaItem() { transportCommands.skipPrevNative() }

        override fun seekTo(mediaItemIndex: Int, positionMs: Long) {
            if (mediaItemIndex != C.INDEX_UNSET &&
                mediaItemIndex != _current.currentMediaItemIndex) {
                // MED-01 fix: external controller requested a specific queue item.
                transportCommands.setTrackNative(mediaItemIndex)
            } else {
                transportCommands.seekNative(positionMs)
            }
        }
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
        // LOW-07 fix: track the initial offload listener so it can be removed before
        // adding a new one on crossfade completion (prevents listener accumulation).
        activeOffloadListener = offloadManager.makeOffloadListener()
        primaryPlayer!!.addAudioOffloadListener(activeOffloadListener!!)

        // Build MediaSession
        // CRIT-01 fix: MediaSession always uses activePlayerProxy — never replaced by a raw
        // ExoPlayer. ActivePlayerProxy.switchTo() migrates MediaSession/AVRCP listeners to the
        // new player on crossfade promotion so lock-screen and BT controllers remain in sync.
        // transportCommands is lateinit but fully initialised before any external controller
        // can connect (connections only happen after onCreate() returns).
        activePlayerProxy = ActivePlayerProxy(primaryPlayer!!)
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val sessionBuilder = MediaSession.Builder(this, activePlayerProxy)
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
                // LOW-07 fix: remove the old offload listener before adding the new one.
                // Previously a new listener was added on every crossfade without removing
                // the previous one, causing accumulation across many crossfades.
                val newOffloadListener = offloadManager.makeOffloadListener()
                activeOffloadListener?.let { activePlayer?.removeAudioOffloadListener(it) }
                activeOffloadListener = newOffloadListener
                activePlayer?.addAudioOffloadListener(newOffloadListener)
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

        // Item 8: each player gets its own StereoWideningAudioProcessor so
        // stereo widening can be applied/updated atomically during crossfade.
        val channelMixingProc: StereoWideningAudioProcessor =
            if (::stereoWidthManager.isInitialized) stereoWidthManager.createProcessor()
            else StereoWideningAudioProcessor()

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
        //
        // DefaultAudioSink.DefaultAudioProcessorChain is the official public API in Media3 1.10.1.
        // It accepts a vararg of user AudioProcessors to insert BEFORE its own
        // SilenceSkippingAudioProcessor (for skip-silence) and SonicAudioProcessor (speed/pitch).
        // All three features — stereo widening, skip-silence, and playback speed — are preserved.
        val renderersFactory = object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean,
            ): DefaultAudioSink = DefaultAudioSink.Builder(context)
                .setEnableFloatOutput(enableFloatOutput)
                .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                // channelMixingProc runs first, then SilenceSkipping, then Sonic.
                .setAudioProcessorChain(DefaultAudioSink.DefaultAudioProcessorChain(channelMixingProc))
                .build()
        }
            .setEnableAudioFloatOutput(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
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
                SessionAuditLogger.warn("PlayerError",
                    "code=${error.errorCode} msg=${error.message}")
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

    // ── Utility ───────────────────────────────────────────────────────────────

    private fun isMiui(): Boolean = try {
        val cls = Class.forName("android.os.SystemProperties")
        val get = cls.getMethod("get", String::class.java)
        (get.invoke(cls, "ro.miui.ui.version.name") as? String)?.isNotEmpty() == true
    } catch (_: Exception) { false }
}
