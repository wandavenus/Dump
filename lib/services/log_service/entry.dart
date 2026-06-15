part of '../log_service.dart';

class LogEntry {
  final DateTime timestamp;
  final String category;
  final String message;
  final LogLevel level;
  final Map<String, dynamic>? extra;
  final Duration? elapsed;

  const LogEntry({
    required this.timestamp,
    required this.category,
    required this.message,
    this.level = LogLevel.info,
    this.extra,
    this.elapsed,
  });

  String get timestampMs {
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.$ms';
  }

  @override
  String toString() {
    final elapsedStr = elapsed != null ? ' [+${elapsed!.inMilliseconds}ms]' : '';
    final extraStr =
        (extra != null && extra!.isNotEmpty) ? ' $extra' : '';
    return '[$timestampMs] [${level.prefix}] [$category] $message$elapsedStr$extraStr';
  }
}
