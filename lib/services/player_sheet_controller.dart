import 'dart:async';
import 'package:flutter/foundation.dart';

/// Thin adapter that drives the player bottom sheet open/close animation.
///
/// Exposes two [ValueNotifier]s consumed by the player UI:
/// - [expanded] — whether the sheet is considered "open" (progress > 0).
/// - [progress] — animation progress in [0.0, 1.0]; drives the sheet drag handle,
///   mini-player opacity, and full-player slide-up transition.
///
/// All writes go through [setProgress] or the convenience helpers [open],
/// [close], [toggle]. The easeOutCubic timer in [_animateTo] handles smooth
/// programmatic transitions (e.g. tapping the mini-player).
///
/// This class sits on top of [PlayerSheetController] (the legacy controller
/// that owns the draggable sheet) and is the sole public API for the rest of
/// the app; the underlying sheet widget subscribes directly to [progress].
class PlayerSheetController {
  PlayerSheetController._();

  static final ValueNotifier<bool> expanded =
      ValueNotifier<bool>(false);

  static final ValueNotifier<double> progress =
      ValueNotifier<double>(0.0);

  static Timer? _timer;

  static void setProgress(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    progress.value = clamped;
    if (clamped > 0 && !expanded.value) {
      expanded.value = true;
    } else if (clamped == 0 && expanded.value) {
      expanded.value = false;
    }
  }

  static void cancelAnimation() {
    _timer?.cancel();
    _timer = null;
  }

  static void _animateTo(double target) {
    _timer?.cancel();

    final startValue = progress.value;
    final startMs = DateTime.now().millisecondsSinceEpoch;
    final distance = (target - startValue).abs();
    final durationMs = (distance * 400).clamp(80.0, 400.0).toInt();

    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
      final rawT = (elapsed / durationMs).clamp(0.0, 1.0);

      // easeOutCubic: 1 - (1-t)^3
      final u = 1.0 - rawT;
      final eased = 1.0 - u * u * u;

      setProgress(startValue + (target - startValue) * eased);

      if (rawT >= 1.0) {
        setProgress(target);
        timer.cancel();
        _timer = null;
      }
    });
  }

  static void open() {
    expanded.value = true;
    _animateTo(1.0);
  }

  static void close() {
    _animateTo(0.0);
  }

  static void toggle() {
    if (expanded.value) {
      close();
    } else {
      open();
    }
  }
}
