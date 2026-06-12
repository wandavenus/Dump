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
    final clamped = value.clamp(0.0, 1.0);

    progress.value = clamped;

    if (clamped > 0) {
      expanded.value = true;
    }

    if (clamped == 0) {
      expanded.value = false;
    }
  }

  static void _animateTo(double target) {
    _timer?.cancel();

    const step = 0.08;

    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final current = progress.value;

      if ((current - target).abs() <= step) {
        progress.value = target;

        if (target == 0) {
          expanded.value = false;
        } else {
          expanded.value = true;
        }

        timer.cancel();
        return;
      }

      progress.value += target > current ? step : -step;
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
