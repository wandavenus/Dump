package com.example.musicplayer

import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.events.NativeLogger

/**
 * A ForwardingPlayer that is permanently set as the MediaSession's player
 * (never replaced by session.setPlayer()). On crossfade promotion, [switchTo]
 * migrates all MediaSession/AVRCP listeners from the old player to the new one
 * so that lock-screen / BT controllers keep receiving correct state events.
 *
 * All transport commands (play, pause, skip, seek) are routed through the
 * supplied lambdas (which delegate to TransportCommands in production) so audio
 * focus, crossfade cancellation, SessionAuditLogger, and position ticker are
 * handled identically regardless of the command source (Flutter MethodChannel,
 * Bluetooth AVRCP, lock screen, Android Auto).
 *
 * MED-01: seekTo() with a non-INDEX_UNSET mediaItemIndex is forwarded as a
 * queue jump ([onSetTrack]) instead of silently dropping the index.
 *
 * Extracted from a private inner class of Media3PlaybackService to allow JVM
 * unit testing without a service context. Production wiring passes lambdas that
 * delegate to TransportCommands; tests supply lightweight lambda stubs.
 *
 * @param initialPlayer The first active ExoPlayer instance.
 * @param onPlay        Called when MediaSession/AVRCP requests play.
 * @param onPause       Called when MediaSession/AVRCP requests pause.
 * @param onSkipNext    Called when MediaSession/AVRCP requests skip-next.
 * @param onSkipPrev    Called when MediaSession/AVRCP requests skip-previous.
 * @param onSeek        Called with position ms when a plain seek is requested.
 * @param onSetTrack    Called with queue index when seekTo(index, pos) specifies a
 *                      non-current mediaItemIndex (AVRCP/Android Auto queue jump).
 */
@UnstableApi
internal class ActivePlayerProxy(
    initialPlayer: ExoPlayer,
    private val onPlay:     () -> Unit,
    private val onPause:    () -> Unit,
    private val onSkipNext: () -> Unit,
    private val onSkipPrev: () -> Unit,
    private val onSeek:     (Long) -> Unit,
    private val onSetTrack: (Int)  -> Unit,
) : ForwardingPlayer(initialPlayer) {

    private val registeredListeners = mutableListOf<Player.Listener>()
    @Volatile private var _current: ExoPlayer = initialPlayer

    /** Returns the current wrapped player — defence-in-depth for any Media3 internal
     *  code that calls [getWrappedPlayer] directly rather than the per-method overrides. */
    override fun getWrappedPlayer(): Player = _current

    /**
     * Migrate all registered listeners from the current wrapped player to [newPlayer].
     * Must be called on the main thread. Invoked by the switchSessionPlayer lambda
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
    //
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

    override fun getCurrentTimeline(): Timeline       = _current.currentTimeline
    override fun getCurrentPeriodIndex(): Int         = _current.currentPeriodIndex
    override fun isPlaying(): Boolean                 = _current.isPlaying
    override fun getPlaybackState(): Int              = _current.playbackState
    override fun getCurrentMediaItemIndex(): Int      = _current.currentMediaItemIndex
    override fun getCurrentMediaItem(): MediaItem?    = _current.currentMediaItem
    override fun getCurrentPosition(): Long           = _current.currentPosition
    override fun getDuration(): Long                  = _current.duration
    override fun getBufferedPosition(): Long          = _current.bufferedPosition
    override fun isLoading(): Boolean                 = _current.isLoading
    override fun getVolume(): Float                   = _current.volume
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
    override fun getPlayWhenReady(): Boolean            = _current.playWhenReady
    override fun getPlayerError(): PlaybackException?   = _current.playerError

    override fun getMediaItemCount(): Int               = _current.mediaItemCount
    override fun getMediaItemAt(index: Int): MediaItem  = _current.getMediaItemAt(index)
    override fun getNextMediaItemIndex(): Int            = _current.nextMediaItemIndex
    override fun getPreviousMediaItemIndex(): Int        = _current.previousMediaItemIndex
    override fun hasNextMediaItem(): Boolean            = _current.hasNextMediaItem()
    override fun hasPreviousMediaItem(): Boolean        = _current.hasPreviousMediaItem()

    override fun getTotalBufferedDuration(): Long       = _current.totalBufferedDuration
    override fun getContentPosition(): Long             = _current.contentPosition
    override fun getContentBufferedPosition(): Long     = _current.contentBufferedPosition
    override fun getContentDuration(): Long             = _current.contentDuration

    override fun isPlayingAd(): Boolean                 = _current.isPlayingAd
    override fun getCurrentAdGroupIndex(): Int          = _current.currentAdGroupIndex
    override fun getCurrentAdIndexInAdGroup(): Int      = _current.currentAdIndexInAdGroup

    override fun getCurrentTracks(): Tracks             = _current.currentTracks
    override fun getTrackSelectionParameters(): TrackSelectionParameters =
        _current.trackSelectionParameters
    override fun getMediaMetadata(): MediaMetadata      = _current.mediaMetadata
    override fun getPlaylistMetadata(): MediaMetadata   = _current.playlistMetadata

    override fun getPlaybackParameters(): PlaybackParameters = _current.playbackParameters
    override fun getRepeatMode(): @Player.RepeatMode Int     = _current.repeatMode
    override fun getShuffleModeEnabled(): Boolean            = _current.shuffleModeEnabled
    override fun getSeekBackIncrement(): Long                = _current.seekBackIncrement
    override fun getSeekForwardIncrement(): Long             = _current.seekForwardIncrement
    override fun getMaxSeekToPreviousPosition(): Long        = _current.maxSeekToPreviousPosition

    override fun getAvailableCommands(): Player.Commands     = _current.availableCommands

    override fun getVideoSize(): VideoSize              = _current.videoSize
    override fun getCurrentCues(): CueGroup             = _current.currentCues

    // Intentionally NOT overriding:
    //   getApplicationLooper() — always the main Looper; identical for all
    //     ExoPlayer instances in this service.
    //   getAudioAttributes()   — all players are built with the same config
    //     in createConfiguredPlayer(); attributes are invariant across players.
    //   getDeviceInfo()        — hardware device descriptor; invariant.
    //   getDeviceVolume() / isDeviceMuted() — system master volume; not
    //     per-player; hardware state is the same regardless of which player
    //     queries it.

    // ── Transport command overrides — always go through supplied lambdas ─────
    override fun play()                    { onPlay() }
    override fun pause()                   { onPause() }
    override fun seekToNextMediaItem()     { onSkipNext() }
    override fun seekToPreviousMediaItem() { onSkipPrev() }

    override fun seekTo(mediaItemIndex: Int, positionMs: Long) {
        if (mediaItemIndex != C.INDEX_UNSET &&
            mediaItemIndex != _current.currentMediaItemIndex) {
            // MED-01 fix: external controller requested a specific queue item.
            onSetTrack(mediaItemIndex)
        } else {
            onSeek(positionMs)
        }
    }
}
