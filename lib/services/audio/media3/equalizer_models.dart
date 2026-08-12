import 'media3_playback_bridge.dart';

// ── Equalizer types ────────────────────────────────────────────────────────────
// Extracted from media3_playback_bridge.dart (Tier 1 split). The bridge
// re-exports this file, so existing importers of media3_playback_bridge.dart
// keep resolving these types unchanged.

class AndroidEqualizerParameters {
  final double minDecibels;
  final double maxDecibels;
  final List<AndroidEqualizerBand> bands;

  const AndroidEqualizerParameters({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bands,
  });
}

class AndroidEqualizerBand {
  final int index;

  /// Center frequency of this band in Hz, as reported by
  /// `android.media.audiofx.Equalizer.getCenterFreq(band)`.
  /// Falls back to 0 when not available (e.g., before first audio session).
  final int centerFrequencyHz;

  const AndroidEqualizerBand(this.index, {this.centerFrequencyHz = 0});

  Future<void> setGain(double gainDb) =>
      Media3PlaybackBridge.setEqualizerBandGain(index, gainDb);
}
