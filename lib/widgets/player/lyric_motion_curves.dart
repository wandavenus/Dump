import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' as physics;

/// Shared timings for the lyric focus and scroll motion.
const lyricFocusAnimationDuration = Duration(milliseconds: 420);
const lyricScrollAnimationDuration = Duration(milliseconds: 550);
const lyricRowMotionDuration = Duration(milliseconds: 800);

/// Critically damped spring: reaches the selected lyric smoothly without
/// the list overshooting its target.
final Curve lyricScrollSpringCurve = _LyricsScrollSpringCurve();

class _LyricsScrollSpringCurve extends Curve {
  const _LyricsScrollSpringCurve();

  static final physics.SpringSimulation _simulation =
      physics.SpringSimulation(
        physics.SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: 196,
          ratio: 1,
        ),
        0,
        1,
        0,
      );

  static final double _end = _simulation.x(
    lyricScrollAnimationDuration.inMicroseconds /
        Duration.microsecondsPerSecond,
  );

  @override
  double transformInternal(double t) {
    final progress = t.clamp(0.0, 1.0).toDouble();
    final seconds =
        progress *
        lyricScrollAnimationDuration.inMicroseconds /
        Duration.microsecondsPerSecond;
    return (_simulation.x(seconds) / _end).clamp(0.0, 1.0).toDouble();
  }
}

final physics.SpringSimulation _lyricFollowerSpring =
    physics.SpringSimulation(
      physics.SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: 121,
        ratio: 0.85,
      ),
      0,
      1,
      0,
    );

double _lyricFollowerProgress(double elapsedSeconds) {
  if (elapsedSeconds <= 0) return 0;
  return _lyricFollowerSpring.x(elapsedSeconds)
      .clamp(0.0, 1.0)
      .toDouble();
}

/// Returns a small transient offset for rows below the focus. The list's
/// spring leads, while following rows settle in with a distance-based delay.
/// This affects painting only and never changes lyric measurements.
double lyricStaggeredRowOffset({
  required double animationProgress,
  required double distance,
  required int rowsAfterFocus,
}) {
  if (rowsAfterFocus <= 0 || distance == 0) return 0;

  final progress = animationProgress.clamp(0.0, 1.0).toDouble();
  final elapsedSeconds =
      progress *
      lyricRowMotionDuration.inMicroseconds /
      Duration.microsecondsPerSecond;
  final scrollProgress = lyricScrollSpringCurve.transform(
    (elapsedSeconds /
            (lyricScrollAnimationDuration.inMicroseconds /
                Duration.microsecondsPerSecond))
        .clamp(0.0, 1.0)
        .toDouble(),
  );
  final delay = rowsAfterFocus.clamp(1, 6) * 0.035;
  final followingProgress = _lyricFollowerProgress(elapsedSeconds - delay);
  final boundedDistance = distance.clamp(-96.0, 96.0).toDouble();

  return boundedDistance * (scrollProgress - followingProgress);
}

/// Blur used to push lines away from the active vocal focus.
double lyricFocusBlurSigma(int lineDistance) {
  if (lineDistance <= 0) return 0;
  if (lineDistance == 1) return 2.4;
  if (lineDistance == 2) return 3.6;
  return 4.8;
}
