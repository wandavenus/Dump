package com.example.musicplayer

import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import androidx.media3.common.AudioAttributes
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
import java.util.Collections
import java.util.IdentityHashMap

/**
 * ActivePlayerProxy — a [ForwardingPlayer] whose backing [ExoPlayer] can be
 * atomically switched at runtime via [switchTo].
 *
 * # Why this class exists
 *
 * The dual-player crossfade architecture promotes a standby [ExoPlayer] to
 * active during a fade.  The naive approach calls [androidx.media3.session.MediaSession.setPlayer]
 * with the new raw player.  This is unsafe: Media3's internal `PlayerWrapper`
 * calls `createPositionInfo()` which reads several fields—timeline,
 * currentMediaItemIndex, currentPosition, contentPosition, isPlayingAd,
 * currentAdGroupIndex, currentAdIndexInAdGroup—in one synchronised block.
 * If those fields are read from *different* ExoPlayer instances (a "mixed
 * snapshot"), the timeline and index can be inconsistent and the resulting
 * `getWindow()` call throws [IllegalStateException].
 *
 * By keeping the [MediaSession] player object constant (always this proxy) and
 * instead swapping the internal `_current` reference, every getter in a single
 * call stack is guaranteed to originate from one and the same ExoPlayer.
 *
 * # What is intentionally NOT overridden
 *
 * * `getApplicationLooper()` — always the main [android.os.Looper]; identical
 *   for every ExoPlayer created in this service.
 * * `getAudioAttributes()` — all players are built with an identical audio
 *   session config via `createConfiguredPlayer()`.
 * * `getDeviceInfo()` — hardware device descriptor; invariant.
 * * `getDeviceVolume()` / `isDeviceMuted()` — hardware master volume; invariant.
 *
 * # Threading
 *
 * [switchTo] MUST be called on the main looper thread (same thread ExoPlayer
 * requires for all API calls). `_current` is [@Volatile][Volatile] so that
 * reads on the main thread always see the latest reference without a
 * synchronised block.
 */
@UnstableApi
class ActivePlayerProxy(initialPlayer: ExoPlayer) : ForwardingPlayer(initialPlayer) {

    @Volatile
    private var _current: ExoPlayer = initialPlayer

    /**
     * Tracks every listener registered via [addListener] so they can be
     * migrated to the new player atomically in [switchTo].
     *
     * Uses identity semantics (same object = same listener) to match
     * ExoPlayer's own listener deduplication behaviour.
     */
    private val registeredListeners: MutableSet<Player.Listener> =
        Collections.newSetFromMap(Collections.synchronizedMap(IdentityHashMap()))

    // ── Public API ─────────────────────────────────────────────────────────────

    /**
     * Atomically replace the backing player.
     *
     * All listeners currently registered on the old player are removed and
     * re-registered on [newPlayer] before the `_current` reference is updated,
     * so no events are lost between the two players during the switch.
     *
     * Must be called on the main looper thread.
     */
    fun switchTo(newPlayer: ExoPlayer) {
        val old = _current
        if (old === newPlayer) return
        val listeners = registeredListeners.toList()
        for (l in listeners) {
            try { old.removeListener(l) } catch (_: Exception) {}
        }
        _current = newPlayer
        for (l in listeners) {
            try { newPlayer.addListener(l) } catch (_: Exception) {}
        }
    }

    // ── Listener management ────────────────────────────────────────────────────

    override fun addListener(listener: Player.Listener) {
        registeredListeners.add(listener)
        _current.addListener(listener)
    }

    override fun removeListener(listener: Player.Listener) {
        registeredListeners.remove(listener)
        _current.removeListener(listener)
    }

    // ── Playback state ─────────────────────────────────────────────────────────
    // These MUST all come from _current to prevent a mixed-snapshot crash inside
    // PlayerWrapper.createPositionInfo().  Every field read in that method is
    // listed in the first block below.

    override fun getPlaybackState(): Int = _current.playbackState

    override fun getPlaybackSuppressionReason(): @Player.PlaybackSuppressionReason Int =
        _current.playbackSuppressionReason

    override fun isPlaying(): Boolean = _current.isPlaying

    override fun isLoading(): Boolean = _current.isLoading

    override fun getPlayWhenReady(): Boolean = _current.playWhenReady

    override fun getPlayerError(): PlaybackException? = _current.playerError

    // ── Timeline / item index — the core createPositionInfo() fields ───────────

    override fun getCurrentTimeline(): Timeline = _current.currentTimeline

    /**
     * Delegates to [_current].
     *
     * Justification: [androidx.media3.session.MediaSession] internal
     * `createPositionInfo()` calls `getCurrentTimeline()` AND
     * `getCurrentMediaItemIndex()` in one block. If they originate from
     * different players the resulting `getWindow(index, ...)` can throw.
     */
    override fun getCurrentMediaItemIndex(): Int = _current.currentMediaItemIndex

    /**
     * Delegates to [_current].
     *
     * Justification: `createPositionInfo()` also calls `getCurrentPeriodIndex()`.
     * Must be consistent with the timeline returned by [getCurrentTimeline].
     */
    override fun getCurrentPeriodIndex(): Int = _current.currentPeriodIndex

    override fun getCurrentMediaItem(): MediaItem? = _current.currentMediaItem

    override fun getMediaItemCount(): Int = _current.mediaItemCount

    /**
     * Delegates to [_current].
     *
     * Justification: index-based item lookup must be consistent with the
     * timeline from the same player.  Reading from a different player could
     * return an item at an index that does not exist in the current timeline.
     */
    override fun getMediaItemAt(index: Int): MediaItem = _current.getMediaItemAt(index)

    /**
     * Delegates to [_current].
     *
     * Justification: the next-item index is computed from the current timeline
     * and shuffle order.  A stale value from the old player during promotion
     * would be incorrect for the new player's queue.
     */
    override fun getNextMediaItemIndex(): Int = _current.nextMediaItemIndex

    /**
     * Delegates to [_current].
     *
     * Justification: symmetric with [getNextMediaItemIndex]; derived from the
     * current timeline and shuffle order on the active player.
     */
    override fun getPreviousMediaItemIndex(): Int = _current.previousMediaItemIndex

    override fun hasNextMediaItem(): Boolean = _current.hasNextMediaItem()

    override fun hasPreviousMediaItem(): Boolean = _current.hasPreviousMediaItem()

    // ── Position / duration — also part of createPositionInfo() ───────────────

    override fun getCurrentPosition(): Long = _current.currentPosition

    override fun getDuration(): Long = _current.duration

    override fun getBufferedPosition(): Long = _current.bufferedPosition

    override fun getTotalBufferedDuration(): Long = _current.totalBufferedDuration

    override fun getContentPosition(): Long = _current.contentPosition

    override fun getContentBufferedPosition(): Long = _current.contentBufferedPosition

    override fun getContentDuration(): Long = _current.contentDuration

    // ── Ad state — part of createPositionInfo() ────────────────────────────────

    override fun isPlayingAd(): Boolean = _current.isPlayingAd

    override fun getCurrentAdGroupIndex(): Int = _current.currentAdGroupIndex

    override fun getCurrentAdIndexInAdGroup(): Int = _current.currentAdIndexInAdGroup

    // ── Track selection & metadata ─────────────────────────────────────────────

    override fun getCurrentTracks(): Tracks = _current.currentTracks

    override fun getTrackSelectionParameters(): TrackSelectionParameters =
        _current.trackSelectionParameters

    override fun getMediaMetadata(): MediaMetadata = _current.mediaMetadata

    override fun getPlaylistMetadata(): MediaMetadata = _current.playlistMetadata

    // ── Playback parameters ────────────────────────────────────────────────────

    override fun getPlaybackParameters(): PlaybackParameters = _current.playbackParameters

    override fun getRepeatMode(): @Player.RepeatMode Int = _current.repeatMode

    override fun getShuffleModeEnabled(): Boolean = _current.shuffleModeEnabled

    override fun getSeekBackIncrement(): Long = _current.seekBackIncrement

    override fun getSeekForwardIncrement(): Long = _current.seekForwardIncrement

    override fun getMaxSeekToPreviousPosition(): Long = _current.maxSeekToPreviousPosition

    // ── Commands ───────────────────────────────────────────────────────────────

    override fun getAvailableCommands(): Player.Commands = _current.availableCommands

    override fun isCommandAvailable(command: @Player.Command Int): Boolean =
        _current.isCommandAvailable(command)

    // ── Volume & video ─────────────────────────────────────────────────────────

    override fun getVolume(): Float = _current.volume

    override fun getVideoSize(): VideoSize = _current.videoSize

    override fun getCurrentCues(): CueGroup = _current.currentCues

    // ── Command methods ────────────────────────────────────────────────────────
    // Overriding these ensures that if any caller (MediaSession, BT controller,
    // or internal Media3 machinery) issues a command through this proxy, it
    // reaches _current — not the stale wrappedPlayer from before promotion.
    // The outer anonymous ForwardingPlayer(proxy) intercepts play/pause/seek for
    // TransportCommands routing; these overrides are the safety net for everything
    // else that passes through without interception.

    override fun prepare() = _current.prepare()

    override fun play() = _current.play()

    override fun pause() = _current.pause()

    override fun stop() = _current.stop()

    override fun setPlayWhenReady(playWhenReady: Boolean) =
        _current.setPlayWhenReady(playWhenReady)

    override fun seekToDefaultPosition() = _current.seekToDefaultPosition()

    override fun seekToDefaultPosition(mediaItemIndex: Int) =
        _current.seekToDefaultPosition(mediaItemIndex)

    override fun seekTo(positionMs: Long) = _current.seekTo(positionMs)

    override fun seekTo(mediaItemIndex: Int, positionMs: Long) =
        _current.seekTo(mediaItemIndex, positionMs)

    override fun seekBack() = _current.seekBack()

    override fun seekForward() = _current.seekForward()

    override fun seekToNextMediaItem() = _current.seekToNextMediaItem()

    override fun seekToNext() = _current.seekToNext()

    override fun seekToPreviousMediaItem() = _current.seekToPreviousMediaItem()

    override fun seekToPrevious() = _current.seekToPrevious()

    override fun setRepeatMode(repeatMode: @Player.RepeatMode Int) =
        _current.setRepeatMode(repeatMode)

    override fun setShuffleModeEnabled(shuffleModeEnabled: Boolean) =
        _current.setShuffleModeEnabled(shuffleModeEnabled)

    override fun setMediaItem(mediaItem: MediaItem) = _current.setMediaItem(mediaItem)

    override fun setMediaItem(mediaItem: MediaItem, resetPosition: Boolean) =
        _current.setMediaItem(mediaItem, resetPosition)

    override fun setMediaItem(mediaItem: MediaItem, startPositionMs: Long) =
        _current.setMediaItem(mediaItem, startPositionMs)

    override fun setMediaItems(mediaItems: MutableList<MediaItem>) =
        _current.setMediaItems(mediaItems)

    override fun setMediaItems(mediaItems: MutableList<MediaItem>, resetPosition: Boolean) =
        _current.setMediaItems(mediaItems, resetPosition)

    override fun setMediaItems(
        mediaItems: MutableList<MediaItem>,
        startIndex: Int,
        startPositionMs: Long,
    ) = _current.setMediaItems(mediaItems, startIndex, startPositionMs)

    override fun addMediaItem(mediaItem: MediaItem) = _current.addMediaItem(mediaItem)

    override fun addMediaItem(index: Int, mediaItem: MediaItem) =
        _current.addMediaItem(index, mediaItem)

    override fun addMediaItems(mediaItems: MutableList<MediaItem>) =
        _current.addMediaItems(mediaItems)

    override fun addMediaItems(index: Int, mediaItems: MutableList<MediaItem>) =
        _current.addMediaItems(index, mediaItems)

    override fun moveMediaItem(currentIndex: Int, newIndex: Int) =
        _current.moveMediaItem(currentIndex, newIndex)

    override fun moveMediaItems(fromIndex: Int, toIndex: Int, newIndex: Int) =
        _current.moveMediaItems(fromIndex, toIndex, newIndex)

    override fun replaceMediaItem(index: Int, mediaItem: MediaItem) =
        _current.replaceMediaItem(index, mediaItem)

    override fun replaceMediaItems(
        fromIndex: Int,
        toIndex: Int,
        mediaItems: MutableList<MediaItem>,
    ) = _current.replaceMediaItems(fromIndex, toIndex, mediaItems)

    override fun removeMediaItem(index: Int) = _current.removeMediaItem(index)

    override fun removeMediaItems(fromIndex: Int, toIndex: Int) =
        _current.removeMediaItems(fromIndex, toIndex)

    override fun clearMediaItems() = _current.clearMediaItems()

    override fun setPlaybackParameters(playbackParameters: PlaybackParameters) =
        _current.setPlaybackParameters(playbackParameters)

    override fun setPlaybackSpeed(speed: Float) = _current.setPlaybackSpeed(speed)

    override fun setVolume(volume: Float) = _current.setVolume(volume)

    override fun setAudioAttributes(audioAttributes: AudioAttributes, handleAudioFocus: Boolean) =
        _current.setAudioAttributes(audioAttributes, handleAudioFocus)

    override fun setTrackSelectionParameters(parameters: TrackSelectionParameters) =
        _current.setTrackSelectionParameters(parameters)

    override fun setPlaylistMetadata(mediaMetadata: MediaMetadata) =
        _current.setPlaylistMetadata(mediaMetadata)

    // ── Video surface — delegate so surface attachment follows the active player ─

    override fun setVideoSurface(surface: Surface?) = _current.setVideoSurface(surface)

    override fun clearVideoSurface() = _current.clearVideoSurface()

    override fun clearVideoSurface(surface: Surface?) = _current.clearVideoSurface(surface)

    override fun setVideoSurfaceHolder(surfaceHolder: SurfaceHolder?) =
        _current.setVideoSurfaceHolder(surfaceHolder)

    override fun clearVideoSurfaceHolder(surfaceHolder: SurfaceHolder?) =
        _current.clearVideoSurfaceHolder(surfaceHolder)

    override fun setVideoSurfaceView(surfaceView: SurfaceView?) =
        _current.setVideoSurfaceView(surfaceView)

    override fun clearVideoSurfaceView(surfaceView: SurfaceView?) =
        _current.clearVideoSurfaceView(surfaceView)

    override fun setVideoTextureView(textureView: TextureView?) =
        _current.setVideoTextureView(textureView)

    override fun clearVideoTextureView(textureView: TextureView?) =
        _current.clearVideoTextureView(textureView)
}
