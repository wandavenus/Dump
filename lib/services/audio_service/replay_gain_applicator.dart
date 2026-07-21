part of '../audio_service.dart';

/// Deep module — encapsulates all ReplayGain DSP decision logic.
///
/// Before this extraction, the gain selection, LoudnessNorm interaction,
/// preamp offsetting, and native DSP calls lived inline in
/// [AudioService._applyReplayGain] (~75 lines spread across [AudioService]).
/// Every caller had to know which [AudioEffectsService] notifiers to read
/// and which [PlaybackManager] methods to call — 4 notifiers × 3 call sites.
///
/// After this extraction:
///   * The public interface is a single method: [apply].
///   * All [AudioEffectsService] reads and [PlaybackManager] DSP calls are
///     hidden inside this module.
///   * [AudioService] passes only the two songs it already has in hand.
///   * Unit tests can exercise gain-selection logic by injecting a fake
///     [LoudnessSourceResolver] without touching the native DSP pipeline.
///
/// Fail-open contract (inherited from the original):
///   A ReplayGain failure is cosmetic — it must never block playback.
///   [apply] wraps its body in try/catch; callers need not add their own.
class _ReplayGainApplicator {
  _ReplayGainApplicator._();

  /// Apply the correct ReplayGain gain for [song] to the native DSP pipeline.
  ///
  /// [prevSong] is the predecessor track — used by [LoudnessSourceResolver]
  /// in [ReplayGainMode.auto] to decide album-gain vs. track-gain.
  ///
  /// This is a **fail-open** call: any exception is caught, logged, and
  /// swallowed so playback is never interrupted.
  static Future<void> apply(LocalSong song, {LocalSong? prevSong}) async {
    try {
      final mode = AudioEffectsService.replayGainMode.value;

      // ── Mode: Off ──────────────────────────────────────────────────────────
      if (mode == ReplayGainMode.off) {
        PlaybackManager.setNativeReplayGainBypass(true);
        return;
      }

      // ── Loudness Normalization is active ───────────────────────────────────
      //
      // When native EBU R128 normalization is running it acts as the dynamic
      // gain authority. Applying full ReplayGain on top would cause the
      // normalizer to continuously re-normalize an already-adjusted signal,
      // producing oscillating gain. Only the user's preamp offset is forwarded
      // so the normalizer sees the intentional level preference.
      if (AudioEffectsService.loudnessNormEnabled.value) {
        final preamp = AudioEffectsService.replayGainPreamp.value;
        if (preamp != 0.0) {
          PlaybackManager.setNativeReplayGain(
            gainDb: preamp,
            peakLinear: 0.0,
            useClippingProtection: false,
          );
          PlaybackManager.setNativeReplayGainBypass(false);
        } else {
          PlaybackManager.setNativeReplayGainBypass(true);
        }
        LogService.verbose(
          'ReplayGainApplicator',
          'Deferred to Loudness Norm'
          ' (preamp: ${preamp.toStringAsFixed(1)} dB)',
        );
        return;
      }

      // ── Resolve loudness metadata ──────────────────────────────────────────
      final data = await LoudnessSourceResolver.resolve(
        song:         song,
        mode:         mode,
        previousSong: prevSong,
      );

      if (!data.hasData) {
        PlaybackManager.setNativeReplayGainBypass(true);
        LogService.verbose(
          'ReplayGainApplicator',
          'No metadata for "${song.title}" — bypass',
        );
        return;
      }

      // ── Apply gain ─────────────────────────────────────────────────────────
      //
      // Pass raw gain + preamp to native: the C layer handles dB→linear
      // conversion and optional clipping protection atomically.
      // Clamped to [−24, +24] dB by the C processor.
      final preamp     = AudioEffectsService.replayGainPreamp.value;
      final useClip    = AudioEffectsService.clippingProtection.value;
      final gainDb     = data.gainDb + preamp;
      final peakLinear = data.peakLinear ?? 0.0;

      PlaybackManager.setNativeReplayGain(
        gainDb: gainDb,
        peakLinear: peakLinear,
        useClippingProtection: useClip,
      );
      PlaybackManager.setNativeReplayGainBypass(false);

      LogService.verbose(
        'ReplayGainApplicator',
        '"${song.title}": ${gainDb.toStringAsFixed(2)} dB '
        '(peak=${peakLinear > 0 ? peakLinear.toStringAsFixed(3) : "n/a"}, '
        'clip=$useClip, src=${data.source.label})',
      );
    } catch (e, st) {
      // Fail-open: never let a ReplayGain failure block playback.
      LogService.error(
        'ReplayGainApplicator',
        'Skipped (fail-open): $e',
        stackTrace: st.toString(),
      );
    }
  }
}
