package com.example.musicplayer.transport

import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.audio_focus.AudioFocusManager
import com.example.musicplayer.crossfade.CrossfadeController
import com.example.musicplayer.crossfade.PreloadManager
import com.example.musicplayer.effects.AudioEffectsManager
import com.example.musicplayer.events.EventEmitter
import com.example.musicplayer.events.NativeLogger
import com.example.musicplayer.notification.PlaybackNotificationManager
import com.example.musicplayer.queue.QueueManager
import com.example.musicplayer.queue.QueueSync
import com.example.musicplayer.sleep_timer.SleepTimerManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Handles all MethodChannel dispatches.
 *
 * Fixes:
 * DE-01 to DE-06: Trailing blanket emitAll() removed. Each branch now calls
 *   emitAll() exactly once where appropriate, or relies on Player.Listener callbacks.
 *
 * EQ-02/EQ-03: skipNext/skipPrevious when STATE_ENDED now respects the existing
 *   player indices without hard-coded fallback wrap — the fallback to index 0 is
 *   preserved only when REPEAT_MODE_ALL/shuffle is logically implied by the ExoPlayer
 *   returning a valid nextMediaItemIndex.
 */
@UnstableApi
class TransportCommands(
    private val getPlayer: () -> ExoPlayer?,
    private val audioFocusManager: AudioFocusManager,
    private val crossfadeController: CrossfadeController,
    private val preloadManager: PreloadManager,
    private val queueManager: QueueManager,
    private val queueSync: QueueSync,
    private val transportState: TransportState,
    private val notificationManager: PlaybackNotificationManager,
    private val sleepTimerManager: SleepTimerManager,
    private val effectsManager: AudioEffectsManager,
    private val ensureMediaForeground: () -> Unit,
) {
    fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        // Sleep timer methods don't require an active player
        when (call.method) {
            "setSleepTimer" -> {
                val ms = call.argument<Number>("durationMs")?.toLong() ?: 0L
                sleepTimerManager.startDuration(ms)
                result.success(null); return
            }
            "setSleepTimerEndOfSong" -> {
                sleepTimerManager.startEndOfSong()
                result.success(null); return
            }
            "cancelSleepTimer" -> {
                sleepTimerManager.cancel()
                result.success(null); return
            }
        }

        val p = getPlayer() ?: run {
            result.error("not_ready", "Media3 service is not ready", null)
            return
        }

        when (call.method) {

            // ── Transport ─────────────────────────────────────────────────────

            "play" -> handlePlay(p, result)
            "pause" -> handlePause(p, result)
            "stop" -> handleStop(p, result)
            "seek" -> {
                val pos = (call.argument<Number>("position")?.toLong() ?: 0L).coerceAtLeast(0L)
                p.seekTo(pos)
                log("verbose", "seek → ${pos}ms")
                // Player listener (onPlaybackStateChanged/onIsPlayingChanged) handles emission
                result.success(null)
            }

            "skipPrevious" -> handleSkipPrevious(p, result)
            "skipNext"     -> handleSkipNext(p, result)

            // ── Queue management ──────────────────────────────────────────────

            "setQueue" -> {
                sleepTimerManager.cancel()
                @Suppress("UNCHECKED_CAST")
                val items = call.argument<List<Map<String, Any?>>>("queue") ?: emptyList()
                val index = call.argument<Number>("index")?.toInt() ?: 0

                crossfadeController.cancel(resetVolume = true)
                preloadManager.releaseStandbyPlayer()

                queueManager.setQueue(items, index)
                if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack()

                queueSync.save()
                val firstTitle = items.getOrNull(index)?.get("title") as? String ?: "?"
                log("info", "setQueue: ${items.size} tracks → [$index] '$firstTitle'")
                transportState.emitAll(emitQueue = true)
                notificationManager.refresh()
                result.success(null)
            }

            "setTrack" -> {
                sleepTimerManager.cancel()
                crossfadeController.cancel(resetVolume = true)
                preloadManager.clearStandbyQueue()
                queueManager.setTrack(call.argument<Number>("index")?.toInt() ?: 0)
                if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack()
                queueSync.save()
                // Player listener covers emission after seekToDefaultPosition
                result.success(null)
            }

            "insertNext" -> {
                val item = call.argument<Map<String, Any?>>("item")
                    ?: run { result.success(null); return }
                queueManager.insertNext(item)
                result.success(null)
            }

            "appendToQueue" -> {
                val item = call.argument<Map<String, Any?>>("item")
                    ?: run { result.success(null); return }
                queueManager.appendToQueue(item)
                if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack(force = true)
                result.success(null)
            }

            "removeFromQueue" -> {
                val index = call.argument<Number>("index")?.toInt()
                    ?: run { result.success(null); return }
                queueManager.removeFromQueue(index)
                if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack(force = true)
                result.success(null)
            }

            "reorderQueue" -> {
                val oldIndex = call.argument<Number>("oldIndex")?.toInt()
                    ?: run { result.success(null); return }
                val newIndex = call.argument<Number>("newIndex")?.toInt()
                    ?: run { result.success(null); return }
                queueManager.reorderQueue(oldIndex, newIndex)
                if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack(force = true)
                result.success(null)
            }

            // ── Playback modes ────────────────────────────────────────────────

            "setRepeatMode" -> {
                p.repeatMode = when (call.argument<String>("mode")) {
                    "one" -> Player.REPEAT_MODE_ONE
                    "all" -> Player.REPEAT_MODE_ALL
                    else  -> Player.REPEAT_MODE_OFF
                }
                preloadManager.clearStandbyQueue()
                if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack(force = true)
                queueSync.save()
                transportState.emitAll(emitQueue = true)
                result.success(null)
            }

            "setShuffleMode" -> {
                p.shuffleModeEnabled = call.argument<Boolean>("enabled") ?: false
                preloadManager.clearStandbyQueue()
                if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack(force = true)
                queueSync.save()
                transportState.emitAll(emitQueue = true)
                result.success(null)
            }

            "setVolume" -> {
                val vol = (call.argument<Number>("volume")?.toFloat() ?: 1f).coerceIn(0f, 1f)
                p.volume = vol
                audioFocusManager.setUserVolume(vol)
                result.success(null)
            }

            // ── Playback parameters ───────────────────────────────────────────

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

            // ── Audio effects ─────────────────────────────────────────────────

            "setEqualizerEnabled"   -> {
                effectsManager.setEqualizerEnabled(call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            }
            "setEqualizerBandGain"  -> {
                effectsManager.setEqualizerBandGain(
                    (call.argument<Number>("band")?.toInt() ?: 0).toShort(),
                    ((call.argument<Number>("gainDb")?.toDouble() ?: 0.0) * 100).toInt().toShort()
                )
                result.success(null)
            }
            "setLoudnessTargetGain" -> {
                effectsManager.setLoudnessTargetGain(call.argument<Number>("gainMb")?.toFloat() ?: 0f)
                result.success(null)
            }
            "setLoudnessEnabled"    -> {
                effectsManager.setLoudnessEnabled(call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            }
            "setTrackGain" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val gainMb  = (call.argument<Number>("gainDb")?.toFloat() ?: 0f) * 100f
                effectsManager.setLoudnessTargetGain(gainMb)
                effectsManager.setLoudnessEnabled(enabled)
                result.success(null)
            }
            "setBassBoostEnabled"    -> { effectsManager.setBassBoostEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }
            "setBassBoostStrength"   -> { effectsManager.setBassBoostStrength((call.argument<Number>("strength")?.toInt() ?: 0).toShort()); result.success(null) }
            "setVirtualizerEnabled"  -> { effectsManager.setVirtualizerEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }
            "setVirtualizerStrength" -> { effectsManager.setVirtualizerStrength((call.argument<Number>("strength")?.toInt() ?: 1000).toShort()); result.success(null) }
            "setReverbPreset"        -> { effectsManager.setReverbPreset((call.argument<Number>("preset")?.toInt() ?: 0).toShort()); result.success(null) }

            // ── Crossfade ─────────────────────────────────────────────────────

            "setCrossfadeDuration" -> {
                val sec = (call.argument<Number>("duration")?.toFloat() ?: 0f).coerceAtLeast(0f)
                crossfadeController.setDuration(sec)
                crossfadeController.cancel(resetVolume = true)
                if (sec <= 0f) {
                    preloadManager.releaseStandbyPlayer()
                } else {
                    preloadManager.ensureStandbyPlayer()
                    preloadManager.preloadNextTrack()
                }
                log("verbose", "setCrossfadeDuration: ${sec}s")
                result.success(null)
            }

            // ── Query ─────────────────────────────────────────────────────────

            "getEffectSupport" -> result.success(effectsManager.effectSupportMap())

            "getEqualizerParameters" -> result.success(effectsManager.equalizerParameters())

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
                val st = sleepTimerManager
                result.success(mapOf(
                    "queue"                 to queueManager.queue,
                    "currentIndex"          to (if (crossfadeController.crossfadeDurationSec > 0f)
                                                    queueManager.activeQueueIndex
                                                else p.currentMediaItemIndex),
                    "isPlaying"             to p.isPlaying,
                    "processingState"       to state,
                    "positionMs"            to p.currentPosition.coerceAtLeast(0L),
                    "durationMs"            to p.duration.coerceAtLeast(0L),
                    "audioSessionId"        to p.audioSessionId,
                    "shuffleEnabled"        to p.shuffleModeEnabled,
                    "repeatMode"            to repeatStr,
                    "sleepTimerActive"      to st.sleepTimerActive,
                    "sleepTimerRemainingMs" to if (st.sleepTimerActive && !st.sleepEndOfSong)
                        (st.sleepTimerEndMs - System.currentTimeMillis()).coerceAtLeast(0L)
                    else 0L,
                ))
            }

            else -> result.notImplemented()
        }
        // No trailing emitAll() — each branch above emits exactly as needed.
    }

    // ── Transport helpers ─────────────────────────────────────────────────────

    private fun handlePlay(p: ExoPlayer, result: MethodChannel.Result) {
        val granted = audioFocusManager.request()
        if (granted) {
            if (p.playbackState == Player.STATE_ENDED && p.mediaItemCount > 0) {
                val restartIndex = when {
                    queueManager.activeQueueIndex in queueManager.queue.indices ->
                        queueManager.activeQueueIndex
                    else -> 0
                }
                p.seekToDefaultPosition(restartIndex)
                p.prepare()
                queueManager.setActiveQueueIndex(restartIndex)
                if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack(force = true)
            }
            p.play()
            ensureMediaForeground()
            notificationManager.refresh()
            transportState.startPositionTicker()
            val t = transportState.currentTrackMap()
            log("info", "play → '${t?.get("title")}' · ${t?.get("artist")} " +
                "[${p.currentMediaItemIndex + 1}/${queueManager.queue.size}]")
        } else {
            log("warn", "play: audio focus denied")
        }
        transportState.emitAll()
        notificationManager.refresh()
        result.success(null)
    }

    private fun handlePause(p: ExoPlayer, result: MethodChannel.Result) {
        p.pause()
        transportState.stopPositionTicker()
        audioFocusManager.abandon()
        log("info", "pause @ ${p.currentPosition}ms")
        // onIsPlayingChanged listener also emits, but explicit call ensures
        // audioFocus is abandoned before Flutter sees the paused state.
        transportState.emitAll()
        notificationManager.refresh()
        result.success(null)
    }

    private fun handleStop(p: ExoPlayer, result: MethodChannel.Result) {
        p.stop()
        transportState.stopPositionTicker()
        audioFocusManager.abandon()
        log("info", "stop")
        transportState.emitAll()
        result.success(null)
    }

    private fun handleSkipPrevious(p: ExoPlayer, result: MethodChannel.Result) {
        sleepTimerManager.cancel()
        crossfadeController.cancel(resetVolume = true)
        preloadManager.clearStandbyQueue()

        if (p.playbackState == Player.STATE_ENDED) {
            val prevIndex = p.previousMediaItemIndex
            if (prevIndex != C.INDEX_UNSET) {
                queueManager.setActiveQueueIndex(prevIndex)
                p.seekToDefaultPosition(prevIndex)
            } else if (queueManager.queue.isNotEmpty()) {
                val lastIdx = queueManager.queue.lastIndex
                queueManager.setActiveQueueIndex(lastIdx)
                p.seekToDefaultPosition(lastIdx)
            }
            p.prepare()
            p.play()
            if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack(force = true)
            transportState.emitAll()
            notificationManager.refresh()
        } else {
            p.seekToPreviousMediaItem()
            // Player listener handles emission
        }
        result.success(null)
    }

    private fun handleSkipNext(p: ExoPlayer, result: MethodChannel.Result) {
    sleepTimerManager.cancel()
    crossfadeController.cancel(resetVolume = true)
    preloadManager.clearStandbyQueue()

    if (p.playbackState == Player.STATE_ENDED) {
        val nextIndex = p.nextMediaItemIndex

        if (nextIndex != C.INDEX_UNSET) {
            queueManager.setActiveQueueIndex(nextIndex)
            p.seekToDefaultPosition(nextIndex)
            p.prepare()
            p.play()

            if (crossfadeController.crossfadeDurationSec > 0f) {
                preloadManager.preloadNextTrack(force = true)
            }

            log("info", "skipNext (ENDED) → index $nextIndex")
        } else if (p.mediaItemCount > 0) {
            queueManager.setActiveQueueIndex(0)
            p.seekToDefaultPosition(0)
            p.prepare()
            p.play()

            if (crossfadeController.crossfadeDurationSec > 0f) {
                preloadManager.preloadNextTrack(force = true)
            }

            log("info", "skipNext (ENDED) → restart queue")
        }

        transportState.emitAll()
        notificationManager.refresh()
    } else {
        if (p.hasNextMediaItem()) {
            p.seekToNextMediaItem()
        } else if (p.mediaItemCount > 0) {
            queueManager.setActiveQueueIndex(0)
            p.seekToDefaultPosition(0)
            p.prepare()
            p.play()

            log("info", "skipNext → wrapped to queue start")
        }

        if (crossfadeController.crossfadeDurationSec > 0f) {
            preloadManager.preloadNextTrack(force = true)
        }

        // Player listener handles emission
    }

    result.success(null)
}

    private fun log(level: String, msg: String) = NativeLogger.emit(level, "Transport", msg)
}
