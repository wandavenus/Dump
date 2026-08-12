// ─── Equalizer parameter type ─────────────────────────────────────────────────

/// Immutable snapshot of the native equalizer's parameter space, as reported
/// by `android.media.audiofx.Equalizer` via [PlaybackManager].
class EqualizerParameters {
  final double minDecibels;
  final double maxDecibels;
  final int bandCount;

  /// Center frequency (Hz) of each band, in band order. May be shorter than
  /// [bandCount] or empty when the engine did not report frequencies (e.g.
  /// before the first audio session) — callers should fall back to a
  /// standard 5-band frequency set in that case.
  final List<int> centerFrequenciesHz;

  const EqualizerParameters({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bandCount,
    this.centerFrequenciesHz = const [],
  });
}
