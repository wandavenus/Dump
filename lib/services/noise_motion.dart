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
      timeSeconds: t,
    );

    // Companion drift — spatially and temporally de-correlated from [sample]
    // so the two layers move on independent trajectories (parallax).
    final companion = _flowField.sample(
      x: layer.fieldX + 29.3,
      y: layer.fieldY - 21.7,
      timeSeconds: t * 0.61, // was 0.73 — less correlated
    );

    // Breathing sample — used only for scale modulation; never touches tx/ty.
    // Evolves at 0.31× with a large spatial offset so it is structurally
    // uncorrelated with both [sample] and [companion].
    final breath = _flowField.sample(
      x: layer.fieldX - 41.0,
      y: layer.fieldY + 33.5,
      timeSeconds: t * 0.31 + 7.9,
    );

    // --- Translation ----------------------------------------------------------
    // Y is damped slightly relative to X (× 0.82 / × 0.22) for a natural
    // horizontal-dominant drift that matches how fog moves across a surface.
    final tx =
        (sample.x    * layer.translationRadius) +
        (companion.x * layer.translationRadius * 0.28);
    final ty =
        (sample.y    * layer.translationRadius * 0.82) +
        (companion.y * layer.translationRadius * 0.22);

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
      translation: Offset(tx, ty),
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
    translationRadius: 36.0,   // was 122 — slow fog drift, not a camera shake
    rotationRange:      0.004, // was 0.022 — nearly invisible
    baseScale:          1.32,  // was 1.84 — still covers edges at max drift
    scaleRange:         0.011, // ≈ 1.1 % breathing
    baseOpacity:        0.22,
    opacityRange:       0.045,
    minimumOpacity:     0.17,
    maximumOpacity:     0.29,
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
    translationRadius: 24.0,   // was 72 — moves less than back → clear parallax
    rotationRange:      0.003, // was 0.017
    baseScale:          1.22,  // was 1.43
    scaleRange:         0.009, // ≈ 0.9 % breathing
    baseOpacity:        0.88,
    opacityRange:       0.055,
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
