import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// TEMPORARY startup instrumentation — added to diagnose the black-screen
/// hang reported after Phase 9 (app never reaches Home, no crash).
///
/// Unlike [LogService], this is always-on regardless of the "logging
/// enabled" runtime toggle — that toggle lives behind a Settings UI the user
/// can never reach if Home never renders, so it is useless for this bug.
/// Every line is emitted via BOTH `debugPrint` and `dart:developer` log so it
/// shows up in `adb logcat` under the `flutter` tag even in a release build
/// (this project has `minifyEnabled false`, so nothing here gets stripped).
///
/// Remove this file and every call site once the hang is fixed and confirmed
/// on-device.
class BootTrace {
  BootTrace._();

  static final Stopwatch _sw = Stopwatch()..start();

  static void log(String msg) {
    final ms = _sw.elapsedMilliseconds;
    final line = '[BOOT +${ms}ms] $msg';
    debugPrint(line);
    developer.log(line, name: 'BootTrace');
  }

  /// Wraps an async step with ENTER/EXIT (+elapsed) logs and prints any
  /// exception (with stack trace) before rethrowing — so a swallowed
  /// `catch (_) {}` upstream never hides where time was actually lost.
  static Future<T> step<T>(String name, Future<T> Function() body) async {
    log('ENTER $name');
    final sw = Stopwatch()..start();
    try {
      final result = await body();
      log('EXIT  $name (${sw.elapsedMilliseconds}ms)');
      return result;
    } catch (e, st) {
      log('EXCEPTION in $name after ${sw.elapsedMilliseconds}ms: $e\n$st');
      rethrow;
    }
  }
}
