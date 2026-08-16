part of '../log_service.dart';

/// Subscribes to the native Android log EventChannel and forwards every event
/// to [LogService] so native Media3 / MainActivity logs appear in the log viewer.
class NativeLogBridge {
  NativeLogBridge._();

  static const EventChannel _channel = EventChannel('musicplayer/native_logs');
  static StreamSubscription<dynamic>? _sub;

  static void init() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _sub = _channel.receiveBroadcastStream().listen((dynamic event) {
      if (event is! Map) return;
      final level = event['level'] as String? ?? 'info';
      final category = event['category'] as String? ?? 'Native';
      final message = event['message'] as String? ?? '';
      if (message.isEmpty) return;
      // L-1 fix: native 'debug' (10 Kotlin emit sites) used to fall through to
      // INFO, so the in-app level filter could never separate debug detail from
      // normal info. Map it to verbose — the "show everything" mode — so
      // verbose-only logging surfaces it and errors-only hides it, matching the
      // intent of the native level.
      final logLevel = switch (level) {
        'error' => LogLevel.error,
        'warn' => LogLevel.warning,
        'verbose' || 'debug' => LogLevel.verbose,
        _ => LogLevel.info,
      };
      LogService.log(category, message, level: logLevel);
    }, onError: (_) {});
  }

  static void dispose() {
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _sub = null;
  }
}
