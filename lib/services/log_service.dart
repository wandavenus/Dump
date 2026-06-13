import 'package:flutter/foundation.dart';

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
  String toString() =>
      '[${timestamp.toIso8601String()}] [$category] $message';
}

class LogService {
  LogService._();

  static final List<LogEntry> _logs = [];
  static final ValueNotifier<int> logCount = ValueNotifier(0);

  static void log(
    String category,
    String message, {
    LogLevel level = LogLevel.info,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      category: category,
      message: message,
      level: level,
    );
    _logs.add(entry);
    logCount.value = _logs.length;
    debugPrint(entry.toString());
  }

  static void warn(String category, String message) =>
      log(category, message, level: LogLevel.warning);

  static void error(String category, String message) =>
      log(category, message, level: LogLevel.error);

  static List<LogEntry> getLogs({String? category, LogLevel? level}) {
    return _logs.where((e) {
      if (category != null && e.category != category) return false;
      if (level != null && e.level != level) return false;
      return true;
    }).toList();
  }

  static void clear() {
    _logs.clear();
    logCount.value = 0;
  }
}
