package dev.wndavenz.music.effects

import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.DefaultAudioSink

/**
 * [DefaultAudioSink.DefaultAudioProcessorChain] subclass that makes
 * [DefaultAudioSink]'s media-position accounting aware of the Signalsmith
 * Stretch time-stretch ratio.
 *
 * ── Root cause addressed ──────────────────────────────────────────────────────
 *
 * [DefaultAudioSink.applyMediaPositionParameters] (DefaultAudioSink.java:1689)
 * calls [DefaultAudioSink.DefaultAudioProcessorChain.getMediaDuration], which
 * ONLY queries [androidx.media3.common.audio.SonicAudioProcessor] (line 213):
 *
 *   public long getMediaDuration(long playoutDuration) {
 *     return sonicAudioProcessor.isActive()
 *         ? sonicAudioProcessor.getMediaDuration(playoutDuration)
 *         : playoutDuration;   // ← always here when PlaybackParameters = default
 *   }
 *
 * Custom processors passed in the [audioProcessors] vararg have NO contribution
 * path to this computation.  When Signalsmith Stretch runs at speed ≠ 1.0 it
 * changes the output frame count relative to input, but that ratio is invisible
 * to DefaultAudioSink's position machinery, causing two bugs:
 *
 *   Bug A — position drift: [DefaultAudioSink.getCurrentPositionUs] returns
 *     AudioTrack-head time scaled by the uncorrected (identity) chain, so
 *     [currentPositionUs] in DecoderAudioRenderer diverges from the actual
 *     media timeline proportionally to |speed − 1.0|.
 *
 *   Bug B — READY↔BUFFERING oscillation: [DefaultAudioSink.hasAudioOutputPendingData]
 *     compares writtenFrames (which are the Signalsmith-reduced output frames)
 *     against the AudioTrack head position.  At speed > 1.0 the AudioTrack drains
 *     writtenFrames faster than the decoder refills them, making hasPendingData()
 *     flip false before the next decoder chunk arrives, which toggles the renderer
 *     between READY and BUFFERING and causes the UI Play/Pause button to flicker.
 *
 * ── Fix ───────────────────────────────────────────────────────────────────────
 *
 * Override [getMediaDuration] to map the incoming playout duration through
 * [SignalsmithStretchAudioProcessor.getMediaDuration] first (which uses the
 * processor's accumulated input/output frame ratio — the same approach Sonic
 * uses with inputBytes/outputBytes), then pass the stretch-corrected value to
 * super for Sonic's own correction (a transparent no-op while ExoPlayer's
 * PlaybackParameters remain at their defaults of speed=1.0/pitch=1.0, which
 * TransportCommands enforces so Sonic never activates).
 *
 * Example (speed = 2.0):
 *   AudioTrack head: 0.5 s of playout elapsed
 *   stretchProcessor.getMediaDuration(0.5 s) → 1.0 s   (ratio: 2 N input / N output)
 *   super.getMediaDuration(1.0 s)            → 1.0 s   (Sonic inactive, identity)
 *   DefaultAudioSink.currentPositionUs       = 1.0 s   ✓
 *
 * Example (speed = 0.5):
 *   AudioTrack head: 2.0 s of playout elapsed
 *   stretchProcessor.getMediaDuration(2.0 s) → 1.0 s   (ratio: N input / 2 N output)
 *   super.getMediaDuration(1.0 s)            → 1.0 s   (Sonic inactive)
 *   DefaultAudioSink.currentPositionUs       = 1.0 s   ✓
 *
 * ── Why simpler fixes are insufficient ───────────────────────────────────────
 *
 * • Just overriding [SignalsmithStretchAudioProcessor.getDurationAfterProcessorApplied]:
 *   That method is called only in [AudioProcessingPipeline.flush] (seek/track-change
 *   time), NOT during steady-state playback.  It fixes seek-position accuracy but
 *   does not touch the real-time [getCurrentPositionUs] path.
 *
 * • Setting player.playbackParameters.speed = stretchSpeed so Sonic activates:
 *   Sonic would then re-process already-stretched audio, resulting in double
 *   time-stretch (4× stretch at 2× speed setting) — catastrophically wrong.
 *
 * • A UI-side position offset (Dart/Flutter):
 *   Does not fix Bug B (buffering oscillation), which is driven by native
 *   writtenFrames vs. AudioTrack head comparison entirely in DefaultAudioSink.
 */
@UnstableApi
class StretchAwareAudioProcessorChain(
    private val stretchProcessor: SignalsmithStretchAudioProcessor,
    vararg audioProcessors: AudioProcessor,
) : DefaultAudioSink.DefaultAudioProcessorChain(*audioProcessors) {

    /**
     * Maps AudioTrack playout duration → media timeline duration, incorporating
     * Signalsmith Stretch's actual accumulated I/O frame ratio.
     *
     * Invoked by [DefaultAudioSink.applyMediaPositionParameters] on every call to
     * [DefaultAudioSink.getCurrentPositionUs], which [DecoderAudioRenderer] calls
     * on every render tick to update [currentPositionUs].
     *
     * The correction is purely multiplicative — pitch-shift alone (speed = 1.0,
     * semitones ≠ 0) does not alter the frame count, so the ratio stays at 1.0
     * and this method is a transparent pass-through in that case.
     */
    override fun getMediaDuration(playoutDuration: Long): Long {
        // Step 1: undo Signalsmith's frame-count change (playout → media).
        val stretchCorrected = stretchProcessor.getMediaDuration(playoutDuration)
        // Step 2: pass through Sonic (inactive at default PlaybackParameters → identity).
        return super.getMediaDuration(stretchCorrected)
    }
}
