package com.example.musicplayer

import android.net.Uri
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * A [SimpleBasePlayer] that holds MediaKit playback state for the [MediaSession].
 *
 * This player does NOT produce audio — it is a state mirror used exclusively so
 * the Android OS can present lock-screen controls, BT AVRCP metadata, and a
 * media-style notification.
 *
 * Metadata and playback state are pushed from Flutter via
 * [MediaKitPlaybackService.handle]. Transport commands from the system (lock
 * screen buttons, BT, Wear OS) are forwarded back to Flutter via the callbacks
 * supplied at construction time, which delegate to [MediaKitEventEmitter].
 *
 * [invalidateState] is called after every state mutation so the [MediaSession]
 * and all registered listeners receive an up-to-date snapshot.
 */
@OptIn(UnstableApi::class)
class MediaKitStatePlayer(
    private val onPlay:     () -> Unit,
    private val onPause:    () -> Unit,
    private val onSkipNext: () -> Unit,
    private val onSkipPrev: () -> Unit,
    private val onSeek:     (positionMs: Long) -> Unit,
) : SimpleBasePlayer(Looper.getMainLooper()) {

    // Current track metadata
    private var title:      String  = ""
    private var artist:     String  = ""
    private var artworkUri: String? = null
    private var durationMs: Long    = 0L

    // Playback state
    @Volatile private var isPlaying:  Boolean = false
    @Volatile private var positionMs: Long    = 0L

    // ── State mutations ───────────────────────────────────────────────────────

    /** Push new track metadata and invalidate the player state. */
    fun updateMetadata(title: String, artist: String, artworkUri: String?, durationMs: Long) {
        this.title      = title
        this.artist     = artist
        this.artworkUri = artworkUri
        this.durationMs = durationMs
        invalidateState()
    }

    /** Push new playback state (playing / paused, position) and invalidate. */
    fun updatePlaybackState(isPlaying: Boolean, positionMs: Long) {
        this.isPlaying  = isPlaying
        this.positionMs = positionMs
        invalidateState()
    }

    // ── SimpleBasePlayer contract ─────────────────────────────────────────────

    override fun getState(): State {
        val hasTrack = title.isNotEmpty()
        val artUri   = artworkUri?.let { Uri.parse(it) }

        val playlist = if (hasTrack) {
            val mediaItem = MediaItem.Builder()
                .setMediaMetadata(
                    MediaMetadata.Builder()
                        .setTitle(title)
                        .setArtist(artist)
                        .setArtworkUri(artUri)
                        .build()
                )
                .build()
            listOf(
                MediaItemData.Builder("mediakit_current_track")
                    .setMediaItem(mediaItem)
                    .setDurationUs(if (durationMs > 0L) durationMs * 1_000L else -1L)
                    .build()
            )
        } else {
            emptyList()
        }

        val commands = Player.Commands.Builder()
            .addAll(
                Player.COMMAND_PLAY_PAUSE,
                Player.COMMAND_SEEK_TO_NEXT,
                Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
                Player.COMMAND_GET_CURRENT_MEDIA_ITEM,
                Player.COMMAND_GET_TIMELINE,
                Player.COMMAND_GET_METADATA,
            )
            .build()

        // Capture position for the lambda below (must be a val, not var).
        val capturedPosition = positionMs

        return State.Builder()
            .setAvailableCommands(commands)
            .setPlayWhenReady(
                isPlaying,
                Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST,
            )
            .setPlaybackState(if (hasTrack) Player.STATE_READY else Player.STATE_IDLE)
            .setPlaylist(playlist)
            .setCurrentMediaItemIndex(0)
            .setContentPositionMs(SimpleBasePlayer.PositionSupplier { capturedPosition })
            .build()
    }

    /**
     * System issued play or pause (lock screen, BT, headset button).
     * Forward to the engine via [onPlay] / [onPause].
     */
    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        if (playWhenReady) onPlay() else onPause()
        return Futures.immediateVoidFuture()
    }

    /**
     * System issued a seek command (skip next/prev, seek bar, default position).
     * Each variant is forwarded to the appropriate engine callback.
     */
    override fun handleSeek(
        mediaItemIndex: Int,
        positionMs: Long,
        seekCommand: Int,
    ): ListenableFuture<*> {
        when (seekCommand) {
            Player.COMMAND_SEEK_TO_NEXT               -> onSkipNext()
            Player.COMMAND_SEEK_TO_PREVIOUS           -> onSkipPrev()
            Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM -> onSeek(positionMs)
            Player.COMMAND_SEEK_TO_DEFAULT_POSITION   -> onSeek(0L)
            else -> {}
        }
        return Futures.immediateVoidFuture()
    }
}
