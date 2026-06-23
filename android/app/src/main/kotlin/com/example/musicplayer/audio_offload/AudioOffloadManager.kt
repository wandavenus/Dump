package com.example.musicplayer.audio_offload

import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.events.NativeLogger
import com.example.musicplayer.events.SessionAuditLogger

/**
 * Observes and reports Audio Offload state on the active ExoPlayer instance.
 *
 * ════════════════════════════════════════════════════════════════════
 * MEDIA3 1.10.1 API AUDIT — WHAT CHANGED
 * ════════════════════════════════════════════════════════════════════
 *
 * REMOVED (no longer exist in Media3 1.10.1):
 *   • ExoPlayer.experimentalSetOffloadSchedulingEnabled(Boolean)
 *     → Removed from the public API surface entirely.  Media3 now manages
 *       CPU scheduling internally when the OS grants hardware offload.
 *       There is no replacement API; calling it in older code causes an
 *       "Unresolved reference" compile error.
 *
 *   • ExoPlayer.AudioOffloadListener.onOffloadSchedulingEnabledChanged(Boolean)
 *     → Removed alongside the scheduling control API.  Implementing this
 *       override causes a "overrides nothing" compile error.
 *
 * AVAILABLE (still exists in Media3 1.10.1):
 *   • ExoPlayer.AudioOffloadListener.onOffloadedPlayback(Boolean)
 *     → Called whenever the OS grants or revokes hardware offload for a
 *       specific audio session.  This is the only offload callback surface
 *       available in 1.10.1.
 *
 *   • ExoPlayer.addAudioOffloadListener(AudioOffloadListener)
 *     → Still valid for attaching a listener to any ExoPlayer instance.
 *
 * SCHEDULING BEHAVIOUR IN 1.10.1:
 *   When the OS grants hardware offload (onOffloadedPlayback = true), Media3
 *   automatically manages CPU scheduling — the render loop sleeps between
 *   audio writes without any explicit API call.  This is not configurable.
 *
 * ════════════════════════════════════════════════════════════════════
 * WHY FULL OFFLOAD IS STILL INCOMPATIBLE WITH THIS APP
 * ════════════════════════════════════════════════════════════════════
 *
 * 1. CROSSFADE — FATAL
 *    The equal-power fade updates player.volume every 16 ms via Handler.
 *    When the OS grants offload, Media3's internal scheduling allows the CPU
 *    to sleep between audio writes, making Handler.postDelayed(16 ms) fire
 *    at unpredictable intervals — volume steps are skipped and the fade
 *    stutters.  Additionally, hardware offload supports only one DSP slot;
 *    the dual-player overlap forces the primary off offload mid-song.
 *
 * 2. DUAL PLAYER — FATAL
 *    Two simultaneous ExoPlayer instances (crossfade overlap window up to
 *    30 s).  The hardware DSP provides at most one offloaded audio slot.
 *    The OS will de-offload the primary as soon as the secondary activates.
 *
 * 3. SOFTWARE AUDIO EFFECTS — FATAL
 *    Equalizer, LoudnessEnhancer, BassBoost, Virtualizer, and PresetReverb
 *    live in the AudioFlinger software effects chain.  Hardware offload routes
 *    audio around this chain directly to the DSP; effects stop processing while
 *    appearing to be enabled.
 *
 * ════════════════════════════════════════════════════════════════════
 * IMPLEMENTATION: OBSERVER ONLY
 * ════════════════════════════════════════════════════════════════════
 *
 * This class is now a pure observer.  It:
 *   • Reports OS grant / revoke events via NativeLogger and the
 *     [onOffloadStateChanged] callback so Flutter can update its UI.
 *   • Tracks crossfade state to enrich "why is offload unavailable" log
 *     messages — no scheduling control is attempted.
 *
 * Because scheduling is now managed by Media3 internally, all previous
 * calls to experimentalSetOffloadSchedulingEnabled() are gone.  The
 * [setForceDisabled] method is retained as a documented no-op so the Dart
 * "Audio Offload Scheduling" settings toggle survives without a MethodChannel
 * removal, but it no longer affects any native behaviour.
 */
@UnstableApi
class AudioOffloadManager(
    /**
     * Returns the live crossfade duration (in seconds) from CrossfadeController.
     * Read inside [onCrossfadeComplete] so the decision always uses the current
     * authoritative value.
     */
    private val getCrossfadeDurationSec: () -> Float = { 0f },

    /**
     * Called on the main thread whenever the observed OS offload state changes.
     * [osGranted] — whether the OS has granted hardware offload on the active
     * player at this moment.
     *
     * Media3PlaybackService wires this to EventEmitter so Flutter can react in
     * real time.  The former `scheduling` parameter has been removed because
     * Media3 1.10.1 no longer exposes scheduling control.
     */
    private val onOffloadStateChanged: (osGranted: Boolean) -> Unit = {},
) {

    private var osGranted          = false
    private var crossfadeActive    = false
    private var crossfadeDuration  = 0f

    /**
     * Retained for MethodChannel backward compatibility.
     * In Media3 1.10.1 this is a NO-OP: there is no public API to force
     * offload scheduling on or off.  The call is logged so the developer can
     * observe that the setting was received but cannot be applied.
     */
    fun setForceDisabled(disabled: Boolean) {
        NativeLogger.emit(
            "info", "AudioOffload",
            "setForceDisabled($disabled) received — NOTE: Media3 1.10.1 removed " +
            "experimentalSetOffloadSchedulingEnabled(); scheduling is now managed " +
            "internally by Media3 when the OS grants offload.  This call has no effect.",
        )
    }

    // ── Crossfade state tracking (for logging only) ────────────────────────────

    /**
     * Called whenever the crossfade duration setting changes.
     * Updates the internal state used to explain offload unavailability in logs.
     */
    fun onCrossfadeDurationChanged(durationSec: Float) {
        crossfadeDuration = durationSec
        if (durationSec > 0f) {
            NativeLogger.emit(
                "info", "AudioOffload",
                "Offload eligibility note: crossfade enabled (${durationSec}s) — " +
                "dual-player overlap and 16 ms volume ticks prevent hardware offload; " +
                "OS will reject or de-offload if granted.",
            )
        } else {
            NativeLogger.emit(
                "info", "AudioOffload",
                "Offload eligibility note: crossfade disabled — " +
                "OS may grant offload if no software effects are attached " +
                "and the audio format is DSP-supported on this device.",
            )
        }
    }

    /**
     * Called at the very start of a crossfade.
     * Updates the internal state used to enrich offload log messages.
     */
    fun onCrossfadeStarting() {
        crossfadeActive = true
        NativeLogger.emit(
            "info", "AudioOffload",
            "Offload eligibility note: crossfade ACTIVE — dual-player overlap in progress; " +
            "OS will de-offload primary player if it had been granted.",
        )
    }

    /**
     * Called after crossfade fully completes and the new player is active.
     * Re-evaluates and logs the eligibility state based on the live crossfade
     * duration from [getCrossfadeDurationSec].
     */
    fun onCrossfadeComplete() {
        crossfadeActive = false
        val dur = getCrossfadeDurationSec()
        if (dur > 0f) {
            NativeLogger.emit(
                "info", "AudioOffload",
                "Offload eligibility note: post-promotion — crossfade still enabled (${dur}s); " +
                "dual-player overlap will continue blocking hardware offload.",
            )
        } else {
            NativeLogger.emit(
                "info", "AudioOffload",
                "Offload eligibility note: post-promotion — crossfade=0; " +
                "OS may now grant offload on the promoted player if format and effects allow.",
            )
        }
    }

    /**
     * Build an AudioOffloadListener for attaching to any ExoPlayer instance.
     *
     * Media3 1.10.1 AudioOffloadListener surface:
     *   • onOffloadedPlayback(Boolean) — only valid callback; reports OS grant / revoke.
     *
     * Removed in 1.10.1 (not implemented here):
     *   • onOffloadSchedulingEnabledChanged(Boolean) — removed from the interface.
     */
    fun makeOffloadListener(): ExoPlayer.AudioOffloadListener =
        object : ExoPlayer.AudioOffloadListener {

            override fun onOffloadedPlayback(offloadedPlayback: Boolean) {
                osGranted = offloadedPlayback

                if (offloadedPlayback) {
                    NativeLogger.emit(
                        "info", "AudioOffload",
                        "OS GRANTED hardware offload — audio decoded by DSP; " +
                        "Media3 now manages CPU scheduling internally (sleeps between audio writes). " +
                        "Battery saving is ACTIVE.",
                    )
                    SessionAuditLogger.onOffloadGranted()
                } else {
                    val reasons = buildList {
                        if (crossfadeActive)          add("crossfade in progress (dual-player DSP slot conflict)")
                        else if (crossfadeDuration > 0f) add("crossfade enabled (${crossfadeDuration}s) — dual-player risk")
                        add("software effects attached (EQ/LoudnessEnhancer/BassBoost/Virtualizer/Reverb bypass offload path)")
                        add("audio format not DSP-supported on this device / Android version")
                    }
                    val reasonStr = reasons.joinToString("; ")
                    NativeLogger.emit(
                        "info", "AudioOffload",
                        "OS REVOKED / REJECTED hardware offload — CPU rendering active. " +
                        "Possible causes: $reasonStr.",
                    )
                    SessionAuditLogger.onOffloadRevoked(reasonStr)
                }
                onOffloadStateChanged(osGranted)
            }
        }
}
