part of '../log_service.dart';

class LogService {
  LogService._();

  static const int _maxEntries = 5000;

  static final List<LogEntry> _logs = [];
  static final ValueNotifier<int> logCount = ValueNotifier(0);

  static final ValueNotifier<bool> loggingEnabled  = ValueNotifier(true);
  static final ValueNotifier<bool> errorsOnly       = ValueNotifier(false);
  static final ValueNotifier<bool> verboseEnabled   = ValueNotifier(false);

  // ── Init ────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    loggingEnabled.value  = prefs.getBool('log_enabled')      ?? true;
    errorsOnly.value      = prefs.getBool('log_errors_only')  ?? false;
    verboseEnabled.value  = prefs.getBool('log_verbose')      ?? false;
  }

  // ── Settings ────────────────────────────────────────────────────────────────

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

  static Future<void> setVerboseEnabled(bool value) async {
    verboseEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('log_verbose', value);
  }

  // ── Logging ─────────────────────────────────────────────────────────────────

  static void log(
    String category,
    String message, {
    LogLevel level = LogLevel.info,
    String? stackTrace,
  }) {
    if (!loggingEnabled.value) return;
    if (errorsOnly.value && level.index < LogLevel.warning.index) return;
    if (level == LogLevel.verbose && !verboseEnabled.value) return;

    final entry = LogEntry(
      timestamp:  DateTime.now(),
      category:   category,
      message:    message,
      level:      level,
      stackTrace: stackTrace,
    );

    if (_logs.length >= _maxEntries) _logs.removeAt(0);
    _logs.add(entry);
    logCount.value = _logs.length;

    if (kDebugMode) debugPrint(entry.toString());
  }

  static void verbose(String category, String message) =>
      log(category, message, level: LogLevel.verbose);

  static void warn(String category, String message) =>
      log(category, message, level: LogLevel.warning);

  static void error(String category, String message, {String? stackTrace}) =>
      log(category, message, level: LogLevel.error, stackTrace: stackTrace);

  // ── Query ───────────────────────────────────────────────────────────────────

  static List<LogEntry> getLogs({
    String? category,
    LogLevel? level,
    String? search,
  }) {
    return _logs.where((e) {
      if (category != null && e.category != category) return false;
      if (level != null && e.level != level) return false;
      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        if (!e.message.toLowerCase().contains(q) &&
            !e.category.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Sorted list of distinct categories seen so far.
  static List<String> getCategories() {
    final cats = _logs.map((e) => e.category).toSet().toList();
    cats.sort();
    return cats;
  }

  static List<LogEntry> getErrors()   => getLogs(level: LogLevel.error);
  static List<LogEntry> getWarnings() => getLogs(level: LogLevel.warning);

  // ── Count helpers ────────────────────────────────────────────────────────────

  static int countByLevel(LogLevel level) =>
      _logs.where((e) => e.level == level).length;

  // ── Clear ───────────────────────────────────────────────────────────────────

  static void clear() {
    _logs.clear();
    logCount.value = 0;
  }
}
