part of '../log_service.dart';

class LogService {
  LogService._();

  static const int _maxEntries = 1000;
  static final List<LogEntry> _logs = [];
  static final ValueNotifier<int> logCount = ValueNotifier(0);

  static final ValueNotifier<bool> loggingEnabled = ValueNotifier(true);
  static final ValueNotifier<bool> errorsOnly     = ValueNotifier(false);
  static final ValueNotifier<bool> verboseEnabled = ValueNotifier(false);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    loggingEnabled.value = prefs.getBool('log_enabled')     ?? true;
    errorsOnly.value     = prefs.getBool('log_errors_only') ?? false;
    verboseEnabled.value = prefs.getBool('log_verbose')     ?? false;
  }

  static Future<void> setLoggingEnabled(bool value) async {
    loggingEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('log_enabled', value);
    if (!value) clear();
  }

  static Future<void> setErrorsOnly(bool value) async {
    errorsOnly.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('log_errors_only', value);
  }

  static Future<void> setVerbose(bool value) async {
    verboseEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('log_verbose', value);
  }

  static void log(
    String category,
    String message, {
    LogLevel level = LogLevel.info,
    Map<String, dynamic>? extra,
    Duration? elapsed,
  }) {
    if (!loggingEnabled.value) return;
    if (level == LogLevel.verbose && !verboseEnabled.value) return;
    if (level == LogLevel.debug   && !verboseEnabled.value) return;
    if (errorsOnly.value && level.index < LogLevel.warning.index) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      category:  category,
      message:   message,
      level:     level,
      extra:     extra,
      elapsed:   elapsed,
    );

    if (_logs.length >= _maxEntries) _logs.removeAt(0);
    _logs.add(entry);
    logCount.value = _logs.length;

    if (kDebugMode) debugPrint(entry.toString());
  }

  static void verbose(String category, String message,
      {Map<String, dynamic>? extra}) =>
      log(category, message, level: LogLevel.verbose, extra: extra);

  static void debug(String category, String message,
      {Map<String, dynamic>? extra}) =>
      log(category, message, level: LogLevel.debug, extra: extra);

  static void warn(String category, String message,
      {Map<String, dynamic>? extra}) =>
      log(category, message, level: LogLevel.warning, extra: extra);

  static void error(
    String category,
    String message, {
    Map<String, dynamic>? extra,
    StackTrace? stackTrace,
  }) {
    final msg = stackTrace != null
        ? '$message\n${stackTrace.toString().split('\n').take(6).join('\n')}'
        : message;
    log(category, msg, level: LogLevel.error, extra: extra);
  }

  static void perf(String category, String label, Duration elapsed) =>
      log(category, label, level: LogLevel.debug, elapsed: elapsed);

  static List<LogEntry> getLogs({String? category, LogLevel? minLevel}) {
    return _logs.where((e) {
      if (category != null && e.category != category) return false;
      if (minLevel != null && e.level.index < minLevel.index) return false;
      return true;
    }).toList();
  }

  static List<String> get categories {
    final seen   = <String>{};
    final result = <String>[];
    for (final e in _logs.reversed) {
      if (seen.add(e.category)) result.add(e.category);
    }
    return result.reversed.toList();
  }

  static List<LogEntry> getErrors()   => getLogs(minLevel: LogLevel.error);
  static List<LogEntry> getWarnings() => getLogs(minLevel: LogLevel.warning);

  static void clear() {
    _logs.clear();
    logCount.value = 0;
  }
}
