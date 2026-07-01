import 'dart:math' as math;
import 'dart:ui';

import 'package:open_simplex_2/open_simplex_2.dart';

/// Immutable tuning values for the procedural FastNoiseLite-style flow field.
class FlowFieldConfig {
  /// Creates a configuration matching the OpenSimplex2 FBm profile used by the
  /// ambient player background.
  const FlowFieldConfig({
    this.seed = 730,
    this.octaves = 4,
    this.gain = 0.5,
    this.lacunarity = 2.0,
    this.frequency = 0.0025,
    this.timeScale = 18.0,
  });

  /// Deterministic seed used by the OpenSimplex2 generator.
  final int seed;

  /// Number of FBm octaves sampled per channel.
  final int octaves;

  /// Amplitude multiplier between FBm octaves.
  final double gain;

  /// Frequency multiplier between FBm octaves.
  final double lacunarity;

  /// Base spatial frequency; approximately FastNoiseLite's frequency value.
  final double frequency;

  /// Converts elapsed seconds into a slow-moving third noise dimension.
  final double timeScale;
}

/// Deterministic OpenSimplex2 FBm flow field for slow organic motion.
class FlowField {
  /// Creates a flow field backed by OpenSimplex2 noise.
  FlowField({this.config = const FlowFieldConfig()})
    : _noise = OpenSimplex2F(config.seed);

  /// FastNoiseLite-compatible OpenSimplex2/FBm configuration.
  final FlowFieldConfig config;

  final OpenSimplex2 _noise;

  /// Returns a two-dimensional vector in the range `[-1, 1]` for [x], [y], and
  /// continuous elapsed [timeSeconds].
  Offset vectorAt(double x, double y, double timeSeconds) {
    final z = timeSeconds * config.timeScale;
    return Offset(
      _fbm(x + 17.0, y - 31.0, z),
      _fbm(x - 113.0, y + 67.0, z + 41.0),
    );
  }

  /// Returns a scalar in the range `[-1, 1]` for [x], [y], and [timeSeconds].
  double scalarAt(double x, double y, double timeSeconds, double channel) {
    return _fbm(
      x + channel * 97.0,
      y - channel * 53.0,
      timeSeconds * config.timeScale + channel * 29.0,
    );
  }

  double _fbm(double x, double y, double z) {
    var frequency = config.frequency;
    var amplitude = 1.0;
    var total = 0.0;
    var normalization = 0.0;

    for (var octave = 0; octave < config.octaves; octave += 1) {
      total +=
          _noise.noise3XYBeforeZ(x * frequency, y * frequency, z * frequency) *
          amplitude;
      normalization += amplitude;
      amplitude *= config.gain;
      frequency *= config.lacunarity;
    }

    return (total / math.max(normalization, 0.0001)).clamp(-1.0, 1.0);
  }
}
