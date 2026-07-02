/// A compact Dart port of FastNoiseLite-style value fractal noise.
///
/// The player background uses this class as the single procedural source for
/// deterministic, continuous motion. Values are normalized to roughly `-1..1`.
class FastNoiseLite {
  FastNoiseLite({int seed = 1337}) : this._(seed);

  FastNoiseLite._(this._seed);

  final int _seed;

  /// Input frequency applied before fractal sampling.
  double frequency = 0.01;

  /// Number of fractal octaves used for each sample.
  int octaves = 4;

  /// Amplitude multiplier between octaves.
  double gain = 0.5;

  /// Frequency multiplier between octaves.
  double lacunarity = 2.0;

  /// Returns deterministic 3D fractal value noise for the coordinate.
  double getNoise3(double x, double y, double z) {
    var sum = 0.0;
    var amp = 1.0;
    var ampSum = 0.0;
    var freq = frequency;

    for (var octave = 0; octave < octaves; octave++) {
      sum += _singleValue(x * freq, y * freq, z * freq, _seed + octave) * amp;
      ampSum += amp;
      amp *= gain;
      freq *= lacunarity;
    }

    return ampSum == 0 ? 0 : sum / ampSum;
  }

  static double _singleValue(double x, double y, double z, int seed) {
    final x0 = x.floor();
    final y0 = y.floor();
    final z0 = z.floor();
    final xs = _interp(x - x0);
    final ys = _interp(y - y0);
    final zs = _interp(z - z0);

    final x00 = _lerp(_hash(seed, x0, y0, z0), _hash(seed, x0 + 1, y0, z0), xs);
    final x10 = _lerp(
      _hash(seed, x0, y0 + 1, z0),
      _hash(seed, x0 + 1, y0 + 1, z0),
      xs,
    );
    final x01 = _lerp(
      _hash(seed, x0, y0, z0 + 1),
      _hash(seed, x0 + 1, y0, z0 + 1),
      xs,
    );
    final x11 = _lerp(
      _hash(seed, x0, y0 + 1, z0 + 1),
      _hash(seed, x0 + 1, y0 + 1, z0 + 1),
      xs,
    );
    return _lerp(_lerp(x00, x10, ys), _lerp(x01, x11, ys), zs);
  }

  static double _interp(double t) => t * t * t * (t * (t * 6 - 15) + 10);

  static double _lerp(double a, double b, double t) => a + ((b - a) * t);

  static double _hash(int seed, int x, int y, int z) {
    var hash = seed ^ (x * 0x27d4eb2d) ^ (y * 0x165667b1) ^ (z * 0x1b873593);
    hash = (hash ^ (hash >> 15)) * 0x85ebca6b;
    hash = (hash ^ (hash >> 13)) * 0xc2b2ae35;
    hash = hash ^ (hash >> 16);
    return ((hash & 0x7fffffff) / 0x3fffffff) - 1.0;
  }
}
