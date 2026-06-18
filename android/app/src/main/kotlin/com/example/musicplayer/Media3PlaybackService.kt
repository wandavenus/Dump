package com.example.musicplayer

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
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
    private var loudnessTargetMb = 0

    private val positionTicker = object : Runnable {
        override fun run() {
            emitAll()
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

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val exoPlayer = ExoPlayer.Builder(this).build().apply {
            val attrs = androidx.media3.common.AudioAttributes.Builder()
                .setUsage(androidx.media3.common.C.USAGE_MEDIA)
                .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MUSIC)
                .build()
            setAudioAttributes(attrs, false)
            setHandleAudioBecomingNoisy(true)
        }
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
            override fun onAudioSessionIdChanged(audioSessionId: Int) { attachEffects(audioSessionId); emitAll() }
        })
        registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        instance = this
        handler.post(positionTicker)
        emitAll()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onDestroy() {
        handler.removeCallbacks(positionTicker)
        try { unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
        abandonAudioFocus()
        releaseEffects()
        instance = null
        session?.run { player?.release(); release() }
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
        Events.emit("audioSessionId", p.audioSessionId)
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
        return MediaItem.Builder().setMediaId((map["id"] ?: path).toString()).setUri(uri).setMediaMetadata(metadata).build()
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val p = player ?: return result.error("not_ready", "Media3 service is not ready", null)
        when (call.method) {
            "play" -> { if (requestAudioFocus()) p.play(); result.success(null) }
            "pause" -> { p.pause(); abandonAudioFocus(); result.success(null) }
            "stop" -> { p.stop(); abandonAudioFocus(); result.success(null) }
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
            "setRepeatMode" -> { p.repeatMode = when (call.argument<String>("mode")) { "one" -> Player.REPEAT_MODE_ONE; "all" -> Player.REPEAT_MODE_ALL; else -> Player.REPEAT_MODE_OFF }; result.success(null) }
            "setShuffleMode" -> { p.shuffleModeEnabled = call.argument<Boolean>("enabled") ?: false; result.success(null) }
            "setVolume" -> { p.volume = (call.argument<Number>("volume")?.toFloat() ?: 1f).coerceIn(0f, 1f); volumeBeforeDuck = p.volume; result.success(null) }
            "setSpeed" -> { val speed = (call.argument<Number>("speed")?.toFloat() ?: 1f).coerceIn(0.25f, 4f); p.playbackParameters = PlaybackParameters(speed, p.playbackParameters.pitch); result.success(null) }
            "setPitch" -> { val pitch = (call.argument<Number>("pitch")?.toFloat() ?: 1f).coerceIn(0.5f, 2f); p.playbackParameters = PlaybackParameters(p.playbackParameters.speed, pitch); result.success(null) }
            "setEqualizerEnabled" -> { setEqualizerEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }
            "setEqualizerBandGain" -> { setEqualizerBandGain((call.argument<Number>("band")?.toInt() ?: 0).toShort(), ((call.argument<Number>("gainDb")?.toDouble() ?: 0.0) * 100).toInt().toShort()); result.success(null) }
            "setLoudnessTargetGain" -> { setLoudnessTargetGain((call.argument<Number>("gainMb")?.toInt() ?: 0)); result.success(null) }
            "setLoudnessEnabled" -> { setLoudnessEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }
            "getEqualizerParameters" -> result.success(equalizerParameters())
            else -> result.notImplemented()
        }
        emitAll()
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

    private fun attachEffects(sessionId: Int) {
        if (sessionId <= 0) return
        releaseEffects()
        try { equalizer = Equalizer(0, sessionId).apply { enabled = eqEnabled; bandGains.forEach { (b, g) -> setBandLevel(b, g.coerceIn(bandLevelRange[0], bandLevelRange[1])) } } } catch (_: Exception) {}
        try { loudness = LoudnessEnhancer(sessionId).apply { setTargetGain(loudnessTargetMb); enabled = loudnessEnabled } } catch (_: Exception) {}
    }

    private fun releaseEffects() { try { equalizer?.release() } catch (_: Exception) {}; try { loudness?.release() } catch (_: Exception) {}; equalizer = null; loudness = null }
    private fun setEqualizerEnabled(enabled: Boolean) { eqEnabled = enabled; try { equalizer?.enabled = enabled } catch (_: Exception) {} }
    private fun setEqualizerBandGain(band: Short, gain: Short) { bandGains[band] = gain; try { equalizer?.let { it.setBandLevel(band, gain.coerceIn(it.bandLevelRange[0], it.bandLevelRange[1])) } } catch (_: Exception) {} }
    private fun setLoudnessTargetGain(gainMb: Int) { loudnessTargetMb = gainMb; try { loudness?.setTargetGain(gainMb) } catch (_: Exception) {} }
    private fun setLoudnessEnabled(enabled: Boolean) { loudnessEnabled = enabled; try { loudness?.enabled = enabled } catch (_: Exception) {} }
    private fun equalizerParameters(): Map<String, Any> = try { val eq = equalizer ?: Equalizer(0, player?.audioSessionId ?: 0).also { equalizer = it }; mapOf("minDecibels" to eq.bandLevelRange[0] / 100.0, "maxDecibels" to eq.bandLevelRange[1] / 100.0, "bands" to List(eq.numberOfBands.toInt()) { it }) } catch (_: Exception) { mapOf("minDecibels" to -15.0, "maxDecibels" to 15.0, "bands" to listOf(0, 1, 2, 3, 4)) }

    companion object { var instance: Media3PlaybackService? = null }
    object Events {
        private val sinks = mutableMapOf<String, EventChannel.EventSink?>()
        fun handler(name: String) = object : EventChannel.StreamHandler { override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sinks[name] = events; instance?.emitAll() }; override fun onCancel(arguments: Any?) { sinks[name] = null } }
        fun emit(name: String, value: Any?) { sinks[name]?.success(value) }
    }
}
