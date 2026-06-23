package com.example.musicplayer.audio_offload

import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.events.NativeLogger

/**
 * Manages Audio Offload scheduling on the active ExoPlayer instance.
 *
 * ════════════════════════════════════════════════════════════════════
 * AUDIT RESULT — why full offload mode is NOT used
 * ════════════════════════════════════════════════════════════════════
 *
 * Full Audio Offload (AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_ENABLED) would
 * route decoded audio directly to the hardware DSP, bypassing the CPU-side
 * AudioFlinger rendering pipeline.  That is incompatible with three core features
 * of this app:
 *
 * 1. CROSSFADE — FATAL
 *    The equal-power fade sets player.volume every 16 ms via a Handler runnable.
 *    Audio Offload does not support real-time volume changes on an offloaded track:
 *    the OS either silently ignores them or forces the player to exit offload mode
 *    mid-song, both of which produce an audible glitch.  Additionally,
 *    experimentalSetOffloadSchedulingEnabled(true) lets the CPU sleep between audio
 *    writes; that makes Handler.postDelayed(16 ms) unreliable — steps would be
 *    skipped and the fade would stutter.
 *
 * 2. DUAL PLAYER — FATAL
 *    During the crossfade overlap window (up to 30 s) both ExoPlayer instances
 *    output audio simultaneously.  The hardware DSP provides at most one offloaded
 *    audio slot; the secondary player always falls back to CPU rendering.  Requesting
 *    offload on the primary while the secondary is also active causes AudioFlinger to
 *    forcibly de-offload the primary mid-song.
 *
 * 3. SOFTWARE AUDIO EFFECTS — FATAL
 *    Equalizer, LoudnessEnhancer, BassBoost, Virtualizer, and PresetReverb are
 *    Android software effects that live in the AudioFlinger effects chain.  Audio
 *    Offload routes audio around this chain directly to the DSP; the effects would
 *    silently stop processing audio while appearing to be enabled — users would
 *    hear no EQ, no bass boost, etc.
 *
 * ════════════════════════════════════════════════════════════════════
 * WHAT IS IMPLEMENTED
 * ════════════════════════════════════════════════════════════════════
 *
 * Only experimentalSetOffloadSchedulingEnabled() is toggled.  This flag does NOT
 * force offload — it tells ExoPlayer's render loop to sleep between audio writes
 * *if and only if* the OS has already granted offload mode on its own.
 *
 * The OS grants offload automatically when ALL of the following are true:
 *   • The audio format is supported by the hardware DSP (PCM / AAC / MP3 on most
 *     Android 10 + devices, including Snapdragon SoCs on MIUI 12).
 *   • No software effects are attached to the audio session.
 *   • Only one audio stream is being decoded (no dual-player overlap).
 *
 * When the OS does not grant offload this flag has zero effect — the render loop
 * stays in normal mode and battery usage is unchanged.
 *
 * ════════════════════════════════════════════════════════════════════
 * DYNAMIC CONTROL
 * ════════════════════════════════════════════════════════════════════
 *
 * Scheduling is DISABLED whenever crossfade is active or configured, then
 * re-evaluated after crossfade completes or is turned off.
 *
 * Callers:
 *   onCrossfadeDurationChanged(sec) — called from TransportCommands.setCrossfadeDuration
 *   onCrossfadeStarting()           — called from CrossfadeController.beginCrossfade
 *   onCrossfadeComplete(sec)        — called from Media3PlaybackService.onCrossfadeComplete
 *   makeOffloadListener()           — attach returned listener to each ExoPlayer instance
 */
@UnstableApi
class AudioOffloadManager(
    private val getActivePlayer: () -> ExoPlayer?,
    /**
     * Called on the main thread whenever the observed offload state changes.
     * [scheduling] — whether experimentalSetOffloadSchedulingEnabled is currently true.
     * [osGranted]  — whether the OS has granted hardware offload on the active player.
     *
     * Media3PlaybackService wires this to EventEmitter so Flutter can react in real time.
     */
    private val onOffloadStateChanged: (scheduling: Boolean, osGranted: Boolean) -> Unit = { _, _ -> },
) {

    private var schedulingEnabled = false
    private var osGranted         = false
    private var lastReason        = "init"

    /**
     * When true, offload scheduling is force-disabled regardless of crossfade state.
     * Toggled by the user via the "Audio Offload Scheduling" toggle in Settings →
     * Jalur Audio.  Useful as a debug/workaround escape hatch on MIUI devices where
     * AudioFlinger's offload path is unstable.
     */
    private var forceDisabled = false

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Called from the Settings toggle ("Audio Offload Scheduling").
     *
     * When [enabled] is false the flag is pinned off permanently, overriding all
     * automatic logic.  When [enabled] is true automatic control resumes and
     * eligibility is re-evaluated immediately.
     */
    fun setForceDisabled(disabled: Boolean) {
        forceDisabled = disabled
        if (disabled) {
            applyScheduling(
                enable = false,
                reason = "user force-disabled offload scheduling in Settings",
            )
        } else {
            // Re-apply the last logical state.  Scheduling stays off until
            // TransportCommands fires onCrossfadeDurationChanged next, which
            // correctly re-evaluates based on current crossfade config.
            applyScheduling(
                enable = false,
                reason = "user re-enabled offload scheduling — awaiting crossfade check",
            )
        }
    }

    // ── State transitions ─────────────────────────────────────────────────────

    /**
     * Called whenever the crossfade duration setting changes.
     *
     * With crossfade > 0 the standby player can come to life at any moment and
     * overlap with the primary, so offload scheduling must stay off permanently
     * until crossfade is disabled.
     */
    fun onCrossfadeDurationChanged(durationSec: Float) {
        if (durationSec > 0f) {
            applyScheduling(
                enable = false,
                reason = "crossfade enabled (${durationSec}s) — standby player may overlap at any time",
            )
        } else {
            applyScheduling(
                enable = true,
                reason = "crossfade disabled — OS may grant offload if format and effects allow",
            )
        }
    }

    /**
     * Called at the very start of a crossfade (before the first volume-fade tick).
     *
     * Disabling offload scheduling here guarantees that Handler.postDelayed(16 ms)
     * fires reliably for the equal-power fade ticks regardless of whether the OS
     * previously granted offload on this player.
     */
    fun onCrossfadeStarting() {
        applyScheduling(
            enable = false,
            reason = "crossfade ACTIVE — 16 ms Handler ticks require CPU awake",
        )
    }

    /**
     * Called after crossfade fully completes and the new player is active.
     *
     * Re-evaluates eligibility: if crossfade will be used again (duration > 0)
     * keep scheduling off; otherwise re-enable so the OS can try offload on the
     * promoted player's new audio session.
     */
    fun onCrossfadeComplete(currentDurationSec: Float) {
        if (currentDurationSec > 0f) {
            applyScheduling(
                enable = false,
                reason = "post-promotion: crossfade still enabled (${currentDurationSec}s)",
            )
        } else {
            applyScheduling(
                enable = true,
                reason = "post-promotion: crossfade=0 — re-evaluating offload eligibility",
            )
        }
    }

    /**
     * Build an AudioOffloadListener suitable for attaching to any ExoPlayer instance.
     *
     * The listener reports OS-level offload decisions to the native log stream so
     * they appear in the app's in-app debug log:
     *   • "OS GRANTED offload"   → battery saving is active
     *   • "OS EXITED offload"    → fallback to CPU rendering (with reason)
     *   • scheduling on/off      → driven by this manager
     */
    fun makeOffloadListener(): ExoPlayer.AudioOffloadListener =
        object : ExoPlayer.AudioOffloadListener {

            // Called when the OS grants or revokes hardware offload for this player.
            override fun onOffloadedPlayback(offloadedPlayback: Boolean) {
                osGranted = offloadedPlayback
                if (offloadedPlayback) {
                    NativeLogger.emit(
                        "info", "AudioOffload",
                        "OS GRANTED offload mode — DSP decoding active, CPU can enter deeper sleep " +
                        "(battery saving is NOW active)",
                    )
                } else {
                    NativeLogger.emit(
                        "info", "AudioOffload",
                        "OS EXITED / REJECTED offload — fallback to normal CPU rendering. " +
                        "Likely cause: software effects attached, dual-player overlap, " +
                        "or audio format not supported by hardware DSP on this device.",
                    )
                }
                // Notify Flutter of the new observed state.
                onOffloadStateChanged(schedulingEnabled, osGranted)
            }

            // Called when experimentalSetOffloadSchedulingEnabled value changes.
            override fun onOffloadSchedulingEnabledChanged(offloadSchedulingEnabled: Boolean) {
                NativeLogger.emit(
                    "info", "AudioOffload",
                    "Offload scheduling changed → ${if (offloadSchedulingEnabled) "ON" else "OFF"}",
                )
            }
        }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun applyScheduling(enable: Boolean, reason: String) {
        // forceDisabled overrides all automatic logic.
        val effective = enable && !forceDisabled
        val changed = schedulingEnabled != effective
        schedulingEnabled = effective
        lastReason = reason

        if (changed) {
            try {
                getActivePlayer()?.experimentalSetOffloadSchedulingEnabled(effective)
            } catch (e: Exception) {
                NativeLogger.emit(
                    "warn", "AudioOffload",
                    "experimentalSetOffloadSchedulingEnabled($effective) threw: ${e.message}",
                )
            }
        }

        val verb = if (effective) "ENABLED " else "DISABLED"
        val suffix = if (!enable) "" else if (forceDisabled) " (overridden: user force-disabled)" else ""
        NativeLogger.emit("info", "AudioOffload", "Scheduling $verb — $reason$suffix")

        // Notify Flutter so the debug status indicator updates immediately.
        onOffloadStateChanged(schedulingEnabled, osGranted)
    }
}
