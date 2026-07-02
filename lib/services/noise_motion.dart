import 'dart:ui';

import 'flow_field.dart';

/// Produces transform and opacity values for a blurred artwork layer.
///
/// Motion model:
///   • [sample]    — primary drift at the layer's own field coordinate + time.
///   • [companion] — secondary drift sampled at a well-separated spatial point
///                   and a different time rate (0.61×) so the two layers never
///                   move in sync even when their field coords are close.
///   • [breath]    — dedicated sample used only for scale; evolves at 0.31×
///                   and a distinct spatial offset, giving the subtle breathing
///                   zoom its own independent rhythm.
class NoiseMotion {
  NoiseMotion({required FlowField flowField}) : this._(flowField);

  const NoiseMotion._(this._flowField);

  final FlowField _flowField;

  /// Generates ambient layer motion. Rendering widgets apply this value only.
  NoiseMotionFrame frameFor({
    required NoiseMotionLayer layer,
    required double timeSeconds,
  }) {
    final t = timeSeconds + layer.timeOffset;

    // Primary drift — owns the bulk of the translation.
    final sample = _flowField.sample(
    x: layer.fieldX,
    y: layer.fieldY,
    timeSeconds: t * (layer == NoiseMotionLayer.deepBackground ? 0.7 : 1.15),
    );

    // Companion drift — spatially and temporally de-correlated from [sample]
    // so the two layers move on independent trajectories (parallax).
    final companion = _flowField.sample(
    x: layer.fieldX + 29.3,
    y: layer.fieldY - 21.7,
    timeSeconds: t * (layer == NoiseMotionLayer.deepBackground ? 0.55 : 1.35),
    );

    // Breathing sample — used only for scale modulation; never touches tx/ty.
    // Evolves at 0.31× with a large spatial offset so it is structurally
    // uncorrelated with both [sample] and [companion].
    final breath = _flowField.sample(
      x: layer.fieldX - 41.0,
      y: layer.fieldY + 33.5,
      timeSeconds: t * 0.45 + 7.9,
    );

    // --- Translation ----------------------------------------------------------
    // Y is damped slightly relative to X (× 0.82 / × 0.22) for a natural
    // horizontal-dominant drift that matches how fog moves across a surface.
    final tx =
    ((sample.x * 0.70) + (companion.x * 0.30)) *
    layer.translationRadius;

    final ty =
    ((sample.y * 0.70) + (companion.y * 0.30)) *
    layer.translationRadius;
    // --- Rotation -------------------------------------------------------------
    // Kept extremely subtle — full-screen rotation is very distracting.
    final rot =
        (sample.rotation    * layer.rotationRange) +
        (companion.rotation * layer.rotationRange * 0.25);

    // --- Scale (breathing zoom) -----------------------------------------------
    // [breath.breathe] drives the primary oscillation independently of drift.
    // [sample.depth] adds a small secondary texture so it is not perfectly
    // periodic, but its contribution is weighted down to 40 %.
    final scale =
        layer.baseScale +
        (breath.breathe * layer.scaleRange) +
        (sample.depth   * layer.scaleRange * 0.40);

    // --- Opacity --------------------------------------------------------------
    final opacity =
        (layer.baseOpacity + (sample.depth * layer.opacityRange)).clamp(
          layer.minimumOpacity,
          layer.maximumOpacity,
        );

    return NoiseMotionFrame(
      translation: Offset(
      tx + (sample.rotation * layer.translationRadius * 0.18),
      ty + (companion.rotation * layer.translationRadius * 0.18),
      ),
      rotation: rot,
      scale: scale,
      opacity: opacity,
    );
  }
}

/// Configuration for one procedural background layer.
class NoiseMotionLayer {
  const NoiseMotionLayer({
    required this.fieldX,
    required this.fieldY,
    required this.timeOffset,
    required this.translationRadius,
    required this.rotationRange,
    required this.baseScale,
    required this.scaleRange,
    required this.baseOpacity,
    required this.opacityRange,
    required this.minimumOpacity,
    required this.maximumOpacity,
  });

  /// Deep, slow-moving ambient background layer.
  ///
  /// Geometry notes:
  ///   translationRadius 36 px → max compound offset ≈ 48 px (×1.34 factor).
  ///   baseScale 1.32 → 64 px margin each side on a 400 px screen — safe.
  ///   scaleRange 0.011 → ±1.1 % breathing zoom from [breath] channel.
  ///   rotationRange 0.004 rad ≈ 0.23° — imperceptible on a full-screen image.
  static const deepBackground = NoiseMotionLayer(
    fieldX:            -8.0,
    fieldY:            12.0,
    timeOffset:         0.0,
    translationRadius: 72.0,
    rotationRange:    0.008,
    baseScale:         1.20,
    scaleRange:       0.025,
    baseOpacity:       0.30,
    opacityRange:     0.08,
    minimumOpacity:    0.17,
    maximumOpacity:    0.29,
  );

  /// Lighter foreground fog layer — moves faster to create parallax depth.
  ///
  /// Geometry notes:
  ///   translationRadius 24 px → max compound offset ≈ 32 px.
  ///   baseScale 1.22 → 44 px margin each side on a 400 px screen — safe.
  ///   scaleRange 0.009 → ±0.9 % breathing (slightly less than back layer).
  ///   rotationRange 0.003 rad ≈ 0.17° — imperceptible.
  static const foregroundFog = NoiseMotionLayer(
    fieldX:            15.0,
    fieldY:            -6.0,
    timeOffset:        41.0,   // large phase offset ensures no sync with back
    translationRadius: 48.0,
    rotationRange: 0.007,
    baseScale: 1.14,
    scaleRange: 0.020,
    baseOpacity:        0.95,
    opacityRange:       0.04,
    minimumOpacity:     0.80,
    maximumOpacity:     0.96,
  );

  final double fieldX;
  final double fieldY;
  final double timeOffset;
  final double translationRadius;
  final double rotationRange;
  final double baseScale;
  final double scaleRange;
  final double baseOpacity;
  final double opacityRange;
  final double minimumOpacity;
  final double maximumOpacity;
}

/// Render-ready transform values generated by [NoiseMotion].
class NoiseMotionFrame {
  const NoiseMotionFrame({
    required this.translation,
    required this.rotation,
    required this.scale,
    required this.opacity,
  });

  final Offset translation;
  final double rotation;
  final double scale;
  final double opacity;
}
