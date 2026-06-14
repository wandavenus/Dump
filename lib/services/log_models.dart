part of 'log_service.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final String category;
  final String message;
  final LogLevel level;

  const LogEntry({
    required this.timestamp,
    required this.category,
    required this.message,
    this.level = LogLevel.info,
  });

  @override
  String toString() {
    final lvl = level == LogLevel.error
        ? 'ERR'
        : level == LogLevel.warning
            ? 'WRN'
            : 'INF';
    return '[${timestamp.toIso8601String()}] [$lvl] [$category] $message';
  }
}
