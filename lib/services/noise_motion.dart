import 'dart:ui';

import 'flow_field.dart';

/// Immutable motion values applied to a cached artwork layer.
class NoiseMotion {
  /// Creates sampled transform and opacity values for one rendered layer.
  const NoiseMotion({
    required this.translation,
    required this.rotation,
    required this.scale,
    required this.opacity,
  });

  /// Pixel translation of the artwork texture.
  final Offset translation;

  /// Small rotation in radians.
  final double rotation;

  /// Uniform artwork scale.
  final double scale;

  /// Layer opacity.
  final double opacity;
}

/// Immutable configuration for converting flow field samples into layer motion.
class NoiseMotionConfig {
  /// Creates a motion configuration for one background layer.
  const NoiseMotionConfig({
    required this.origin,
    required this.translationExtent,
    required this.rotationExtent,
    required this.baseScale,
    required this.scaleExtent,
    required this.baseOpacity,
    this.opacityExtent = 0.0,
  });

  /// Stable sample origin for the layer, in virtual field coordinates.
  final Offset origin;

  /// Maximum translation in logical pixels on each axis.
  final Offset translationExtent;

  /// Maximum absolute rotation in radians.
  final double rotationExtent;

  /// Scale applied before noise modulation.
  final double baseScale;

  /// Maximum scale modulation around [baseScale].
  final double scaleExtent;

  /// Opacity applied before noise modulation.
  final double baseOpacity;

  /// Maximum opacity modulation around [baseOpacity].
  final double opacityExtent;
}

/// Converts [FlowField] samples into transform values for cached artwork.
class NoiseMotionSampler {
  /// Creates a sampler using [flowField].
  const NoiseMotionSampler(this.flowField);

  /// Shared procedural flow field.
  final FlowField flowField;

  /// Samples immutable motion values for a configured layer.
  NoiseMotion sample(NoiseMotionConfig config, double timeSeconds) {
    final vector = flowField.vectorAt(
      config.origin.dx,
      config.origin.dy,
      timeSeconds,
    );
    final rotation = flowField.scalarAt(
      config.origin.dx,
      config.origin.dy,
      timeSeconds,
      3.0,
    );
    final scale = flowField.scalarAt(
      config.origin.dx,
      config.origin.dy,
      timeSeconds,
      5.0,
    );
    final opacity = flowField.scalarAt(
      config.origin.dx,
      config.origin.dy,
      timeSeconds,
      7.0,
    );

    return NoiseMotion(
      translation: Offset(
        vector.dx * config.translationExtent.dx,
        vector.dy * config.translationExtent.dy,
      ),
      rotation: rotation * config.rotationExtent,
      scale: config.baseScale + scale * config.scaleExtent,
      opacity: (config.baseOpacity + opacity * config.opacityExtent).clamp(
        0.0,
        1.0,
      ),
    );
  }
}
