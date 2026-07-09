package dev.wndavenz.music.transport

import android.os.Handler
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import dev.wndavenz.music.events.NativeLogger

/**
 * Short volume fade applied ONLY around explicit user play/pause taps.
 *
 * This is intentionally NOT a second "volume controller". It is a thin,
 * single-purpose Handler-tick animator that:
 *   - never runs while [isCrossfadeActive] reports true (CrossfadeController
 *     owns player.volume exclusively during a crossfade — see class doc below),
 *   - only ever drives the single ExoPlayer instance passed in for the current
 *     command (never a standby/background player),
 *   - always cancels any of its own previous ticks before starting a new one,
 *     so two of *its own* animations can never overlap either.
 *
 * Why simultaneous volume automation with CrossfadeController cannot occur:
 *   1. CrossfadeController is the only place that starts a crossfade fade, and
 *      it flips [crossfadeInProgress] to true for its entire duration (prewarm
 *      is silent — only the equal-power fade phase touches volume).
 *   2. Every entry point here ([fadeInOnPlay], [fadeOutThenPause]) checks
 *      `isCrossfadeActive()` BEFORE starting and again on EVERY tick. If a
 *      crossfade is (or becomes) active, this controller snaps the player to
 *      its target volume and yields — it never issues a competing `.volume =`
 *      write while a crossfade tick could also be writing to the same player.
 *   3. Both this class and CrossfadeController post their steps to the SAME
 *      main-thread [Handler], so there is no cross-thread race on `.volume`;
 *      ticks are strictly ordered on one looper.
 *   4. This controller only ever touches the currently *active* player
 *      (the one passed in by TransportCommands at command time) — it never
 *      touches the standby player, which is the only other player crossfade
 *      writes to.
 *
 * Cadence matches [dev.wndavenz.music.crossfade.CrossfadeController]'s
 * FADE_STEP_MS (16 ms / ~62 fps) so both animations feel consistent and reuse
 * the same Handler-tick mechanism rather than introducing a new timer/loop
 * primitive (e.g. ValueAnimator, coroutines, a second Handler).
 */
@UnstableApi
class PlayPauseFadeController(
    private val handler: Handler,
    /** Target ("full") volume to fade toward / away from — post-duck, post-user-volume. */
    private val getTargetVolume: () -> Float,
    /** True while CrossfadeController owns volume automation on some player. */
    private val isCrossfadeActive: () -> Boolean,
) {
    companion object {
        /** Same cadence as CrossfadeController.FADE_STEP_MS for a consistent feel. */
        const val FADE_STEP_MS = 16L

        /** Play: 0.0 → target over ~180-220 ms. */
        const val FADE_IN_MS = 200L

        /** Pause: current → 0.0 over ~120-180 ms, then pause() is called. */
        const val FADE_OUT_MS = 150L
    }

    private var fadeRunnable: Runnable? = null

    /** True while this controller (not CrossfadeController) is mid-animation. */
    var isFading: Boolean = false
        private set

    /**
     * Cancel any in-flight fade owned by this controller.
     *
     * Always safe to call even when nothing is running. When [resetVolume] is
     * true, [player]'s volume is snapped to the target immediately so rapid
     * repeated taps can never leave it stuck partway through a fade.
     */
    fun cancel(player: ExoPlayer?, resetVolume: Boolean) {
        fadeRunnable?.let { handler.removeCallbacks(it) }
        fadeRunnable = null
        isFading = false
        if (resetVolume && player != null) {
            player.volume = getTargetVolume().coerceIn(0f, 1f)
        }
    }

    /**
     * Fade [player]'s volume from 0.0 up to the target volume over
     * [durationMs]. Must be called right before / around [ExoPlayer.play] —
     * volume is snapped to 0 synchronously here so there is no audible pop.
     *
     * No-ops into an instant "set target volume" when a crossfade is active or
     * [durationMs] <= 0, preserving instant play behavior in both cases.
     */
    fun fadeInOnPlay(player: ExoPlayer, durationMs: Long = FADE_IN_MS) {
        // Cancel any previous fade owned by this controller (fade-in or
        // fade-out) WITHOUT forcing a volume snap — we're about to set volume
        // ourselves below, so no window exists for a "stuck" value.
        cancel(player, resetVolume = false)

        val target = getTargetVolume().coerceIn(0f, 1f)
        if (isCrossfadeActive() || durationMs <= 0L) {
            player.volume = target
            return
        }

        player.volume = 0f
        val steps  = (durationMs / FADE_STEP_MS).coerceAtLeast(1L).toInt()
        val stepMs = (durationMs / steps).coerceAtLeast(1L)
        var step   = 0

        val runnable = object : Runnable {
            override fun run() {
                // Defensive guard mirroring CrossfadeController's own mid-tick
                // check: if a crossfade claims volume ownership while we're
                // mid fade-in, stop touching this player immediately.
                if (isCrossfadeActive()) {
                    fadeRunnable = null
                    isFading = false
                    return
                }

                step++
                if (step >= steps) {
                    player.volume = target
                    fadeRunnable = null
                    isFading = false
                    return
                }

                player.volume = (target * step / steps.toFloat()).coerceIn(0f, target)
                handler.postDelayed(this, stepMs)
            }
        }
        fadeRunnable = runnable
        isFading = true
        handler.post(runnable)
        log("fadeInOnPlay: ${durationMs}ms, $steps steps, target=$target")
    }

    /**
     * Fade [player]'s volume from its current level down to 0.0 over
     * [durationMs], THEN invoke [onFadeComplete] (which is expected to call
     * [ExoPlayer.pause] and run the rest of the pause bookkeeping). After
     * [onFadeComplete] runs, volume is restored to the target so the next
     * play() starts from a known, full-volume state.
     *
     * No-ops into an immediate pause (volume snapped to target beforehand)
     * when a crossfade is active or [durationMs] <= 0, preserving instant
     * pause behavior in both cases.
     */
    fun fadeOutThenPause(player: ExoPlayer, durationMs: Long = FADE_OUT_MS, onFadeComplete: () -> Unit) {
        // Cancel any previous fade owned by this controller before reading
        // player.volume, so we always ramp from a value WE last set (or the
        // player's true current volume if nothing was in flight).
        cancel(player, resetVolume = false)

        val target = getTargetVolume().coerceIn(0f, 1f)
        if (isCrossfadeActive() || durationMs <= 0L) {
            onFadeComplete()
            player.volume = target
            return
        }

        val startVol = player.volume.coerceIn(0f, 1f)
        if (startVol <= 0.01f) {
            onFadeComplete()
            player.volume = target
            return
        }

        val steps  = (durationMs / FADE_STEP_MS).coerceAtLeast(1L).toInt()
        val stepMs = (durationMs / steps).coerceAtLeast(1L)
        var step   = 0

        val runnable = object : Runnable {
            override fun run() {
                if (isCrossfadeActive()) {
                    // Crossfade claimed volume ownership mid fade-out. Preserve
                    // the pre-existing (pre-fade) behavior of pausing
                    // immediately, but stop issuing any further volume writes
                    // of our own on this player.
                    fadeRunnable = null
                    isFading = false
                    onFadeComplete()
                    return
                }

                step++
                if (step >= steps) {
                    fadeRunnable = null
                    isFading = false
                    onFadeComplete()
                    // Restore to a known full-volume state now that the
                    // player is paused, so the next play() is never silent.
                    player.volume = target
                    return
                }

                player.volume = (startVol * (1f - step.toFloat() / steps.toFloat())).coerceIn(0f, startVol)
                handler.postDelayed(this, stepMs)
            }
        }
        fadeRunnable = runnable
        isFading = true
        handler.post(runnable)
        log("fadeOutThenPause: ${durationMs}ms, $steps steps, from=$startVol")
    }

    private fun log(msg: String) = NativeLogger.emit("verbose", "PlayPauseFade", msg)
}
