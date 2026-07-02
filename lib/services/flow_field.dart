import 'fast_noise_lite.dart';

/// Samples a deterministic FastNoiseLite-backed vector field for ambient motion.
///
/// Three noise instances drive translation/rotation; a fourth independent
/// instance evolves at a much lower rate and is used exclusively for the
/// slow breathing-zoom signal so it never correlates with drift direction.
class FlowField {
  FlowField({required int seed})
    : _primary   = FastNoiseLite(seed: seed)..frequency = 0.72,
      _secondary = FastNoiseLite(seed: seed ^ 0x6D2B79F5)..frequency = 0.46,
      _depth     = FastNoiseLite(seed: seed ^ 0x1B873593)..frequency = 0.28,
      _breathe   = FastNoiseLite(seed: seed ^ 0x45612F3A)..frequency = 0.18;

  final FastNoiseLite _primary;
  final FastNoiseLite _secondary;
  final FastNoiseLite _depth;
  final FastNoiseLite _breathe; // independent channel — drives scale breathing only

  /// Returns a coherent sample at [timeSeconds] for a normalised field point.
  FlowFieldSample sample({
    required double x,
    required double y,
    required double timeSeconds,
  }) {
    // Slower temporal rates → the field evolves like fog, not turbulent smoke.
    final slowTime   = timeSeconds * 0.006; // was 0.018
    final mediumTime = timeSeconds * 0.010; // was 0.032
    final breathTime = timeSeconds * 0.003; // very slow; purely for zoom pulse

    final warpX = vx * 1.8;
final warpY = vy * 1.8;

final swirl = _secondary.getNoise3(
  x + warpX,
  y + warpY,
  mediumTime + 31.0,
);

final lift = _secondary.getNoise3(
  x - warpY,
  y + warpX,
  mediumTime - 19.0,
);
    final lift  = _secondary.getNoise3(
      x - vy * 0.7,
      y + vx * 0.7,
      mediumTime - 19.0,
    );
    final density = _depth.getNoise3(
  x + warpX + swirl,
  y + warpY + lift,
  slowTime + 53.0,
);
    // Breathing sample lives at a spatially separate point so it carries no
    // directional information and can modulate scale independently.
    final breathe = _breathe.getNoise3(x + 7.3, y - 4.1, breathTime + 3.7);

    return FlowFieldSample(
      x: (vx * 0.30) + (swirl * 0.70),
y: (vy * 0.30) + (lift * 0.70),
      rotation: (swirl - lift) * 1.10,
      depth:   density,
      breathe: breathe,
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
    required this.breathe,
  });

  final double x;
  final double y;
  final double rotation;
  final double depth;
  /// Independent slow oscillator in [−1, 1] — use for scale breathing only.
  final double breathe;
}
