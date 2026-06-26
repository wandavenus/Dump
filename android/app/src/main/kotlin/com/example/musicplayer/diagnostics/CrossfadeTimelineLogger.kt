package com.example.musicplayer.diagnostics

import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.events.NativeLogger

/**
 * Shared epoch clock for crossfade dropout diagnosis.
 *
 * Every instrumentation site calls [stamp] to emit a log line that includes:
 *   • milliseconds since crossfade started (relative — easier to diff than wall time)
 *   • wall-clock ms (absolute — to correlate with system audio traces)
 *   • calling thread name
 *   • full ExoPlayer state snapshot (state, pos, pwr, session, index)
 *
 * Usage:
 *   1. Call [begin] once when CrossfadeController.beginCrossfade() starts.
 *   2. Call [stamp] at every subsequent operation that might touch the audio pipeline.
 *   3. Call [end] after onCrossfadeComplete() finishes — this resets the epoch so
 *      a subsequent crossfade gets a fresh zero reference.
 *
 * All methods are thread-safe (volatile epoch, no locks needed — worst case a race
 * on [begin]/[end] produces a slightly wrong relative time, which is acceptable for
 * a diagnostic tool).
 */
@UnstableApi
object CrossfadeTimelineLogger {

    private const val TAG = "CrossfadeTimeline"

    @Volatile private var epochMs: Long = 0L
    @Volatile private var active: Boolean = false

    /**
     * Mark the start of a crossfade.  Sets the relative-time epoch to now.
     * Call this as the very first thing inside beginCrossfade().
     */
    fun begin(label: String = "") {
        epochMs = System.currentTimeMillis()
        active  = true
        val thread = Thread.currentThread().name
        NativeLogger.emit("info", TAG,
            "═══ CROSSFADE BEGIN  wall=${epochMs}ms  thread=$thread  $label ═══")
    }

    /**
     * Emit a timestamped step with a full player-state snapshot.
     *
     * @param label  Short description of the operation (e.g. "setMediaItems START").
     * @param player Optional ExoPlayer whose state is captured at this instant.
     *               Pass null when no player context is available.
     */
    fun stamp(label: String, player: ExoPlayer? = null) {
        val wall    = System.currentTimeMillis()
        val rel     = if (active) wall - epochMs else -1L
        val thread  = Thread.currentThread().name

        val state   = player?.let { stateStr(it.playbackState) } ?: "n/a"
        val pos     = player?.currentPosition ?: -1L
        val pwr     = player?.playWhenReady   ?: false
        val idx     = player?.currentMediaItemIndex ?: -1
        val session = player?.audioSessionId  ?: 0

        NativeLogger.emit("info", TAG,
            "[+${rel}ms | wall=${wall}ms] $label" +
            " | thread=$thread" +
            " | state=$state pos=${pos}ms pwr=$pwr idx=$idx session=$session")
    }

    /**
     * Emit a timestamped step without a player reference (pure timing marker).
     */
    fun stamp(label: String) = stamp(label, null)

    /**
     * Emit a step for an operation that involves TWO players simultaneously
     * (e.g. the moment both players are audible during fade).
     */
    fun stampDual(label: String, newPlayer: ExoPlayer?, oldPlayer: ExoPlayer?) {
        val wall    = System.currentTimeMillis()
        val rel     = if (active) wall - epochMs else -1L
        val thread  = Thread.currentThread().name

        val nState  = newPlayer?.let { stateStr(it.playbackState) } ?: "n/a"
        val nPos    = newPlayer?.currentPosition ?: -1L
        val nPwr    = newPlayer?.playWhenReady   ?: false
        val nSession= newPlayer?.audioSessionId  ?: 0

        val oState  = oldPlayer?.let { stateStr(it.playbackState) } ?: "n/a"
        val oPos    = oldPlayer?.currentPosition ?: -1L
        val oPwr    = oldPlayer?.playWhenReady   ?: false
        val oSession= oldPlayer?.audioSessionId  ?: 0

        NativeLogger.emit("info", TAG,
            "[+${rel}ms | wall=${wall}ms] $label" +
            " | thread=$thread" +
            " | NEW(state=$nState pos=${nPos}ms pwr=$nPwr session=$nSession)" +
            " | OLD(state=$oState pos=${oPos}ms pwr=$oPwr session=$oSession)")
    }

    /**
     * Mark the end of the crossfade diagnostic window.
     * Call after all onCrossfadeComplete() sub-operations finish.
     */
    fun end(label: String = "") {
        val wall = System.currentTimeMillis()
        val rel  = if (active) wall - epochMs else -1L
        val thread = Thread.currentThread().name
        NativeLogger.emit("info", TAG,
            "═══ CROSSFADE END  [+${rel}ms | wall=${wall}ms]  thread=$thread  $label ═══")
        active  = false
        epochMs = 0L
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun stateStr(state: Int) = when (state) {
        Player.STATE_IDLE      -> "IDLE"
        Player.STATE_BUFFERING -> "BUFFERING"
        Player.STATE_READY     -> "READY"
        Player.STATE_ENDED     -> "ENDED"
        else                   -> "UNKNOWN($state)"
    }
}
