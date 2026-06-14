part of 'log_service.dart';

class LogService {
  LogService._();

  static const int _maxEntries = 500;

  static final List<LogEntry> _logs = [];
  static final ValueNotifier<int> logCount = ValueNotifier(0);

  /// Whether logging is enabled (persisted).
  static final ValueNotifier<bool> loggingEnabled = ValueNotifier(true);

  /// Whether only errors+warnings are kept (persisted).
  static final ValueNotifier<bool> errorsOnly = ValueNotifier(false);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    loggingEnabled.value = prefs.getBool('log_enabled') ?? true;
    errorsOnly.value = prefs.getBool('log_errors_only') ?? false;
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

  static void log(
    String category,
    String message, {
    LogLevel level = LogLevel.info,
  }) {
    if (!loggingEnabled.value) return;
    if (errorsOnly.value && level == LogLevel.info) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      category: category,
      message: message,
      level: level,
    );

    if (_logs.length >= _maxEntries) _logs.removeAt(0);
    _logs.add(entry);
    logCount.value = _logs.length;

    if (kDebugMode) debugPrint(entry.toString());
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

  static List<LogEntry> getErrors() => getLogs(level: LogLevel.error);
  static List<LogEntry> getWarnings() => getLogs(level: LogLevel.warning);

  static void clear() {
    _logs.clear();
    logCount.value = 0;
  }
}
