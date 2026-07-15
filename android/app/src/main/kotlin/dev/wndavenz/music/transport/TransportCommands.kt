package dev.wndavenz.music.transport

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import dev.wndavenz.music.audio_focus.AudioFocusManager
import dev.wndavenz.music.audio_offload.AudioOffloadManager
import dev.wndavenz.music.crossfade.CrossfadeController
import dev.wndavenz.music.crossfade.PreloadManager
import dev.wndavenz.music.effects.AudioEffectsManager
import dev.wndavenz.music.events.EventEmitter
import dev.wndavenz.music.events.NativeLogger
import dev.wndavenz.music.notification.PlaybackNotificationManager
import dev.wndavenz.music.queue.QueueManager
import dev.wndavenz.music.queue.QueueSync
import dev.wndavenz.music.sleep_timer.SleepTimerManager
import dev.wndavenz.music.transport.PlayPauseFadeController
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
    private val offloadManager: AudioOffloadManager,
    /**
     * M4 — Applied to ALL live ExoPlayer instances (primary + secondary) whenever
     * the skip-silence setting changes, so both players in a crossfade behave identically.
     */
    private val applySkipSilence: (Boolean) -> Unit = {},
    /**
     * M5 — Called when the output mode changes (0=Auto/AAudio, 1=OpenSL ES, 2=Hi-Res).
     * The service uses this to update its hiResModeEnabled flag so the next player
     * created by createConfiguredPlayer() uses the appropriate LoadControl parameters.
     */
    private val onOutputModeChanged: (Int) -> Unit = {},
    /**
     * Item 8 — Called when the user changes the stereo widening setting.
     * Delegates to StereoWidthManager which updates all live ChannelMixingAudioProcessor
     * instances atomically, so both active and standby players (during crossfade) are
     * updated simultaneously without a race condition.
     */
    private val onStereoWideningChanged: (Boolean, Float) -> Unit = { _, _ -> },
    /**
     * Item 6 — Returns a snapshot of PlaybackStats for the active player,
     * or null when no session is in progress.
     */
    private val getPlaybackStats: () -> Map<String, Any>? = { null },
    /**
     * Play/pause volume fade — a thin, single-purpose animator that fades in
     * on play() and fades out before pause(). It never runs while
     * crossfadeController.crossfadeInProgress is true (see PlayPauseFadeController
     * doc for the full conflict-prevention argument), so it can never write
     * player.volume at the same time as the crossfade equal-power fade.
     */
    private val playPauseFadeController: PlayPauseFadeController,
    /**
     * Bit-Perfect Mode: switches playback onto/off the dedicated
     * processing-free ExoPlayer in Media3PlaybackService. Wired to the
     * existing Dart bitPerfectMode toggle — no new UI is involved.
     */
    private val setBitPerfectMode: (Boolean) -> Unit = {},
    /**
     * Playback speed + pitch shift — delegates to StretchManager, which
     * updates every live SignalsmithStretchAudioProcessor instance (primary
     * + secondary/crossfade) atomically. Replaces the old PlaybackParameters-
     * based approach (which drove ExoPlayer's built-in Sonic processor).
     */
    private val onSpeedChanged: (Float) -> Unit = {},
    private val onPitchSemitonesChanged: (Float) -> Unit = {},
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
            "setBitPerfectMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                setBitPerfectMode(enabled)
                log("info", "setBitPerfectMode: $enabled")
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
                // Speed is now realised by SignalsmithStretchAudioProcessor
                // (see StretchManager), not ExoPlayer's PlaybackParameters/Sonic —
                // Signalsmith Stretch stays clean far outside 1.0x where Sonic
                // gets robotic. PlaybackParameters.speed is deliberately left at
                // its ExoPlayer default (1.0) so Sonic's own speed handling
                // never doubles up with Stretch's.
                val rawSpeed = call.argument<Number>("speed")?.toFloat() ?: 1f
                val speed = rawSpeed.coerceIn(0.25f, 4f)
                NativeLogger.emit("info", "Stretch", "[Stretch] Flutter setSpeed command raw=$rawSpeed clamped=$speed")
                onSpeedChanged(speed)
                result.success(null)
            }

            "setPitch" -> {
                // Dart sends a pitch FACTOR (0.5x–2x, matching the old
                // PlaybackParameters.pitch semantics) — convert to semitones
                // for Signalsmith Stretch's setTransposeSemitones().
                val rawPitch = call.argument<Number>("pitch")?.toFloat() ?: 1f
                val pitchFactor = rawPitch.coerceIn(0.5f, 2f)
                val semitones = 12f * (kotlin.math.ln(pitchFactor.toDouble()) / kotlin.math.ln(2.0)).toFloat()
                NativeLogger.emit(
                    "info", "Stretch",
                    "[Stretch] Flutter setPitch command raw=$rawPitch clamped=$pitchFactor semitones=$semitones",
                )
                onPitchSemitonesChanged(semitones)
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

            // ── Skip silence (Item 1) ─────────────────────────────────────────

            "setSkipSilence" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                applySkipSilence(enabled)
                log("info", "setSkipSilence: $enabled")
                result.success(null)
            }

            // ── Stereo widening (Item 8) ──────────────────────────────────────

            /**
             * Enables/disables software stereo widening via ChannelMixingAudioProcessor.
             *
             * [strength] range: 0.0 (no effect) … 1.0 (maximum, ~25 % extra separation).
             * Applied atomically to all live ExoPlayer instances via StereoWidthManager;
             * no race between active and standby players during crossfade.
             *
             * Compatible with all software effects (EQ, BassBoost, etc.) — runs in
             * ExoPlayer pipeline, not AudioFlinger effects chain.
             * Incompatible with tunneling (audio bypasses the pipeline entirely).
             */
            "setStereoWidening" -> {
                val enabled  = call.argument<Boolean>("enabled") ?: false
                val strength = call.argument<Number>("strength")?.toFloat() ?: 0.5f
                onStereoWideningChanged(enabled, strength.coerceIn(0f, 1f))
                log("info", "setStereoWidening: enabled=$enabled strength=$strength")
                result.success(null)
            }

            // ── Audio Offload ─────────────────────────────────────────────────

            "setOffloadSchedulingEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                offloadManager.setForceDisabled(!enabled)
                log("verbose", "setOffloadSchedulingEnabled: $enabled")
                result.success(null)
            }

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
                // Update offload scheduling eligibility whenever crossfade duration changes.
                // Scheduling is disabled when crossfade > 0 (standby player may overlap at any
                // time) and re-enabled when crossfade = 0 (single-player, OS may grant offload).
                offloadManager.onCrossfadeDurationChanged(sec)
                log("verbose", "setCrossfadeDuration: ${sec}s")
                result.success(null)
            }

            // ── Query ─────────────────────────────────────────────────────────

            /**
             * Returns the currently active audio format reported by Media3's track
             * selection.  Reads ExoPlayer.currentTracks at call-time; returns null
             * when no audio track is selected (e.g. player is idle).
             *
             * Fields (all 0 / empty-string when not available):
             *   sampleRate   — Hz (e.g. 44100, 48000, 96000)
             *   channelCount — 1 = mono, 2 = stereo, 6 = 5.1, etc.
             *   bitrate      — bits/second (0 for lossless like FLAC)
             *   mimeType     — MIME type string (e.g. "audio/flac", "audio/mpeg")
             *   codecs       — codec-specific string from container (may be empty)
             *   pcmEncoding  — AudioFormat.ENCODING_* int (0 when not PCM)
             */
            "getAudioFormat" -> {
                val p2 = getPlayer()
                if (p2 == null) { result.success(null); return }
                val audioGroup = p2.currentTracks.groups.firstOrNull {
                    it.type == C.TRACK_TYPE_AUDIO && it.isSelected
                }
                val fmt = audioGroup?.let { g ->
                    (0 until g.length)
                        .firstOrNull { i -> g.isTrackSelected(i) }
                        ?.let { i -> g.getTrackFormat(i) }
                }
                result.success(
                    if (fmt != null) mapOf(
                        "sampleRate"   to (fmt.sampleRate.takeIf   { it != Format.NO_VALUE } ?: 0),
                        "channelCount" to (fmt.channelCount.takeIf { it != Format.NO_VALUE } ?: 0),
                        "bitrate"      to (fmt.bitrate.takeIf      { it != Format.NO_VALUE } ?: 0),
                        "mimeType"     to (fmt.sampleMimeType ?: ""),
                        "codecs"       to (fmt.codecs        ?: ""),
                        "pcmEncoding"  to (fmt.pcmEncoding.takeIf  { it != Format.NO_VALUE } ?: 0),
                    ) else null
                )
            }

            "getEffectSupport" -> result.success(effectsManager.effectSupportMap())

            "getEqualizerParameters" -> result.success(effectsManager.equalizerParameters())

            // ── Playback stats (Item 6) ───────────────────────────────────────

            /**
             * Returns accumulated PlaybackStats for the current active-player session.
             * Fields: totalPlayTimeMs, totalBufferingTimeMs, totalRebufferCount,
             *         totalErrorCount.
             * Returns null when no session is in progress.
             */
            "getPlaybackStats" -> {
                result.success(getPlaybackStats())
            }

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

                // Audio format from active track selection (null-safe; fields are
                // 0 / empty-string when the player is idle or no track is selected).
                val audioGroup = p.currentTracks.groups.firstOrNull {
                    it.type == C.TRACK_TYPE_AUDIO && it.isSelected
                }
                val fmt = audioGroup?.let { g ->
                    (0 until g.length)
                        .firstOrNull { i -> g.isTrackSelected(i) }
                        ?.let { i -> g.getTrackFormat(i) }
                }

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
                    // Audio format fields (Media3 1.10.1 — Format.NO_VALUE = -1 sentinel)
                    "audioSampleRate"   to (fmt?.sampleRate?.takeIf   { it != Format.NO_VALUE } ?: 0),
                    "audioChannelCount" to (fmt?.channelCount?.takeIf { it != Format.NO_VALUE } ?: 0),
                    "audioBitrate"      to (fmt?.bitrate?.takeIf      { it != Format.NO_VALUE } ?: 0),
                    "audioMimeType"     to (fmt?.sampleMimeType ?: ""),
                    "audioCodecs"       to (fmt?.codecs        ?: ""),
                    "audioPcmEncoding"  to (fmt?.pcmEncoding?.takeIf  { it != Format.NO_VALUE } ?: 0),
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
            // Snap volume to 0 (unless a crossfade already owns this player's
            // volume) BEFORE play() so there is no audible pop, then ramp up.
            playPauseFadeController.fadeInOnPlay(p)
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
        // Fade out, then perform the actual pause + bookkeeping only once the
        // fade completes (or immediately, unchanged, if a crossfade is active
        // or fade duration resolves to 0 — see PlayPauseFadeController).
        playPauseFadeController.fadeOutThenPause(p) {
            p.pause()
            transportState.stopPositionTicker()
            audioFocusManager.abandon()
            log("info", "pause @ ${p.currentPosition}ms")
            // onIsPlayingChanged listener also emits, but explicit call ensures
            // audioFocus is abandoned before Flutter sees the paused state.
            transportState.emitAll()
            notificationManager.refresh()
        }
        result.success(null)
    }

    private fun handleStop(p: ExoPlayer, result: MethodChannel.Result) {
        // Stop is not a user "pause" gesture (used for setQueue/teardown paths
        // elsewhere) — no fade here, matches prior instant behavior. Cancel any
        // in-flight play/pause fade so it can't keep writing to a stopped player.
        playPauseFadeController.cancel(p, resetVolume = true)
        p.stop()
        transportState.stopPositionTicker()
        audioFocusManager.abandon()
        log("info", "stop")
        transportState.emitAll()
        result.success(null)
    }

    private fun handleSkipPrevious(p: ExoPlayer, result: MethodChannel.Result) {
        sleepTimerManager.cancel()

        // Capture before cancel() + clearStandbyQueue() erase this information.
        val wasCrossfading = crossfadeController.crossfadeInProgress
        val promotedIndex  = preloadManager.preloadedQueueIndex

        crossfadeController.cancel(resetVolume = true)
        preloadManager.clearStandbyQueue()

        // If a crossfade was in flight, the active player was already promoted to
        // the standby (1 item) before the fade completed.  cancel() stops the fade
        // but does NOT call rebuildPlayerQueue(), so the player still has only 1
        // MediaItem.  With REPEAT_MODE_ALL, seekToPreviousMediaItem() / previousMediaItemIndex
        // on a 1-item player wraps to the same item — locking playback on one track.
        // Fix: restore the full queue and the correct activeQueueIndex before seeking.
        if (wasCrossfading &&
            promotedIndex in queueManager.queue.indices &&
            p.mediaItemCount < queueManager.queue.size) {
            queueManager.setActiveQueueIndex(promotedIndex)
            queueManager.rebuildPlayerQueue()
        }

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

        // Capture before cancel() + clearStandbyQueue() erase this information.
        val wasCrossfading = crossfadeController.crossfadeInProgress
        val promotedIndex  = preloadManager.preloadedQueueIndex

        crossfadeController.cancel(resetVolume = true)
        preloadManager.clearStandbyQueue()

        // Same partial-queue fix as handleSkipPrevious — see that function for the
        // full explanation.  Without this, skipNext on a 1-item promoted player with
        // REPEAT_MODE_ALL wraps to the same item and locks playback on one track.
        if (wasCrossfading &&
            promotedIndex in queueManager.queue.indices &&
            p.mediaItemCount < queueManager.queue.size) {
            queueManager.setActiveQueueIndex(promotedIndex)
            queueManager.rebuildPlayerQueue()
        }

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

                log("info", "skipNext → wrapped to queue start")
            }

            if (crossfadeController.crossfadeDurationSec > 0f) {
                preloadManager.preloadNextTrack(force = true)
            }

            // Player listener handles emission
        }

        result.success(null)
    }
    // ── Native transport wrappers ─────────────────────────────────────────────
    // Called from MediaSession.Callback and handleNotificationAction so that both
    // paths share identical logic (audio focus, crossfade, etc.).

    private val noopResult = object : MethodChannel.Result {
        override fun success(result: Any?) {}
        override fun error(code: String, msg: String?, details: Any?) {}
        override fun notImplemented() {}
    }

    fun playNative()     { getPlayer()?.let { handlePlay(it, noopResult) } }
    fun pauseNative()    { getPlayer()?.let { handlePause(it, noopResult) } }
    fun stopNative()     { getPlayer()?.let { handleStop(it, noopResult) } }
    fun skipNextNative() { getPlayer()?.let { handleSkipNext(it, noopResult) } }
    fun skipPrevNative() { getPlayer()?.let { handleSkipPrevious(it, noopResult) } }

    fun seekNative(posMs: Long) {
        val p = getPlayer() ?: return
        p.seekTo(posMs)
        log("verbose", "seekNative → ${posMs}ms")
    }

    /**
     * MED-01/CRIT-01 support: jump to a specific queue index. Called from
     * [ActivePlayerProxy.seekTo] when an external controller (Android Auto,
     * AVRCP media browser) sends seekTo(mediaItemIndex, positionMs) with a
     * non-INDEX_UNSET mediaItemIndex. Mirrors the "setTrack" MethodChannel branch.
     */
    fun setTrackNative(index: Int) {
        sleepTimerManager.cancel()
        crossfadeController.cancel(resetVolume = true)
        preloadManager.clearStandbyQueue()
        queueManager.setTrack(index)
        if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack()
        queueSync.save()
        log("info", "setTrack(native): [$index]")
    }

    private fun log(level: String, msg: String) = NativeLogger.emit(level, "Transport", msg)
}
