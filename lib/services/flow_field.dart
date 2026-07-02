import 'fast_noise_lite.dart';

/// Samples a deterministic FastNoiseLite-backed vector field for ambient motion.
///
/// Tuned for more noticeable movement while keeping motion smooth and organic.
class FlowField {
  FlowField({required int seed})
    : _primary = FastNoiseLite(seed: seed)..frequency = 0.72,
      _secondary = FastNoiseLite(seed: seed ^ 0x6D2B79F5)..frequency = 0.46,
      _depth = FastNoiseLite(seed: seed ^ 0x1B873593)..frequency = 0.24,
      _breathe = FastNoiseLite(seed: seed ^ 0x45612F3A)..frequency = 0.18;

  final FastNoiseLite _primary;
  final FastNoiseLite _secondary;
  final FastNoiseLite _depth;
  final FastNoiseLite _breathe;

  FlowFieldSample sample({
    required double x,
    required double y,
    required double timeSeconds,
  }) {
    // Faster evolution so movement is clearly visible.
    final slowTime = timeSeconds * 0.022;
    final mediumTime = timeSeconds * 0.040;
    final breathTime = timeSeconds * 0.014;

    final vx = _primary.getNoise3(
      x + 11.7,
      y - 3.4,
      slowTime,
    );

    final vy = _primary.getNoise3(
      x - 5.2,
      y + 9.8,
      slowTime + 17.0,
    );

    final swirl = _secondary.getNoise3(
      x + vx,
      y + vy,
      mediumTime + 31.0,
    );

    final lift = _secondary.getNoise3(
      x - vy * 0.8,
      y + vx * 0.8,
      mediumTime - 19.0,
    );

    final density = _depth.getNoise3(
      x + swirl * 0.7,
      y + lift * 0.7,
      slowTime + 53.0,
    );

    final breathe = _breathe.getNoise3(
      x + 7.3,
      y - 4.1,
      breathTime + 3.7,
    );

    return FlowFieldSample(
      x: (vx * 0.72) + (swirl * 0.55),
      y: (vy * 0.72) + (lift * 0.55),
      rotation: (swirl - lift) * 0.75,
      depth: density,
      breathe: breathe,
    );
  }
}

class FlowFieldSample {
  const FlowFieldSample({
    required this.x,
    required this.y,
    required this.rotation,
    required this.depth,
    required this.breathe,
  });

  final double x;
  final double y;
  final double rotation;
  final double depth;

  /// Independent slow oscillator in [-1, 1].
  final double breathe;
}
