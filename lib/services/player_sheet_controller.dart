import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

class PlayerSheetController {
  PlayerSheetController._();

  static final ValueNotifier<bool> expanded =
      ValueNotifier<bool>(false);

  static final ValueNotifier<double> progress =
      ValueNotifier<double>(0.0);

  static Timer? _timer;

  static void setProgress(double value) {
    _timer?.cancel();
    _setProgress(value);
  }

  static void _setProgress(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();

    if ((progress.value - clamped).abs() < 0.001) {
      return;
    }

    progress.value = clamped;

    if (clamped > 0 && !expanded.value) {
      expanded.value = true;
    } else if (clamped == 0 && expanded.value) {
      expanded.value = false;
    }
  }

  static double _easeOutCubic(double t) {
    final inverse = 1 - t;
    return 1 - (inverse * inverse * inverse);
  }

  static void _animateTo(double target) {
    _timer?.cancel();

    final start = progress.value;
    final distance = (target - start).abs();
    if (distance < 0.001) {
      _setProgress(target);
      return;
    }

    final duration = Duration(
      milliseconds: math.max(180, (360 * distance).round()),
    );
    final startedAt = DateTime.now();

    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      final t = (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
      final eased = _easeOutCubic(t);

      _setProgress(start + ((target - start) * eased));

      if (t >= 1.0) {
        _setProgress(target);
        timer.cancel();
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
