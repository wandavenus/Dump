part of '../log_service.dart';

class LogService {
  LogService._();

  static const int _maxEntries = 5000;

  static final Queue<LogEntry> _logs = Queue<LogEntry>();
  static final ValueNotifier<int> logCount = ValueNotifier(0);

  static final ValueNotifier<bool> loggingEnabled = ValueNotifier(false);
  static final ValueNotifier<bool> errorsOnly = ValueNotifier(false);
  static final ValueNotifier<bool> verboseEnabled = ValueNotifier(false);

  /// True setelah [init] selesai. Digunakan oleh zone handler di main()
  /// untuk memutuskan apakah aman memanggil [error] atau harus fallback
  /// ke debugPrint.
  static bool isInitialized = false;

  // ── Init ────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    loggingEnabled.value = prefs.getBool('log_enabled') ?? false;
    errorsOnly.value = prefs.getBool('log_errors_only') ?? false;
    verboseEnabled.value = prefs.getBool('log_verbose') ?? false;
    isInitialized = true;
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
      timestamp: DateTime.now(),
      category: category,
      message: message,
      level: level,
      // L-7 fix: bound per-entry stack traces. Full Dart traces are often
      // 5–10 KB; with the 5000-entry ring buffer the worst case balloons to
      // tens of MB of retained strings. Keep the head (frames closest to the
      // throw site — the diagnostically useful part) and mark the cut.
      stackTrace: stackTrace == null ? null : _capStackTrace(stackTrace),
    );

    if (_logs.length >= _maxEntries) _logs.removeFirst();
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

  static List<LogEntry> getErrors() => getLogs(level: LogLevel.error);
  static List<LogEntry> getWarnings() => getLogs(level: LogLevel.warning);

  /// True while [entry] is still in the ring buffer (not yet evicted).
  /// L-5 fix: the log page prunes its expanded-stack-trace set with this so
  /// an expansion survives new log arrivals and is only dropped when the
  /// entry itself is evicted past the [_maxEntries] limit.
  static bool contains(LogEntry entry) => _logs.contains(entry);

  // ── Count helpers ────────────────────────────────────────────────────────────

  /// How many ring-buffer entries match [level], optionally restricted to the
  /// active [category] / [search] filters so the log page's per-level chips
  /// stay consistent with the filtered list (L-6 fix).
  static int countByLevel(
    LogLevel level, {
    String? category,
    String? search,
  }) => _logs.where((e) {
    if (e.level != level) return false;
    if (category != null && e.category != category) return false;
    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      if (!e.message.toLowerCase().contains(q) &&
          !e.category.toLowerCase().contains(q)) {
        return false;
      }
    }
    return true;
  }).length;

  static const int _maxStackTraceChars = 3000;

  static String _capStackTrace(String trace) {
    if (trace.length <= _maxStackTraceChars) return trace;
    final dropped = trace.length - _maxStackTraceChars;
    return '${trace.substring(0, _maxStackTraceChars)}\n'
        '… [truncated, $dropped chars dropped]';
  }

  // ── Clear ───────────────────────────────────────────────────────────────────

  static void clear() {
    _logs.clear();
    logCount.value = 0;
  }
}
