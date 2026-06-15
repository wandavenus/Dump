part of '../loudness_analyzer.dart';

/// Holds the loudness measurement for one audio track.
class LoudnessResult {
  /// Integrated loudness in LUFS (negative value; e.g. −18.5).
  final double lufs;

  /// RMS power in dBFS (negative; e.g. −20.1).
  final double rms;

  /// True peak in dBFS (negative or near 0; e.g. −1.2).
  final double truePeak;

  /// True when LUFS was estimated from RMS (less accurate).
  final bool isLufsEstimated;

  /// Where the data came from: 'lufs_native', 'rms_native', 'wav_dart', 'estimate'.
  final String source;

  const LoudnessResult({
    required this.lufs,
    required this.rms,
    required this.truePeak,
    required this.isLufsEstimated,
    required this.source,
  });

  // ── Gain calculation ──────────────────────────────────────────────────────

  static const double _targetLufs  = -14.0;
  static const double _peakCeiling = -1.0;   // dBFS hard ceiling

  /// Recommended gain in dB to reach [_targetLufs].
  /// Automatically reduces gain if it would push the peak above [_peakCeiling].
  double get recommendedGainDb {
    double gain = _targetLufs - lufs;
    final peakAfterGain = truePeak + gain;
    if (peakAfterGain > _peakCeiling) {
      gain -= (peakAfterGain - _peakCeiling); // back off to protect peak
    }
    return gain;
  }

  /// Gain in millibels (for Android LoudnessEnhancer).
  double get recommendedGainMb => recommendedGainDb * 100.0;

  /// Linear gain factor (for player.setVolume on non-Android).
  double get recommendedGainLinear =>
      math.pow(10.0, recommendedGainDb / 20.0).toDouble().clamp(0.0, 1.0);

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'lufs':            lufs,
    'rms':             rms,
    'truePeak':        truePeak,
    'isLufsEstimated': isLufsEstimated,
    'source':          source,
  };

  factory LoudnessResult.fromJson(Map<String, dynamic> j) => LoudnessResult(
    lufs:            (j['lufs']    as num).toDouble(),
    rms:             (j['rms']     as num).toDouble(),
    truePeak:        (j['truePeak'] as num).toDouble(),
    isLufsEstimated: j['isLufsEstimated'] as bool? ?? true,
    source:          j['source']   as String? ?? 'cached',
  );

  @override
  String toString() =>
      'LoudnessResult($source lufs=$lufs rms=$rms peak=$truePeak gain=${recommendedGainDb.toStringAsFixed(1)}dB)';
}
