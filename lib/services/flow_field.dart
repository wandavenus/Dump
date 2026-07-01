import 'fast_noise_lite.dart';

/// Samples a deterministic FastNoiseLite-backed vector field for ambient motion.
class FlowField {
  FlowField({required int seed})
    : _primary = FastNoiseLite(seed: seed)..frequency = 0.72,
      _secondary = FastNoiseLite(seed: seed ^ 0x6D2B79F5)..frequency = 0.46,
      _depth = FastNoiseLite(seed: seed ^ 0x1B873593)..frequency = 0.28;

  final FastNoiseLite _primary;
  final FastNoiseLite _secondary;
  final FastNoiseLite _depth;

  /// Returns a coherent sample at [timeSeconds] for a normalized field point.
  FlowFieldSample sample({
    required double x,
    required double y,
    required double timeSeconds,
  }) {
    final slowTime = timeSeconds * 0.018;
    final mediumTime = timeSeconds * 0.032;

    final vx = _primary.getNoise3(x + 11.7, y - 3.4, slowTime);
    final vy = _primary.getNoise3(x - 5.2, y + 9.8, slowTime + 17.0);
    final swirl = _secondary.getNoise3(x + vx, y + vy, mediumTime + 31.0);
    final lift = _secondary.getNoise3(
      x - vy * 0.7,
      y + vx * 0.7,
      mediumTime - 19.0,
    );
    final density = _depth.getNoise3(
      x + swirl * 0.5,
      y + lift * 0.5,
      slowTime + 53.0,
    );

    return FlowFieldSample(
      x: (vx * 0.58) + (swirl * 0.42),
      y: (vy * 0.62) + (lift * 0.38),
      rotation: (swirl - lift) * 0.5,
      depth: density,
    );
  }
}

/// A single coherent point sampled from a [FlowField].
class FlowFieldSample {
  const FlowFieldSample({
    required this.x,
    required this.y,
    required this.rotation,
    required this.depth,
  });

  final double x;
  final double y;
  final double rotation;
  final double depth;
}
