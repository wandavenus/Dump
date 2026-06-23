package com.example.musicplayer.events

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Per-track audit chain emitted into the NativeLogger stream.
 *
 * ════════════════════════════════════════════════════════════════════
 * DESIGN
 * ════════════════════════════════════════════════════════════════════
 *
 * Every time a new track becomes active (normal gapless transition, manual
 * skip, or crossfade promotion) a new CHAPTER is opened with a visible
 * banner header:
 *
 *   ══ TRACK #3 ══════════════════════════════════════════════════════
 *     Title:        Bohemian Rhapsody
 *     Artist:       Queen
 *     AudioSession: 42
 *     Started:      14:32:01.123
 *   ──────────────────────────────────────────────────────────────────
 *     [+0ms]    Session — audioSessionId assigned → 42
 *     [+152ms]  Effects — attaching to audioSession=42
 *     [+304ms]  Effects — attached attempt=1 [EQ✓ Loud✓ Bass✗ Virt✗ Rev✗]
 *     [+2.4s]   Offload — OS GRANTED hardware offload — DSP decoding active
 *     [+5m 12s] Transport — PAUSE @ 312450ms
 *     [+5m 15s] Transport — PLAY @ 312450ms
 *     [+5m 44s] Preload — standby ← [4] "Don't Stop Me Now"
 *     [+5m 45s] Preload — standby pre-warm → audio pipeline warming at volume=0
 *     [+5m 46s] Crossfade — fade START — 3000ms equal-power → "Don't Stop Me Now"
 *     [+5m 49s] Crossfade — fade COMPLETE — 3000ms / 187 steps → promoting standby
 *   ══ TRACK #4 ══════════════════════════════════════════════════════
 *     ...
 *
 * Relative timestamps are formatted as:
 *   "+0ms"    (<1 s)
 *   "+1.4s"   (<60 s)
 *   "+1m 23s" (≥60 s)
 *
 * ════════════════════════════════════════════════════════════════════
 * THREAD SAFETY
 * ════════════════════════════════════════════════════════════════════
 *
 * All methods are safe to call from any thread.  The only output path is
 * NativeLogger.emit() → EventChannel.EventSink.success(), which Flutter's
 * EventChannel implementation serialises internally.  @Volatile guards on
 * chapter state prevent torn reads across threads.
 *
 * ════════════════════════════════════════════════════════════════════
 * INTEGRATION POINTS
 * ════════════════════════════════════════════════════════════════════
 *
 *  openChapter()          Media3PlaybackService — onMediaItemTransition (active,
 *                           non-crossfade) and onCrossfadeComplete callback.
 *  onAudioSessionAssigned Media3PlaybackService — onAudioSessionIdChanged.
 *  onEffects*             AudioEffectsManager  — attachEffects() branches.
 *  onPreload / onPrewarm  PreloadManager       — preloadNextTrack / prewarmStandby.
 *  onCrossfadeStarting    CrossfadeController  — beginCrossfade().
 *  onCrossfadeComplete    CrossfadeController  — runEqualPowerFade step≥steps.
 *  onCrossfadeCancelled   CrossfadeController  — cancel() when in-progress.
 *  onOffloadGranted/      AudioOffloadManager  — onOffloadedPlayback().
 *    Revoked
 *  onPlay/Pause/Skip/Seek TransportCommands    — transport handlers.
 */
object SessionAuditLogger {

    private val timeFmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    @Volatile private var chapterSeq     = 0
    @Volatile private var chapterStartMs = 0L

    // ── Chapter management ────────────────────────────────────────────────────

    /**
     * Open a new chapter for a newly active track.
     *
     * Emits a visible banner header and resets the relative-time clock.
     * Safe to call multiple times — each call closes the implicit previous chapter
     * and begins a fresh one.
     */
    fun openChapter(title: String, artist: String, audioSessionId: Int) {
        val seq = ++chapterSeq
        chapterStartMs = System.currentTimeMillis()
        val wall = timeFmt.format(Date(chapterStartMs))

        NativeLogger.emit("info", "Audit",
            "══ TRACK #$seq ══════════════════════════════════════════════════════")
        NativeLogger.emit("info", "Audit", "  Title:        ${title.ifBlank { "Unknown" }}")
        NativeLogger.emit("info", "Audit", "  Artist:       ${artist.ifBlank { "Unknown" }}")
        NativeLogger.emit("info", "Audit", "  AudioSession: $audioSessionId")
        NativeLogger.emit("info", "Audit", "  Started:      $wall")
        NativeLogger.emit("info", "Audit",
            "────────────────────────────────────────────────────────────────────")
    }

    // ── Generic event entry points ─────────────────────────────────────────────

    /** Log an info-level lifecycle event relative to the current chapter start. */
    fun log(phase: String, msg: String) {
        val ts = elapsed()
        NativeLogger.emit("info", "Audit", "  [$ts] $phase — $msg")
    }

    /** Log a warn-level lifecycle event (retries, revocations, cancellations). */
    fun warn(phase: String, msg: String) {
        val ts = elapsed()
        NativeLogger.emit("warn", "Audit", "  [$ts] $phase — $msg")
    }

    // ── Audio session ─────────────────────────────────────────────────────────

    fun onAudioSessionAssigned(sessionId: Int) {
        log("Session", "audioSessionId assigned → $sessionId")
    }

    // ── Transport ─────────────────────────────────────────────────────────────

    fun onPlay(posMs: Long) {
        log("Transport", "PLAY @ ${posMs}ms")
    }

    fun onPause(posMs: Long) {
        log("Transport", "PAUSE @ ${posMs}ms")
    }

    fun onSkipNext() {
        log("Transport", "SKIP → next")
    }

    fun onSkipPrev() {
        log("Transport", "SKIP → previous")
    }

    fun onSeek(posMs: Long) {
        log("Transport", "SEEK → ${posMs}ms")
    }

    // ── Effects ───────────────────────────────────────────────────────────────

    fun onEffectsAttaching(sessionId: Int) {
        log("Effects", "attaching to audioSession=$sessionId")
    }

    fun onEffectsOk(
        sessionId: Int,
        attempt:   Int,
        eq:        Boolean,
        loud:      Boolean,
        bass:      Boolean,
        virt:      Boolean,
        reverb:    Boolean,
    ) {
        val chain = buildString {
            append(if (eq)    "EQ✓ "    else "EQ✗ ")
            append(if (loud)  "Loud✓ "  else "Loud✗ ")
            append(if (bass)  "Bass✓ "  else "Bass✗ ")
            append(if (virt)  "Virt✓ "  else "Virt✗ ")
            append(if (reverb)"Rev✓"    else "Rev✗")
        }
        log("Effects", "attached session=$sessionId attempt=${attempt + 1} [$chain]")
    }

    fun onEffectsRetrying(sessionId: Int, attempt: Int, delayMs: Long) {
        warn("Effects", "all failed session=$sessionId — retry ${attempt + 1} in ${delayMs}ms")
    }

    fun onEffectsFailed(sessionId: Int, attempts: Int) {
        warn("Effects", "FAILED session=$sessionId after $attempts attempts — no effects active")
    }

    // ── Preload / prewarm ────────────────────────────────────────────────────

    fun onPreload(queueIndex: Int, title: String) {
        log("Preload", "standby ← [$queueIndex] \"$title\"")
    }

    fun onPrewarm() {
        log("Preload", "standby pre-warm → audio pipeline warming at volume=0")
    }

    // ── Crossfade ─────────────────────────────────────────────────────────────

    fun onCrossfadeStarting(fadeMs: Long, standbyTitle: String) {
        log("Crossfade", "fade START — ${fadeMs}ms equal-power → \"$standbyTitle\"")
    }

    /**
     * Logged at the END of the current chapter, just before [openChapter] opens
     * the promoted track's chapter.
     */
    fun onCrossfadeComplete(fadeMs: Long, steps: Int) {
        log("Crossfade", "fade COMPLETE — ${fadeMs}ms / $steps steps → promoting standby")
    }

    fun onCrossfadeCancelled(reason: String) {
        warn("Crossfade", "CANCELLED — $reason")
    }

    // ── Offload ───────────────────────────────────────────────────────────────

    fun onOffloadGranted() {
        log("Offload", "OS GRANTED hardware offload — DSP decoding active, battery saving ON")
    }

    fun onOffloadRevoked(reasons: String) {
        warn("Offload", "OS REVOKED / REJECTED offload — CPU rendering. Causes: $reasons")
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun elapsed(): String {
        val ms = System.currentTimeMillis() - chapterStartMs
        return when {
            ms < 1_000L  -> "+${ms}ms"
            ms < 60_000L -> {
                val s   = ms / 1_000L
                val dec = (ms % 1_000L) / 100L
                "+${s}.${dec}s"
            }
            else -> {
                val m = ms / 60_000L
                val s = (ms % 60_000L) / 1_000L
                "+${m}m ${s}s"
            }
        }
    }
}
