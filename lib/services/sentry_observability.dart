import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

/// Low-volume, privacy-conscious Sentry breadcrumbs and failures for Noisegraph.
class SentryObservability {
  SentryObservability._();

  static void breadcrumb(
    String category,
    String message, {
    Map<String, dynamic>? data,
    SentryLevel level = SentryLevel.info,
  }) {
    if (!Sentry.isEnabled) return;
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: category,
          message: message,
          data: data,
          level: level,
        ),
      ),
    );
  }

  static Future<T> trace<T>(
    String name,
    Future<T> Function() operation,
  ) {
    if (!Sentry.isEnabled) return operation();
    return Sentry.startSpan<T>(name, (_) => operation());
  }

  static void captureException(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    if (!Sentry.isEnabled) return;
    breadcrumb(
      'app.failure',
      '$operation failed',
      level: SentryLevel.error,
      data: {'error_type': error.runtimeType.toString()},
    );
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }
}
