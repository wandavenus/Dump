part of '../log_service.dart';

class LogEntry {
  final DateTime timestamp;
  final String category;
  final String message;
  final LogLevel level;
  final String? stackTrace;

  const LogEntry({
    required this.timestamp,
    required this.category,
    required this.message,
    this.level = LogLevel.info,
    this.stackTrace,
  });

  /// HH:mm:ss.cc  (centiseconds — short but precise)
  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final cs = (timestamp.millisecond ~/ 10).toString().padLeft(2, '0');
    return '$h:$m:$s.$cs';
  }

  String get levelTag => switch (level) {
        LogLevel.verbose => 'VRB',
        LogLevel.info    => 'INF',
        LogLevel.warning => 'WRN',
        LogLevel.error   => 'ERR',
      };

  @override
  String toString() =>
      '[${timestamp.toIso8601String()}] [$levelTag] [$category] $message'
      '${stackTrace != null ? '\n$stackTrace' : ''}';
}
