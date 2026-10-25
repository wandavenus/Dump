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


/// Matches Mornye's word-lift envelope. The full text segment uses the same
/// offset before and after the karaoke color sweep, preventing a stationary
/// dim glyph from showing through a raised highlighted glyph.
double lyricWordLift({
  required Duration position,
  required Duration start,
  required Duration end,
  required double fontSize,
}) {
  if (end <= start) return 0;

  final maxLift = (fontSize * 0.05).clamp(0.0, 2.0).toDouble();
  final elapsedMs = (position - start).inMicroseconds / 1000.0;
  final durationMs = (end - start).inMicroseconds / 1000.0;

  double ease(double value) {
    final t = value.clamp(0.0, 1.0).toDouble();
    return t * t * (3.0 - 2.0 * t);
  }

  // Begin moving slightly ahead of the color sweep, but use a broad envelope
  // so a 16 ms frame never produces a perceptible jump.
  final normalLift = ease((elapsedMs + 180.0) / 720.0);
  final heldStrength = ((durationMs - 1000.0) / 1500.0)
      .clamp(0.0, 1.0)
      .toDouble();
  if (heldStrength == 0 || durationMs <= 400) {
    return maxLift * normalLift;
  }

  final riseWindow = math.min(1200.0, (durationMs - 400.0) * 0.6);
  final rise = ease((elapsedMs - 400.0) / riseWindow);
  final settle = ease((durationMs - elapsedMs) / 600.0);
  return maxLift * (normalLift + 1.3 * heldStrength * rise * settle);
}

/// Blur used to push lines away from the active vocal focus.
double lyricFocusBlurSigma(int lineDistance) {
  if (lineDistance <= 0) return 0;
  if (lineDistance == 1) return 2.4;
  if (lineDistance == 2) return 3.6;
  return 4.8;
}
