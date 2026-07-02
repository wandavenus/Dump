import 'fast_noise_lite.dart';

/// Samples a deterministic FastNoiseLite-backed vector field for ambient motion.
///
/// Three noise instances drive translation/rotation; a fourth independent
/// instance evolves at a much lower rate and is used exclusively for the
/// slow breathing-zoom signal so it never correlates with drift direction.
class FlowField {
  FlowField({required int seed})
    : _primary   = FastNoiseLite(seed: seed)..frequency = 0.48,
      _secondary = FastNoiseLite(seed: seed ^ 0x6D2B79F5)..frequency = 0.29,
      _depth     = FastNoiseLite(seed: seed ^ 0x1B873593)..frequency = 0.16,
      _breathe   = FastNoiseLite(seed: seed ^ 0x45612F3A)..frequency = 0.11;

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
    final slowTime   = timeSeconds * 0.012; // was 0.018
    final mediumTime = timeSeconds * 0.021; // was 0.032
    final breathTime = timeSeconds * 0.007; // very slow; purely for zoom pulse

    final vx    = _primary.getNoise3(x + 11.7, y - 3.4,  slowTime);
    final vy    = _primary.getNoise3(x -  5.2, y + 9.8,  slowTime  + 17.0);
    final swirl = _secondary.getNoise3(x + vx,  y + vy,  mediumTime + 31.0);
    final lift  = _secondary.getNoise3(
      x - vy * 0.7,
      y + vx * 0.7,
      mediumTime - 19.0,
    );
    final density = _depth.getNoise3(
      x + swirl * 0.5,
      y + lift  * 0.5,
      slowTime + 53.0,
    );
    // Breathing sample lives at a spatially separate point so it carries no
    // directional information and can modulate scale independently.
    final breathe = _breathe.getNoise3(x + 7.3, y - 4.1, breathTime + 3.7);

    return FlowFieldSample(
      x:       (vx    * 0.58) + (swirl * 0.42),
      y:       (vy    * 0.62) + (lift  * 0.38),
      rotation: (swirl - lift) * 0.5,
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
