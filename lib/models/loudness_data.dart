enum LoudnessSource {
  replayGainTrack,
  replayGainAlbum,
  r128Track,
  r128Album,
  iTunNorm,
  embedded,
  none;

  String get label => switch (this) {
    LoudnessSource.replayGainTrack => 'ReplayGain (Track)',
    LoudnessSource.replayGainAlbum => 'ReplayGain (Album)',
    LoudnessSource.r128Track       => 'R128 (Track)',
    LoudnessSource.r128Album       => 'R128 (Album)',
    LoudnessSource.iTunNorm        => 'iTunNORM',
    LoudnessSource.embedded        => 'Embedded',
    LoudnessSource.none            => 'None',
  };
}

class LoudnessData {
  final double gainDb;
  final double? peakLinear;
  final LoudnessSource source;

  const LoudnessData({
    required this.gainDb,
    this.peakLinear,
    required this.source,
  });

  const LoudnessData.none()
      : gainDb      = 0.0,
        peakLinear  = null,
        source      = LoudnessSource.none;

  bool get hasData => source != LoudnessSource.none;

  double get gainMb => gainDb * 100.0;

  double safeGain({double preamp = 0.0}) {
    if (!hasData) return 0.0;
    var g = gainDb + preamp;
    if (peakLinear != null && peakLinear! > 0.0) {
      final maxGain = -20.0 * (peakLinear! > 0 ? _log10(peakLinear!) : 0.0);
      if (g > maxGain) g = maxGain;
    }
    return g.clamp(-24.0, 24.0).toDouble();
  }

  static double _log10(double x) => x > 0 ? (x == 1.0 ? 0.0 : _ln(x) / _ln(10)) : 0.0;
  static double _ln(double x) {
    if (x <= 0) return double.negativeInfinity;
    var result = 0.0;
    var n = (x - 1) / (x + 1);
    var term = n;
    for (var i = 1; i <= 100; i += 2) {
      result += term / i;
      term *= n * n;
    }
    return 2 * result;
  }

  @override
  String toString() =>
      'LoudnessData(gain=${gainDb.toStringAsFixed(2)} dB, '
      'peak=$peakLinear, source=${source.label})';
}
