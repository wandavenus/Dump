package com.example.musicplayer

import android.app.PendingIntent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.PlaybackParameters
import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class Media3PlaybackService : MediaSessionService() {
    private var player: ExoPlayer? = null
    private var session: MediaSession? = null
    private var queue: List<Map<String, Any?>> = emptyList()
    private val handler = Handler(Looper.getMainLooper())
    private val positionTicker = object : Runnable {
        override fun run() {
            emitAll()
            handler.postDelayed(this, 500L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        val exoPlayer = ExoPlayer.Builder(this).build()
        player = exoPlayer
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        session = MediaSession.Builder(this, exoPlayer)
            .setSessionActivity(pendingIntent)
            .build()
        exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) = emitAll()
            override fun onIsPlayingChanged(isPlaying: Boolean) = emitAll()
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) = emitAll()
            override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) = emitAll()
            override fun onRepeatModeChanged(repeatMode: Int) = emitAll()
        })
        instance = this
        handler.post(positionTicker)
        emitAll()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onDestroy() {
        handler.removeCallbacks(positionTicker)
        instance = null
        session?.run { player.release(); release() }
        session = null
        player = null
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
    }

    private fun currentTrackMap(): Map<String, Any?>? {
        val index = player?.currentMediaItemIndex ?: return null
        return queue.getOrNull(index)?.plus("index" to index)
    }

    private fun mediaItemFrom(map: Map<*, *>): MediaItem {
        val path = map["path"] as? String ?: ""
        val uri = if (path.startsWith("content://") || path.startsWith("file://")) path.toUri() else Uri.fromFile(java.io.File(path))
        val metadata = MediaMetadata.Builder()
            .setTitle(map["title"] as? String)
            .setArtist(map["artist"] as? String)
            .setAlbumTitle(map["album"] as? String)
            .build()
        return MediaItem.Builder()
            .setMediaId((map["id"] ?: path).toString())
            .setUri(uri)
            .setMediaMetadata(metadata)
            .build()
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val p = player ?: return result.error("not_ready", "Media3 service is not ready", null)
        when (call.method) {
            "play" -> { p.play(); result.success(null) }
            "pause" -> { p.pause(); result.success(null) }
            "stop" -> { p.stop(); result.success(null) }
            "seek" -> { p.seekTo((call.argument<Number>("position")?.toLong() ?: 0L).coerceAtLeast(0L)); result.success(null) }
            "skipNext" -> { p.seekToNextMediaItem(); result.success(null) }
            "skipPrevious" -> { p.seekToPreviousMediaItem(); result.success(null) }
            "setQueue" -> {
                @Suppress("UNCHECKED_CAST") val items = call.argument<List<Map<String, Any?>>>("queue") ?: emptyList()
                val index = call.argument<Number>("index")?.toInt() ?: 0
                queue = items
                p.setMediaItems(items.map { mediaItemFrom(it) }, index.coerceIn(0, (items.size - 1).coerceAtLeast(0)), 0L)
                p.prepare(); emitAll(); result.success(null)
            }
            "setTrack" -> { p.seekToDefaultPosition(call.argument<Number>("index")?.toInt() ?: 0); result.success(null) }
            "setRepeatMode" -> {
                p.repeatMode = when (call.argument<String>("mode")) {
                    "one" -> Player.REPEAT_MODE_ONE
                    "all" -> Player.REPEAT_MODE_ALL
                    else -> Player.REPEAT_MODE_OFF
                }; result.success(null)
            }
            "setShuffleMode" -> { p.shuffleModeEnabled = call.argument<Boolean>("enabled") ?: false; result.success(null) }
            "setVolume" -> { p.volume = (call.argument<Number>("volume")?.toFloat() ?: 1f).coerceIn(0f, 1f); result.success(null) }
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
            "setEqualizerEnabled", "setEqualizerBandGain", "setLoudnessTargetGain", "setLoudnessEnabled" -> result.success(null)
            "getEqualizerParameters" -> result.success(mapOf("minDecibels" to -15.0, "maxDecibels" to 15.0, "bands" to listOf(0, 1, 2, 3, 4)))
            else -> result.notImplemented()
        }
        emitAll()
    }

    companion object { var instance: Media3PlaybackService? = null }

    object Events {
        private val sinks = mutableMapOf<String, EventChannel.EventSink?>()
        fun handler(name: String) = object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sinks[name] = events; instance?.emitAll() }
            override fun onCancel(arguments: Any?) { sinks[name] = null }
        }
        fun emit(name: String, value: Any?) { sinks[name]?.success(value) }
    }
}
