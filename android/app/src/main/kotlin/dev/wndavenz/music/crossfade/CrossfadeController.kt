package dev.wndavenz.music.crossfade

import android.os.Handler
import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import dev.wndavenz.music.automix.AutomixGainEnvelope
import dev.wndavenz.music.automix.AutomixPhaseLock
import dev.wndavenz.music.automix.AutomixTransitionPolicy
import dev.wndavenz.music.diagnostics.CrossfadeTimelineLogger
import dev.wndavenz.music.events.NativeLogger
import dev.wndavenz.music.effects.AutomixLiveBeatState
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.cos
import kotlin.math.sin

/**
 * TRUE CROSSFADE ENGINE
 *
 * Two-phase architecture:
 *
 *   Phase 1 — PRE-WARM  (PREWARM_LEAD_MS before the crossfade point)
 *     PreloadManager.prewarmStandby() starts the standby player at volume=0.
 *     Its AudioTrack and Android AudioFlinger mixing slot are fully active so there is
 *     zero startup latency when the actual fade begins.
 *
 *   Phase 2 — EQUAL-POWER FADE  (at the planned transition point)
 *     Standard fades target the outgoing track end; AutoMix may start 30–65 s
 *     early when an incoming drop and both beat grids are confidently detected.
 *     The overlap itself remains the short, separately planned fade duration.
 *     Both players output audio simultaneously. Volumes follow:
 *       old → cos(t × π/2) × targetVol        (perceptually constant power)
 *       new → sin(t × π/2) × targetVol
 *     At t=0:   old=target, new=0
 *     At t=0.5: old=0.707×target, new=0.707×target  ← no loudness dip / pump
 *     At t=1:   old=0,      new=target
 *
 * Bug fixes carried forward:
 *   CE-04: cancel(resetVolume) stops the old player (promotionOwner) AND restores the new
 *          player's volume — not just one or the other.
 *   QS-02/03/CE-03: onCrossfadeComplete callback triggers queue rebuild on promoted player.
 *   CE-02: explicit READY-state check with diagnostic log before promotion.
 *
 * MIUI 12 / Android 11 notes:
 *   - The standby player is created with setHandleAudioBecomingNoisy(false) in
 *     Media3PlaybackService.createConfiguredPlayer() so only the active player auto-responds
 *     to headphone unplug.
 *   - Audio focus is held by the service (not per-player) so both players share the same
 *     focus grant during the overlap window; we never request a second focus during a fade.
 */
@UnstableApi
class CrossfadeController(
    private val handler: Handler,
    private val getActivePlayer:      () -> ExoPlayer?,
    private val getStandbyPlayer:     () -> ExoPlayer?,
    private val setActivePlayer:      (ExoPlayer) -> Unit,
    private val switchSessionPlayer:  (ExoPlayer) -> Unit,
    private val preloadManager:       PreloadManager,
    private val getVolumeBeforeDuck:  () -> Float,
     private val getEffectiveVolume:   () -> Float = getVolumeBeforeDuck,
    private val hasAudioFocus:        () -> Boolean,
    private val requestAudioFocus:    () -> Boolean,
    private val getQueue:             () -> List<Map<String, Any?>>,
    private val getActiveQueueIndex:  () -> Int,
    private val setActiveQueueIndex:  (Int) -> Unit,
    // K1 fix: restores the promoted player's one-item timeline after a
    // mid-fade cancel (headphones unplugged / audio focus lost). Wired to
    // QueueManager.rebuildPlayerQueue() in Media3PlaybackService.
    private val rebuildPromotedQueue: () -> Unit = {},
    private val onCrossfadeComplete:  () -> Unit,
    private val emitAll:              () -> Unit,
    private val refreshNotification:  () -> Unit,
    // Called at the very start of beginCrossfade() so offload scheduling can be
    // disabled before the first 16 ms Handler tick fires.
    private val onCrossfadeStarting:  () -> Unit = {},
    // Patch B (RC-3 fix): called during Phase 1 prewarm to pre-load the next track's
    // artwork into the notification bitmap cache.  The 1500 ms prewarm window is otherwise
    // idle for artwork, so this moves the load earlier and eliminates the blank-artwork
    // window at crossfade start.  Nullable to keep the parameter optional/backward-compat.
    private val prewarmNotificationArtwork: ((songId: Int, artUri: String?) -> Unit)? = null,
    // F1 (sleep timer): while the end-of-song sleep timer is armed, crossfade must not
    // start — the current track plays out to its natural end so the existing
    // STATE_ENDED / transition trigger can fire. See maybeCrossfadeOut().
    private val isEndOfSongSleepTimerActive: () -> Boolean = { false },
    // BP-06: Bit-Perfect Mode and the dual-player crossfade are mutually exclusive.
    // Dart already forces the crossfade duration to 0 on mode entry; this native
    // guard is defence in depth so a stale crossfade setting can never start a fade
    // on the clean player (or reuse its standby slot) while the mode is active.
    private val isBitPerfectModeActive: () -> Boolean = { false },
    // AutoMix hints enable conservative beat-grid scheduling and bass swap.
    private val isAutomixTransitionEnabled: () -> Boolean = { false },
    private val getAutoMixBpmForPlayer: (ExoPlayer) -> Float? = { null },
    private val getAutoMixLiveBeatStateForPlayer: (ExoPlayer) -> AutomixLiveBeatState? = { null },
    private val getAutoMixBeatOffsetMsForPlayer: (ExoPlayer) -> Long? = { null },
    private val getAutoMixDownbeatOffsetMsForPlayer: (ExoPlayer) -> Long? = { null },
    private val getMediaPlaybackSpeedForPlayer: (ExoPlayer) -> Float = { it.playbackParameters.speed },
    private val monotonicClockMs: () -> Long = { SystemClock.uptimeMillis() },
    private val setAutoMixBassGain: (ExoPlayer, Float) -> Unit = { _, _ -> },
    private val setAutoMixMidGain: (ExoPlayer, Float) -> Unit = { _, _ -> },
    private val getAutoMixBassOverlapGainsForIncoming: (ExoPlayer) -> Pair<Float, Float>? = { null },
    private val getAutoMixMidOverlapGainsForIncoming: (ExoPlayer) -> Pair<Float, Float>? = { null },
    private val getAutoMixHighOverlapGainsForIncoming: (ExoPlayer) -> Pair<Float, Float>? = { null },
    // Per-transition shaping from the offline planner, keyed by the INCOMING
    // track: its own fade length, the equal-power transfer curve, and the level
    // match between the two decks. All default to the pre-AutoMix behaviour.
    private val getAutoMixFadeSecondsForPlayer: (ExoPlayer) -> Float? = { null },
    // Absolute start position on the OUTGOING track's media timeline. This is
    // distinct from fade length and is only set for confident early handovers.
    private val getAutoMixTransitionStartMsForPlayer: (ExoPlayer) -> Long? = { null },
    private val getAutoMixCurveForPlayer: (ExoPlayer) -> Float = { 1f },
    private val getAutoMixTrimForPlayer: (ExoPlayer) -> Float = { 1f },
    private val getAutoMixOutgoingTrimForPlayer: (ExoPlayer) -> Float = { 1f },
    // Beat-phase resync: re-times ONLY the incoming deck while the two decks
    // overlap. The factor is relative (1.0 = leave the planner's multiplier as
    // it is), so a correction can never accumulate across fades.
    private val setAutoMixTempoNudge: (ExoPlayer, Float) -> Unit = { _, _ -> },
    // Gentle high-band filter-out on the outgoing deck's tail: 1.0 = transparent.
    private val setAutoMixTailFilter: (ExoPlayer, Float) -> Unit = { _, _ -> },
    // Native per-sample equal-power envelope; player.volume remains the master
    // volume control. False keeps the existing Kotlin volume-ramp fallback.
    private val setAutoMixCrossfadeGains:
        (ExoPlayer, ExoPlayer, Float, Float, Float, Float) -> Boolean =
        { _, _, _, _, _, _ -> false },
    private val setAutoMixFadeGain: (ExoPlayer, Float) -> Unit = { _, _ -> },
    private val onCrossfadeCancelled: () -> Unit = {},
) {
    companion object {
        /** How far before the crossfade point we start the standby audio pipeline. */
        const val PREWARM_LEAD_MS = 1500L

        /** Fade animation step — ~62 fps for smooth perceived volume curve. */
        const val FADE_STEP_MS = 16L

        /** Minimum actual fade duration regardless of track-end proximity. */
        const val MIN_FADE_MS = AutomixTransitionPolicy.MIN_FADE_MS

        /** Bounds for a planner-approved early handover, relative to outgoing EOF. */
        const val EARLY_TRANSITION_MIN_LEAD_MS =
            AutomixTransitionPolicy.EARLY_TRANSITION_MIN_LEAD_MS
        const val EARLY_TRANSITION_MAX_LEAD_MS =
            AutomixTransitionPolicy.EARLY_TRANSITION_MAX_LEAD_MS

        /**
         * How often an overlap re-measures the two beat grids and re-times the
         * incoming deck. ~64 ms is frequent enough to stay locked while not
         * fighting the 16 ms volume ramp.
         */
        const val PHASE_LOCK_INTERVAL_MS = 64L
        const val LIVE_BEAT_MIN_CONFIDENCE = 0.30f

        /** Most high band the outgoing tail filter may remove (-12 dB). */
        const val MAX_TAIL_FILTER = 0.75f
    }

    var crossfadeDurationSec: Float = 0f
        private set
    var crossfadeInProgress: Boolean = false
        private set
    var promotionTriggered: Boolean = false
        private set
    var promotionOwner: ExoPlayer? = null
        private set

    private var prewarmTriggered: Boolean = false
    private var crossfadeFadeRunnable: Runnable? = null
    private var beatAlignedStartRunnable: Runnable? = null

    // Captured once per fade (read again on every 16 ms tick).
    private var fadeGamma: Float = 1f
    private var outgoingTrim: Float = 1f
    private var incomingTrim: Float = 1f

    // ── Public API ────────────────────────────────────────────────────────────

    fun setDuration(sec: Float) {
        crossfadeDurationSec = sec
    }

    /**
     * Called every 200 ms from the position ticker.
     *
     * Drives both phases:
     *   • enters pre-warm zone → warms up standby pipeline
     *   • enters fade zone     → begins equal-power crossfade
     */
    fun maybeCrossfadeOut() {
        if (crossfadeDurationSec <= 0f || promotionTriggered || crossfadeInProgress) return
        // BP-06: never start a crossfade while Bit-Perfect Mode is active.
        if (isBitPerfectModeActive()) return
        // F1 (sleep timer): never start a crossfade while the end-of-song timer is armed.
        // During a crossfade the promoted standby's transition is PLAYLIST_CHANGED (not
        // AUTO) and the old player's STATE_ENDED is dropped by the isActiveEvent() guard,
        // so the end-of-song trigger would only fire at the end of the LAST queue item
        // (or never, with repeat-all). Letting the track play out naturally preserves the
        // "stop at this song's boundary" semantics.
        if (isEndOfSongSleepTimerActive()) return
        val p = getActivePlayer() ?: return

        val dur = p.duration
        if (dur <= 0L || dur == C.TIME_UNSET) return
        if (!p.hasNextMediaItem() && p.repeatMode == Player.REPEAT_MODE_OFF) return
        if (p.repeatMode == Player.REPEAT_MODE_ONE) return  // let ExoPlayer loop natively

        // Ensure next track is ready in standby
        preloadManager.preloadNextTrack()
        val standby = getStandbyPlayer() ?: return
        if (standby.mediaItemCount == 0) return

        // AutoMix may shorten/lengthen this particular blend (dense outro →
        // quicker hand-over, sparse outro → longer one); otherwise the user's
        // crossfade duration applies unchanged.
        val automixFadeSec = if (isAutomixTransitionEnabled()) {
            getStandbyPlayer()?.let { getAutoMixFadeSecondsForPlayer(it) }
        } else null
        val crossMs = ((automixFadeSec ?: crossfadeDurationSec) * 1000f)
            .toLong()
            .coerceAtLeast(MIN_FADE_MS)
        val currentPosition = p.currentPosition.coerceAtLeast(0L)
        val remaining = (dur - currentPosition).coerceAtLeast(0L)
        // Only honour a planner cue within the explicitly supported early-exit
        // window. A stale/malformed target safely falls back to the standard
        // crossfade point near EOF.
        val requestedStartMs = if (isAutomixTransitionEnabled()) {
            getAutoMixTransitionStartMsForPlayer(standby)
        } else null
        val earlyStartMs = requestedStartMs?.takeIf {
            AutomixTransitionPolicy.isValidEarlyHandover(it, dur, crossMs)
        }
        val isEarlyTransition = earlyStartMs != null
        val idealStart = (earlyStartMs ?: (dur - crossMs)).coerceAtLeast(0L)

        // BPM + phase are an offline onset-grid estimate, not a guaranteed
        // musical downbeat. If either is uncertain, retain time-based crossfade.
        val beatMs = if (isAutomixTransitionEnabled()) {
            getAutoMixBpmForPlayer(p)?.takeIf { it.isFinite() && it in 50f..250f }
                ?.let { 60_000.0 / it }
        } else null
        val beatOffset = if (beatMs != null) {
            getAutoMixBeatOffsetMsForPlayer(p)?.toDouble()
        } else null
        val beatAlignedStart = if (beatMs != null && beatOffset != null && beatMs > 0.0) {
            val phase = ((beatOffset % beatMs) + beatMs) % beatMs
            // Start on the beat at/before the requested fade start. Starting on
            // the next beat would leave less than the configured fade duration
            // before EOS, even though the fade itself still ran for crossMs.
            val previousBeat = phase + floor((idealStart - phase) / beatMs) * beatMs
            val aligned = if (previousBeat >= 0.0 &&
                idealStart - previousBeat <= beatMs * 1.05
            ) previousBeat.toLong() else idealStart
            aligned.coerceIn(0L, (dur - 1L).coerceAtLeast(0L))
        } else {
            idealStart
        }
        // For the normal near-end path, let the fade reach the outgoing
        // boundary; beat alignment may extend it by less than one beat. Early
        // handovers must keep crossMs as the overlap, not fade for all remaining
        // media time after the early start.
        val fadeLeadMs = (dur - beatAlignedStart).coerceAtLeast(MIN_FADE_MS)

        // ── Phase 1: pre-warm ─────────────────────────────────────────────────
        val prewarmWindowStart = (beatAlignedStart - PREWARM_LEAD_MS).coerceAtLeast(0L)
        if (!prewarmTriggered && currentPosition >= prewarmWindowStart) {
            prewarmTriggered = true
            preloadManager.prewarmStandby()
            log(
                "Pre-warm triggered @ position=${currentPosition}ms " +
                    "(start=${beatAlignedStart}ms early=${isEarlyTransition})"
            )

            // Patch B (RC-3 fix): pre-load notification artwork during the idle prewarm
            // window so bitmapCache already has the next track's artwork by the time
            // beginCrossfade() calls refreshNotification().  artworkExecutor is otherwise
            // idle here; starting the load ~1500 ms early eliminates the blank-artwork
            // window that previously lasted 150–900 ms into the fade.
            if (prewarmNotificationArtwork != null) {
                val nextTrack = getQueue().getOrNull(preloadManager.preloadedQueueIndex)
                if (nextTrack != null) {
                    val songId = (nextTrack["id"] as? Number)?.toInt() ?: 0
                    val artUri = nextTrack["artworkUri"] as? String
                    prewarmNotificationArtwork.invoke(songId, artUri)
                    log("prewarmNotificationArtwork triggered for [${ preloadManager.preloadedQueueIndex }] " +
                        "'${nextTrack["title"]}' artUri=${artUri != null}")
                }
            }
        }

        // ── Phase 2: beat-grid-aware or ordinary crossfade ────────────────────
        if (beatMs != null && beatOffset != null && currentPosition < beatAlignedStart) {
            // Use a Handler to reduce timing jitter after the standby is prewarmed.
            // Convert media-time distance to wall time when playback speed is not 1x.
            if (currentPosition >= prewarmWindowStart && beatAlignedStartRunnable == null) {
                val expectedItemId = p.currentMediaItem?.mediaId
                val speed = AutomixTransitionPolicy.normalizedPlaybackSpeed(
                    getMediaPlaybackSpeedForPlayer(p),
                )
                val delay = ((beatAlignedStart - currentPosition) / speed)
                    .toLong().coerceAtLeast(1L)
                val runnable = Runnable {
                    beatAlignedStartRunnable = null
                    if (getActivePlayer() !== p || p.currentMediaItem?.mediaId != expectedItemId ||
                        crossfadeInProgress || promotionTriggered || isBitPerfectModeActive() ||
                        isEndOfSongSleepTimerActive()
                    ) return@Runnable
                    val nowPosition = p.currentPosition.coerceAtLeast(0L)
                    if (nowPosition < beatAlignedStart) {
                        // Position can lag the wall-clock delay (buffering/speed
                        // changes). The next 200 ms position tick will re-arm it.
                        return@Runnable
                    }
                    val nowRemaining = (p.duration - nowPosition).coerceAtLeast(0L)
                    val requestedFadeMs = if (isEarlyTransition) {
                        crossMs
                    } else {
                        (dur - beatAlignedStart).coerceAtLeast(MIN_FADE_MS)
                    }
                    val fade = minOf(requestedFadeMs, nowRemaining).coerceAtLeast(MIN_FADE_MS)
                    beginCrossfade(fade)
                }
                beatAlignedStartRunnable = runnable
                handler.postDelayed(runnable, delay)
            }
        } else if (remaining > 0L && currentPosition >= beatAlignedStart) {
            beatAlignedStartRunnable?.let { handler.removeCallbacks(it) }
            beatAlignedStartRunnable = null
            val requestedFadeMs = if (isEarlyTransition) {
                crossMs
            } else if (beatMs != null && beatOffset != null) {
                fadeLeadMs
            } else {
                crossMs
            }
            val actualFadeMs = minOf(requestedFadeMs, remaining).coerceAtLeast(MIN_FADE_MS)
            log(
                "Crossfade trigger: remaining=${remaining}ms fade=${actualFadeMs}ms " +
                    "start=${beatAlignedStart}ms early=${isEarlyTransition} " +
                    "beatAligned=${beatMs != null && beatOffset != null}"
            )
            beginCrossfade(actualFadeMs)
        }
    }

    /**
     * Cancel any pending or in-progress crossfade.
     *
     * CE-04 fix: stops the old player (promotionOwner) AND restores the new player's volume.
     */
    fun cancel(resetVolume: Boolean) {
        crossfadeFadeRunnable?.let { handler.removeCallbacks(it) }
        crossfadeFadeRunnable = null
        beatAlignedStartRunnable?.let { handler.removeCallbacks(it) }
        beatAlignedStartRunnable = null
        getActivePlayer()?.let {
            setAutoMixBassGain(it, 1f)
            setAutoMixMidGain(it, 1f)
            setAutoMixTempoNudge(it, 1f)
            setAutoMixTailFilter(it, 1f)
            setAutoMixFadeGain(it, 1f)
        }
        promotionOwner?.let {
            setAutoMixBassGain(it, 1f)
            setAutoMixMidGain(it, 1f)
            setAutoMixTailFilter(it, 1f)
            setAutoMixFadeGain(it, 1f)
        }

        // K1 fix: capture the mid-fade state BEFORE clearing the flags below. A
        // promoted standby owns a one-item timeline until the fade completes;
        // cancelling mid-fade (headphones unplugged, audio focus lost) would
        // otherwise leave that one-item timeline as the active queue.
        val wasMidFade = crossfadeInProgress

        // Stop the old player if we're mid-fade
        if (wasMidFade) {
            CrossfadeTimelineLogger.stamp(
                "CrossfadeController.cancel(): mid-fade cancel resetVolume=$resetVolume",
                getActivePlayer())
            promotionOwner?.let { old ->
                try { old.pause()           } catch (_: Exception) {}
                try { old.stop()            } catch (_: Exception) {}
                try { old.clearMediaItems() } catch (_: Exception) {}
            }
            // Reset the diagnostic epoch so a subsequent crossfade starts fresh.
            CrossfadeTimelineLogger.end("cancel() — crossfade aborted externally")
        }

        crossfadeInProgress  = false
        promotionTriggered   = false
        prewarmTriggered     = false
        promotionOwner       = null

        if (resetVolume) getActivePlayer()?.volume = getVolumeBeforeDuck().coerceIn(0f, 1f)

        // K1 fix: rebuild the authoritative queue on the promoted player after a
        // mid-fade cancel so next/prev navigation never stays locked on a single
        // track. rebuildPlayerQueue() skips when the timeline is already full, so
        // paths that restore explicitly (TransportCommands pause/stop/skip,
        // setQueue, shutdown) are unaffected no-ops.
        if (wasMidFade) rebuildPromotedQueue()
        if (wasMidFade) onCrossfadeCancelled()
    }

    /**
     * Called from onMediaItemTransition when a track changes outside of an active crossfade.
     * Resets promotionTriggered + prewarmTriggered so the next track can trigger a fresh fade.
     */
    fun resetPromotionState() {
        if (!crossfadeInProgress) {
            beatAlignedStartRunnable?.let { handler.removeCallbacks(it) }
            beatAlignedStartRunnable = null
            promotionTriggered = false
            prewarmTriggered = false
        }
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun beginCrossfade(actualFadeMs: Long) {
        if (crossfadeInProgress) return

        val standby   = getStandbyPlayer() ?: return
        val current   = getActivePlayer()  ?: return
        val nextIndex = preloadManager.preloadedQueueIndex
        val queue     = getQueue()

        if (standby === current) return
        if (standby.mediaItemCount == 0 || nextIndex !in queue.indices) return

        // Do not promote either deck or mutate the outgoing queue until audio focus
        // is confirmed. A failed request must leave the current track untouched.
        if (!hasAudioFocus() && !requestAudioFocus()) {
            log("Crossfade deferred: audio focus unavailable; outgoing player remains active")
            return
        }

        // ── Timeline epoch: every subsequent stamp is relative to this point ──
        CrossfadeTimelineLogger.begin(
            "fade=${actualFadeMs}ms  nextIdx=$nextIndex  " +
            "track='${queue.getOrNull(nextIndex)?.get("title") ?: "?"}'"
        )
        CrossfadeTimelineLogger.stampDual("beginCrossfade: ENTER", standby, current)

        // Diagnostic: log if standby isn't READY yet (pre-warm may not have settled)
        when (standby.playbackState) {
            Player.STATE_READY     -> {
                log("Standby is READY — clean crossfade start")
                CrossfadeTimelineLogger.stamp("beginCrossfade: standby READY (good)", standby)
            }
            Player.STATE_BUFFERING -> {
                log("warn: standby still BUFFERING — may have startup gap")
                CrossfadeTimelineLogger.stamp("beginCrossfade: warn standby BUFFERING", standby)
            }
            Player.STATE_IDLE      -> {
                log("warn: standby is IDLE — forcing prepare+play")
                CrossfadeTimelineLogger.stamp("beginCrossfade: warn standby IDLE — calling prepare()", standby)
                standby.prepare()
                CrossfadeTimelineLogger.stamp("beginCrossfade: forced prepare() done", standby)
            }
            else -> {
                log("warn: standby state=${standby.playbackState}")
                CrossfadeTimelineLogger.stamp("beginCrossfade: warn standby state=${standby.playbackState}", standby)
            }
        }

        // AutoMix per-transition shape, captured from the incoming deck's cue.
        fadeGamma = if (isAutomixTransitionEnabled()) {
            getAutoMixCurveForPlayer(standby).coerceIn(0.6f, 1.6f)
        } else 1f
        outgoingTrim = if (isAutomixTransitionEnabled()) {
            getAutoMixOutgoingTrimForPlayer(standby).coerceIn(0f, 1f)
        } else 1f
        incomingTrim = if (isAutomixTransitionEnabled()) {
            getAutoMixTrimForPlayer(standby).coerceIn(0f, 1f)
        } else 1f

        // A deck keeps its tone processor between blends, so every fade starts
        // from a transparent filter state on both decks.
        setAutoMixTailFilter(current, 1f)
        setAutoMixTailFilter(standby, 1f)
        // Keep the master gain envelope on the controller thread for BOTH modes.
        // The two native processors consume PCM on independent audio threads, so
        // their per-sample fade ramps can briefly be out of phase and exceed the
        // combined headroom budget even when each target pair is normalized.
        // The Kotlin ramp computes both deck gains in the same tick and applies
        // one shared headroom scale. Reset stale native envelopes before fading.
        setAutoMixFadeGain(current, 1f)
        setAutoMixFadeGain(standby, 1f)
        val nativeFadeAvailable = false

        // Live BPM estimates may be available even for tracks that the planner
        // deliberately left unmatched. Only use phase lock when the published
        // offline targets say this pair passed tempo matching.
        val phaseLockActive = isAutomixTransitionEnabled() &&
            AutomixTransitionPolicy.isBeatMatchedPair(
                getAutoMixBpmForPlayer(current),
                getAutoMixBpmForPlayer(standby),
            )
        // Empty/same-ID target sets intentionally mean ordinary crossfade; do
        // not apply the default tail filter unless a real transition cue exists.
        val transitionCueAvailable = isAutomixTransitionEnabled() &&
            AutomixTransitionPolicy.hasTransitionCue(getAutoMixFadeSecondsForPlayer(standby))

        crossfadeInProgress = true
        promotionTriggered  = true
        promotionOwner      = current

        // Notify AudioOffloadManager BEFORE the first Handler tick so offload
        // scheduling is disabled before the 16 ms volume-fade runnable starts.
        onCrossfadeStarting()
        // K-02 (historical): an earlier version of setActiveQueueIndex called seekTo() on
        // ExoPlayer which caused a ~200 ms audio cut.  The current implementation is a pure
        // integer assignment in QueueManager with no ExoPlayer side effects, so it is now
        // called immediately after setActivePlayer() — see DP-1 fix below.

        // Isolate the old player to exactly the current item so it cannot
        // auto-advance to any other queue position during the fade.
        //
        // Root-cause of "queue[0] plays for ~1 s during B's fade-in":
        //   beginCrossfade() used to remove only the TAIL (items after A), leaving
        //   prefix items (queue[0]…A-1) intact. If A's track finishes before the
        //   media-timeline-based fade completes, REPEAT_MODE_ALL could wrap the old
        //   player back to index 0 (queue[0]) at an audible fade-out volume.
        //
        // Fix: set REPEAT_MODE_OFF on the old player and also remove the prefix so
        // the old player contains exactly [A]. When A ends the player silently
        // reaches STATE_ENDED regardless of the user's global repeat setting.
        try {
            val ci = current.currentMediaItemIndex
            // Remove tail (items after A)
            if (current.mediaItemCount > ci + 1) {
                CrossfadeTimelineLogger.stamp(
                    "beginCrossfade: old player removeMediaItems tail [${ci+1}..${current.mediaItemCount})", current)
                current.removeMediaItems(ci + 1, current.mediaItemCount)
                CrossfadeTimelineLogger.stamp("beginCrossfade: old player tail removed", current)
            }
            // Remove prefix (items before A) — prevents REPEAT_MODE_ALL from wrapping
            // to queue[0] if A ends before the fade completes.
            if (ci > 0) {
                CrossfadeTimelineLogger.stamp(
                    "beginCrossfade: old player removeMediaItems prefix [0..$ci)", current)
                current.removeMediaItems(0, ci)
                CrossfadeTimelineLogger.stamp("beginCrossfade: old player prefix removed", current)
            }
        } catch (e: Exception) {
            log("beginCrossfade: old player isolation failed: ${e.message}")
        }

        // Promote standby → active BEFORE starting playback so the MediaSession
        // immediately shows the new track in the notification.
        standby.volume = 0f
        CrossfadeTimelineLogger.stamp("beginCrossfade: setActivePlayer(standby)", standby)
        setActivePlayer(standby)
        // DP-1 fix: update activeQueueIndex immediately after promoting standby so that
        // any callbacks fired by prepare()/play() below (onPlaybackStateChanged,
        // onIsPlayingChanged → emitAll) read the correct incoming track index rather than
        // the stale outgoing one.  setActiveQueueIndex is a pure integer assignment with
        // no ExoPlayer side effects (see Media3PlaybackService setActiveQueueIndex lambda).
        setActiveQueueIndex(nextIndex)

        // Belt-and-suspenders: disable repeat on the old player AFTER promotion.
        // Doing this here (after setActivePlayer) ensures the listener's
        // isActiveEvent() guard returns false for the old player, so
        // onRepeatModeChanged does NOT emit REPEAT_MODE_OFF to Flutter UI —
        // the user's global repeat setting remains visually intact.
        try { current.repeatMode = Player.REPEAT_MODE_OFF } catch (_: Exception) {}

        // Switch the MediaSession to the standby player immediately so the
        // notification shows the incoming track.  Crash-safety is guaranteed by
        // ActivePlayerProxy: getCurrentTimeline() and getCurrentPeriodIndex() are
        // overridden (alongside all other state-query methods) to delegate to
        // _current, so PlayerWrapper.createPositionInfo() always reads a
        // self-consistent snapshot from a single player and its period-window
        // consistency check cannot fail.
        CrossfadeTimelineLogger.stamp("beginCrossfade: ActivePlayerProxy.switchTo(standby) START", standby)
        switchSessionPlayer(standby)
        CrossfadeTimelineLogger.stamp("beginCrossfade: ActivePlayerProxy.switchTo(standby) DONE", standby)

        // Audio focus was validated before any queue/player mutation above.
        if (standby.playbackState != Player.STATE_READY) {
            CrossfadeTimelineLogger.stamp("beginCrossfade: standby not READY — calling prepare()", standby)
            standby.prepare()
            CrossfadeTimelineLogger.stamp("beginCrossfade: standby.prepare() DONE", standby)
        }
        CrossfadeTimelineLogger.stamp("beginCrossfade: standby.play() START (focus granted)", standby)
        standby.play()
        CrossfadeTimelineLogger.stamp("beginCrossfade: standby.play() DONE", standby)

        log("Promotion complete → [$nextIndex] '${queue[nextIndex]["title"]}' (fade=${actualFadeMs}ms)")
        emitAll()
        refreshNotification()

        val applyBassSwap = isAutomixTransitionEnabled() &&
            getAutoMixBpmForPlayer(current) != null &&
            getAutoMixBpmForPlayer(standby) != null
        val bassOverlapGains = if (isAutomixTransitionEnabled()) {
            getAutoMixBassOverlapGainsForIncoming(standby)
        } else null
        val midOverlapGains = if (isAutomixTransitionEnabled()) {
            getAutoMixMidOverlapGainsForIncoming(standby)
        } else null
        val highOverlapGains = if (isAutomixTransitionEnabled()) {
            getAutoMixHighOverlapGainsForIncoming(standby)
        } else null
        if (applyBassSwap) {
            setAutoMixBassGain(current, 1f)
            setAutoMixBassGain(standby, 0f)
            log("AutoMix bass swap enabled for confident BPM pair")
        } else {
            setAutoMixBassGain(current, 1f)
            setAutoMixBassGain(standby, 1f)
        }
        beatAlignedStartRunnable?.let { handler.removeCallbacks(it) }
        beatAlignedStartRunnable = null

        runEqualPowerFade(
            standby,
            current,
            nextIndex,
            actualFadeMs,
            applyBassSwap,
            phaseLockActive,
            transitionCueAvailable,
            nativeFadeAvailable,
            bassOverlapGains,
            midOverlapGains,
            highOverlapGains,
        )
        }

    /**
     * Equal-power fade animation.
     *
     * Volumes at linear progress t ∈ [0,1]:
     *   old = targetVol × cos(t × π/2)
     *   new = targetVol × sin(t × π/2)
     *
     * Step interval: FADE_STEP_MS (16 ms ≈ 62 fps) for a smooth perceptual curve.
     */
    private fun runEqualPowerFade(
    newPlayer: ExoPlayer,
    oldPlayer: ExoPlayer,
    nextIndex: Int,
    durationMs: Long,
    applyBassSwap: Boolean,
    phaseLock: Boolean,
    tailFilter: Boolean,
    nativeFadeEnabled: Boolean,
    bassOverlapGains: Pair<Float, Float>?,
    midOverlapGains: Pair<Float, Float>?,
    highOverlapGains: Pair<Float, Float>?,
) {
        crossfadeFadeRunnable?.let { handler.removeCallbacks(it) }
        // durationMs is source-media time. Integrate monotonic wall time using
        // the outgoing processor's applied speed each tick, rather than relying
        // on PlaybackParameters.speed (Signalsmith owns the real stretch ratio).
        val sourcePositionAtStartMs = oldPlayer.currentPosition.coerceAtLeast(0L)
        val sourceDurationMs = oldPlayer.duration
        val effectiveDurationMs = if (sourceDurationMs > 0L && sourceDurationMs != C.TIME_UNSET) {
            minOf(
                durationMs,
                (sourceDurationMs - sourcePositionAtStartMs).coerceAtLeast(1L),
            )
        } else {
            durationMs.coerceAtLeast(1L)
        }
        val estimatedSteps = (effectiveDurationMs / FADE_STEP_MS).coerceAtLeast(1L).toInt()
        var elapsedMediaMs = 0.0
        var lastFadeTickAtMs = monotonicClockMs()
        var step = 0
        var lastPhaseLockAt: Long? = null
        var nativeFadeActive = nativeFadeEnabled

        val runnable = object : Runnable {
            override fun run() {
                // Guard: abort if the active player changed underneath us
                if (getActivePlayer() !== newPlayer) {
                    CrossfadeTimelineLogger.stamp(
                        "runEqualPowerFade: ABORT — active player changed mid-fade (ticks=$step)",
                        getActivePlayer())
                    crossfadeInProgress   = false
                    promotionTriggered    = false
                    prewarmTriggered      = false
                    promotionOwner        = null
                    crossfadeFadeRunnable = null
                    setAutoMixBassGain(newPlayer, 1f)
                    setAutoMixBassGain(oldPlayer, 1f)
                    setAutoMixMidGain(newPlayer, 1f)
                    setAutoMixMidGain(oldPlayer, 1f)
                    setAutoMixTempoNudge(newPlayer, 1f)
                    setAutoMixTailFilter(newPlayer, 1f)
                    setAutoMixTailFilter(oldPlayer, 1f)
                    setAutoMixFadeGain(newPlayer, 1f)
                    setAutoMixFadeGain(oldPlayer, 1f)
                    log("Fade aborted — active player changed mid-fade")
                    // Reset epoch so a subsequent crossfade starts with a clean timeline.
                    CrossfadeTimelineLogger.end("runEqualPowerFade abort — player changed mid-fade")
                    return
                }

                val nowForProgress = monotonicClockMs()
                // A wall-clock tick is not proof that media advanced. Freeze the
                // envelope while either deck is paused/buffering, and discard that
                // interval so recovery cannot cause a large catch-up jump.
                val bothDecksAdvancing = oldPlayer.isPlaying && newPlayer.isPlaying
                val wallDeltaMs = if (bothDecksAdvancing && nowForProgress >= lastFadeTickAtMs) {
                    nowForProgress - lastFadeTickAtMs
                } else {
                    0L
                }
                if (nowForProgress >= lastFadeTickAtMs) lastFadeTickAtMs = nowForProgress
                elapsedMediaMs = AutomixTransitionPolicy.advanceMediaTimeline(
                    elapsedMediaMs,
                    wallDeltaMs,
                    getMediaPlaybackSpeedForPlayer(oldPlayer),
                )
                val t = AutomixTransitionPolicy.mediaTimelineProgress(
                    elapsedMediaMs,
                    effectiveDurationMs,
                )
                if (t >= 1f) {
                    setAutoMixBassGain(newPlayer, 1f)
                    setAutoMixBassGain(oldPlayer, 1f)
                    setAutoMixMidGain(newPlayer, 1f)
                    setAutoMixMidGain(oldPlayer, 1f)
                    // The promoted deck takes over at its own tempo and with a
                    // dry tone: a phase correction or a tail filter must never
                    // survive into the next track.
                    setAutoMixTempoNudge(newPlayer, 1f)
                    setAutoMixTailFilter(newPlayer, 1f)
                    setAutoMixTailFilter(oldPlayer, 1f)
                    // ── Crossfade complete ─────────────────────────────────────
                    CrossfadeTimelineLogger.stampDual(
                        "runEqualPowerFade: COMPLETE (ticks=$step) — about to stop old player",
                        newPlayer, oldPlayer)

                    val targetVol = getEffectiveVolume().coerceIn(0f, 1f)
                    setActiveQueueIndex(nextIndex) 
                    setAutoMixFadeGain(newPlayer, 1f)
                    newPlayer.volume = targetVol

                    // Stop and release the old player's audio resources
                    CrossfadeTimelineLogger.stamp("runEqualPowerFade: oldPlayer.pause() START", oldPlayer)
                    try { oldPlayer.pause()           } catch (_: Exception) {}
                    CrossfadeTimelineLogger.stamp("runEqualPowerFade: oldPlayer.stop() START", oldPlayer)
                    try { oldPlayer.stop()            } catch (_: Exception) {}
                    CrossfadeTimelineLogger.stamp("runEqualPowerFade: oldPlayer.clearMediaItems() START", oldPlayer)
                    try { oldPlayer.clearMediaItems() } catch (_: Exception) {}
                    setAutoMixFadeGain(oldPlayer, 1f)
                    CrossfadeTimelineLogger.stamp("runEqualPowerFade: old player stopped+cleared", oldPlayer)

                    CrossfadeTimelineLogger.stamp("runEqualPowerFade: setActivePlayer(newPlayer)", newPlayer)
                    setActivePlayer(newPlayer)

                    // NOTE: switchSessionPlayer is called here even though it was already called
                    // in beginCrossfade() when standby was promoted.  This second call is a no-op
                    // inside ActivePlayerProxy.switchTo() when newPlayer === _current, but we log
                    // it explicitly to confirm whether listeners are re-migrated here.
                    CrossfadeTimelineLogger.stamp(
                        "runEqualPowerFade: ActivePlayerProxy.switchTo(newPlayer) START [2nd call]", newPlayer)
                    switchSessionPlayer(newPlayer)
                    CrossfadeTimelineLogger.stamp(
                        "runEqualPowerFade: ActivePlayerProxy.switchTo(newPlayer) DONE [2nd call]", newPlayer)
                   
                    crossfadeInProgress   = false
                    promotionTriggered    = false
                    prewarmTriggered      = false
                    promotionOwner        = null
                    crossfadeFadeRunnable = null
                    preloadManager.resetPreloadedIndex()

                    log("Crossfade complete: ${effectiveDurationMs}ms source-media duration, $step ticks")

                    // Rebuild full queue on promoted player + re-attach effects.
                    // *** THIS IS THE PRIMARY SUSPECT for post-fade decoder re-init. ***
                    // onCrossfadeComplete() calls:
                    //   1. queueManager.rebuildPlayerQueue()  → p.setMediaItems(fullQueue, idx, pos)
                    //   2. effectsManager.attachEffects(sessionId)
                    // Both are stamped inside their respective methods.
                    CrossfadeTimelineLogger.stamp(
                        "runEqualPowerFade: calling onCrossfadeComplete() START", newPlayer)
                    onCrossfadeComplete()
                    CrossfadeTimelineLogger.stamp(
                        "runEqualPowerFade: onCrossfadeComplete() DONE", newPlayer)

                    emitAll()
                    refreshNotification()

                    // Preload the track after the newly active one
                    preloadManager.preloadNextTrack(force = true)

                    CrossfadeTimelineLogger.end("preloadNextTrack(force) dispatched")
                    return
                }

                // ── Equal-power volume update ──────────────────────────────────
                // Read the target on every tick so a user volume change or a
                // duck/restore event during the overlap is reflected immediately.
                // Capturing this once before the fade would restore the stale
                // pre-change volume at completion.
                val targetVol = getEffectiveVolume().coerceIn(0f, 1f)
                // Transition-specific three-band targets are attenuations only.
                // Apply them with a bounded overlap envelope; the native DSP
                // smooths every target over ~20 ms without audio-thread locks.
                val overlapEnvelope = sin(PI * t.toDouble()).toFloat().coerceIn(0f, 1f)
                var outgoingBass = 1f
                var incomingBass = 1f
                if (applyBassSwap) {
                    // Keep outgoing bass until the blend is established, then
                    // transfer the low band smoothly to the incoming deck.
                    outgoingBass = if (t <= 0.45f) 1f
                        else (1f - (t - 0.45f) / 0.55f).coerceIn(0f, 1f)
                    incomingBass = if (t <= 0.40f) 0f
                        else ((t - 0.40f) / 0.60f).coerceIn(0f, 1f)
                }
                if (bassOverlapGains != null) {
                    outgoingBass *= 1f - (1f - bassOverlapGains.first.coerceIn(0f, 1f)) * overlapEnvelope
                    incomingBass *= 1f - (1f - bassOverlapGains.second.coerceIn(0f, 1f)) * overlapEnvelope
                }
                if (applyBassSwap || bassOverlapGains != null) {
                    setAutoMixBassGain(oldPlayer, outgoingBass)
                    setAutoMixBassGain(newPlayer, incomingBass)
                }
                if (midOverlapGains != null) {
                    val outgoingMid = 1f - (1f - midOverlapGains.first.coerceIn(0f, 1f)) * overlapEnvelope
                    val incomingMid = 1f - (1f - midOverlapGains.second.coerceIn(0f, 1f)) * overlapEnvelope
                    setAutoMixMidGain(oldPlayer, outgoingMid)
                    setAutoMixMidGain(newPlayer, incomingMid)
                }

                // ── AutoMix phase lock ─────────────────────────────────────────
                // The fade is scheduled ONCE, but the two ExoPlayers decode
                // independently: buffer jitter and clock drift slide them apart
                // while they overlap. Re-measure both grids and re-time the
                // incoming deck (rate only, never a seek) so the beats stay
                // locked until the hand-over. Each correction is re-derived from
                // live positions, so a wrong measurement self-corrects.
                if (phaseLock) {
                    val now = monotonicClockMs()
                    val previousSample = lastPhaseLockAt
                    if (previousSample == null ||
                        AutomixTransitionPolicy.shouldSamplePhaseLock(
                            now,
                            previousSample,
                            PHASE_LOCK_INTERVAL_MS,
                        )
                    ) {
                        lastPhaseLockAt = now
                        val oldLive = getAutoMixLiveBeatStateForPlayer(oldPlayer)
                            ?.takeIf { it.confidence >= LIVE_BEAT_MIN_CONFIDENCE }
                        val newLive = getAutoMixLiveBeatStateForPlayer(newPlayer)
                            ?.takeIf { it.confidence >= LIVE_BEAT_MIN_CONFIDENCE }
                        val useLivePhase = oldLive != null && newLive != null
                        val oldBpm = if (useLivePhase) oldLive!!.bpm else getAutoMixBpmForPlayer(oldPlayer)
                        val oldOffset = if (useLivePhase) 0L else getAutoMixBeatOffsetMsForPlayer(oldPlayer)
                        val newBpm = if (useLivePhase) newLive!!.bpm else getAutoMixBpmForPlayer(newPlayer)
                        val newOffset = if (useLivePhase) 0L else getAutoMixBeatOffsetMsForPlayer(newPlayer)
                        if (oldBpm != null && oldOffset != null &&
                            newBpm != null && newOffset != null &&
                            oldBpm > 0f && newBpm > 0f
                        ) {
                            // Convert the remaining outgoing source-media horizon to wall
                            // time, then into incoming source-media time. Read both applied
                            // speeds every sample so speed changes during a blend are tracked.
                            val remainingOutgoingMediaMs =
                                (effectiveDurationMs.toDouble() - elapsedMediaMs)
                                    .coerceAtLeast(0.0)
                            val outgoingSpeed = AutomixTransitionPolicy.normalizedPlaybackSpeed(
                                getMediaPlaybackSpeedForPlayer(oldPlayer),
                            ).toDouble()
                            val incomingSpeed = AutomixTransitionPolicy.normalizedPlaybackSpeed(
                                getMediaPlaybackSpeedForPlayer(newPlayer),
                            ).toDouble()
                            val remainingMediaMs =
                                (remainingOutgoingMediaMs / outgoingSpeed) * incomingSpeed
                            val oldDownbeat = if (useLivePhase) null
                                else getAutoMixDownbeatOffsetMsForPlayer(oldPlayer)
                            val newDownbeat = if (useLivePhase) null
                                else getAutoMixDownbeatOffsetMsForPlayer(newPlayer)

                            // Prefer bar/phrase alignment when both tracks have
                            // confident downbeat grids. Fall back to the existing
                            // beat-level correction whenever either grid is absent.
                            val phraseFactor =
                                if (oldDownbeat != null && newDownbeat != null) {
                                    AutomixPhaseLock.phraseFactorFor(
                                        outgoingPositionMs = oldPlayer.currentPosition.toDouble(),
                                        outgoingDownbeatOffsetMs = oldDownbeat.toDouble(),
                                        outgoingBpm = oldBpm.toDouble(),
                                        incomingPositionMs = newPlayer.currentPosition.toDouble(),
                                        incomingDownbeatOffsetMs = newDownbeat.toDouble(),
                                        incomingBpm = newBpm.toDouble(),
                                        remainingMs = remainingMediaMs,
                                        beatsPerPhrase = 16,
                                    )
                                } else {
                                    null
                                }
                            val tempoFactor = phraseFactor ?: AutomixPhaseLock.factorFor(
                                outgoingPositionMs = if (useLivePhase) oldLive!!.phaseElapsedMs
                                    else oldPlayer.currentPosition.toDouble(),
                                outgoingPhaseOffsetMs = if (useLivePhase) 0.0 else oldOffset.toDouble(),
                                outgoingBpm = oldBpm.toDouble(),
                                incomingPositionMs = if (useLivePhase) newLive!!.phaseElapsedMs
                                    else newPlayer.currentPosition.toDouble(),
                                incomingPhaseOffsetMs = if (useLivePhase) 0.0 else newOffset.toDouble(),
                                incomingBpm = newBpm.toDouble(),
                                remainingMs = remainingMediaMs,
                            )
                            if (tempoFactor != null) {
                                setAutoMixTempoNudge(newPlayer, tempoFactor)
                            }
                        }
                    }
                }
                // AutoMix shaping: transfer curve (gamma) and the level match
                // between the decks. The louder deck's trim stays flat (it is
                // silenced at the end anyway) while the incoming trim is
                // released over the last quarter so the promoted deck ends at
                // its own level — no step when the fade completes.
                val nativeApplied = nativeFadeActive && setAutoMixCrossfadeGains(
                    oldPlayer,
                    newPlayer,
                    t,
                    fadeGamma,
                    outgoingTrim,
                    incomingTrim,
                )
                if (nativeFadeActive && !nativeApplied) {
                    setAutoMixFadeGain(oldPlayer, 1f)
                    setAutoMixFadeGain(newPlayer, 1f)
                    nativeFadeActive = false
                }
                if (nativeFadeActive) {
                    // Keep ExoPlayer's volume as the master/user/audio-focus
                    // control. Native C/NEON applies the per-deck fade envelope.
                    oldPlayer.volume = targetVol
                    // Keep the incoming deck muted for the first audio block so
                    // the native target can settle from any previous track state.
                    newPlayer.volume = if (step == 0) 0f else targetVol
                } else {
                    val gains = AutomixGainEnvelope.gains(
                        progress = t,
                        targetVolume = targetVol,
                        curveGamma = fadeGamma,
                        outgoingTrim = outgoingTrim,
                        incomingTrim = incomingTrim,
                    )
                    oldPlayer.volume = gains.outgoing
                    newPlayer.volume = gains.incoming
                }

                // ── Tail filter-out ────────────────────────────────────────────
                // The outgoing deck eases its high band away over the second
                // half of the blend (at most -12 dB) while the incoming deck
                // stays dry, so the hand-over sounds intentional instead of cut
                // short. An idle AutoMix deck is bit-transparent.
                if (tailFilter) {
                    val tail = ((t - 0.55f) / 0.45f).coerceIn(0f, 1f)
                    val eased = tail * tail * (3f - 2f * tail)
                    val outgoingHigh = highOverlapGains?.first?.coerceIn(0f, 1f)
                        ?: (1f - MAX_TAIL_FILTER)
                    val incomingHigh = highOverlapGains?.second?.coerceIn(0f, 1f) ?: 1f
                    setAutoMixTailFilter(oldPlayer, 1f - (1f - outgoingHigh) * eased)
                    setAutoMixTailFilter(newPlayer, 1f - (1f - incomingHigh) * eased)
                }
                step++
                handler.postDelayed(this, FADE_STEP_MS)
            }
        }
        crossfadeFadeRunnable = runnable
        handler.post(runnable)
        log("Equal-power fade started: ${effectiveDurationMs}ms source-media duration, ~${estimatedSteps} ticks")
    }

    private fun log(msg: String) = NativeLogger.emit("info", "Crossfade", msg)
}
