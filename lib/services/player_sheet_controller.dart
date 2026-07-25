import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Thin adapter that drives the player bottom sheet open/close animation.
///
/// Exposes two [ValueNotifier]s consumed by the player UI:
/// - [expanded] — whether the sheet is considered "open" (progress > 0).
/// - [progress] — animation progress in [0.0, 1.0]; drives the sheet drag handle,
///   mini-player opacity, and full-player slide-up transition.
///
/// All writes go through [setProgress] or the convenience helpers [open],
/// [close], [toggle]. The easeOutCubic Ticker in [_animateTo] handles smooth
/// programmatic transitions (e.g. tapping the mini-player).
///
/// Uses [SchedulerBinding.createTicker] so the animation fires in sync with
/// the display vsync — no drift between animation frames and screen refresh,
/// and it auto-pauses when the app is backgrounded.
class PlayerSheetController {
  PlayerSheetController._();

  static final ValueNotifier<bool> expanded = ValueNotifier<bool>(false);

  static final ValueNotifier<double> progress = ValueNotifier<double>(0.0);

  // Vsync-driven ticker replaces the old Timer.periodic approach.
  static Ticker? _ticker;
  static double _animStart = 0.0;
  static double _animTarget = 0.0;
  static int _animDurationMs = 300;

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
    _ticker?.dispose();
    _ticker = null;
  }

  static void _onTick(Duration elapsed) {
    final rawT =
        (elapsed.inMilliseconds / _animDurationMs).clamp(0.0, 1.0);

    // easeOutCubic: 1 - (1-t)^3
    final u = 1.0 - rawT;
    final eased = 1.0 - u * u * u;

    setProgress(_animStart + (_animTarget - _animStart) * eased);

    if (rawT >= 1.0) {
      setProgress(_animTarget);
      _ticker?.dispose();
      _ticker = null;
    }
  }

  static void _animateTo(double target) {
    _ticker?.dispose();
    _ticker = null;

    _animStart = progress.value;
    _animTarget = target;
    final distance = (_animTarget - _animStart).abs();
    _animDurationMs = (distance * 600).clamp(120.0, 600.0).toInt();

    _ticker = Ticker(_onTick);
    _ticker!.start();
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
