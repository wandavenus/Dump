import 'dart:async';
import 'package:flutter/foundation.dart';

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
