part of '../log_service.dart';

class LogService {
  LogService._();

  static const int _maxEntries = 5000;

  static final Queue<LogEntry> _logs = Queue<LogEntry>();
  static final ValueNotifier<int> logCount = ValueNotifier(0);

  /// Monotonic notification counter.
  ///
  /// [logCount] intentionally saturates at [_maxEntries]; using it as the
  /// "new log" signal made the log page stop refreshing once the ring buffer
  /// was full. Widgets that only need to know "something changed" should
  /// listen to this value instead.
  static final ValueNotifier<int> logRevision = ValueNotifier(0);
  static int _revision = 0;

  /// Collapses historical category aliases so the log filter stays compact
  /// without losing the detailed category names already present in messages.
  static const Map<String, String> _categoryAliases = <String, String>{
    'AppState': 'App',
    'AudioEffects': 'Audio',
    'AudioFocus': 'Audio',
    'AudioSession': 'Audio',
    'DeviceDsp': 'Audio',
    'MediaCap': 'Audio',
    'NativeDspBridge': 'Audio',
    'PlaybackManager': 'Audio',
    'Media3Bridge': 'Media3',
    'DeviceState': 'Device',
    'EmbeddedProvider': 'Lyrics',
    'FetchManager': 'Lyrics',
    'LocalFileProvider': 'Lyrics',
    'LoudnessResolver': 'ReplayGain',
    'ReplayGainApplicator': 'ReplayGain',
    'NativeModuleRegistry': 'Native',
    'SongMetadata': 'Metadata',
    'NativePaletteService': 'Palette',
    'LocalSongCard': 'UI',
    'NewMusicCell': 'UI',
    'AlbumsSection': 'UI',
    'SmartPlaylistCard': 'UI',
    'PlayShuffleButtons': 'UI',
    'fluid.frag': 'Shader',
  };

  static final ValueNotifier<bool> loggingEnabled = ValueNotifier(false);
  static final ValueNotifier<bool> errorsOnly = ValueNotifier(false);
  static final ValueNotifier<bool> verboseEnabled = ValueNotifier(false);
  static final ValueNotifier<bool> liveTailEnabled = ValueNotifier(true);
  static const MethodChannel _nativeLoggingChannel = MethodChannel(
    'musicplayer/logging',
  );

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
    liveTailEnabled.value = prefs.getBool('log_live_tail') ?? true;
    await _syncNativeLoggingEnabled(loggingEnabled.value);
    isInitialized = true;
  }

  // ── Settings ────────────────────────────────────────────────────────────────

  static Future<void> setLoggingEnabled(bool value) async {
    // Flip the in-memory/native gates before awaiting disk I/O so new log calls
    // stop immediately rather than waiting for SharedPreferences.
    loggingEnabled.value = value;
    if (!value) clear();
    await _syncNativeLoggingEnabled(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('log_enabled', value);
  }

  static Future<void> _syncNativeLoggingEnabled(bool value) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _nativeLoggingChannel.invokeMethod<void>('setEnabled', value);
    } on MissingPluginException {
      // The in-app Dart gate still applies if native logging is unavailable.
    } on PlatformException {
      // Never allow diagnostics wiring to interfere with playback/settings.
    }
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

  static Future<void> setLiveTailEnabled(bool value) async {
    liveTailEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('log_live_tail', value);
  }

  // ── Logging ─────────────────────────────────────────────────────────────────

  /// Console-only fallback for the narrow window before [init] has completed.
  /// Feature code must use [log]/[verbose]/[warn]/[error] so the entry reaches
  /// the in-app viewer and the level filters.
  static void debugPrintIfEnabled(String message) {
    if (!loggingEnabled.value) return;
    debugPrint(LogRedaction.apply(message));
  }

  /// Redacts absolute paths and URIs from [input].
  ///
  /// Call sites should still prefer passing a stable id (for example
  /// `song.id`) instead of a title, file path, or URI.
  static String redact(String input) => LogRedaction.apply(input);

  static void log(
    String category,
    String message, {
    LogLevel level = LogLevel.info,
    String? stackTrace,
  }) {
    if (!loggingEnabled.value) return;
    if (errorsOnly.value && level.index < LogLevel.warning.index) return;
    if (level == LogLevel.verbose && !verboseEnabled.value) return;

    final canonicalCategory = _categoryAliases[category] ?? category;
    final entry = LogEntry(
      timestamp: DateTime.now(),
      category: canonicalCategory,
      message: LogRedaction.apply(message),
      level: level,
      // L-7 fix: bound per-entry stack traces. Full Dart traces are often
      // 5–10 KB; with the 5000-entry ring buffer the worst case balloons to
      // tens of MB of retained strings. Keep the head (frames closest to the
      // throw site — the diagnostically useful part) and mark the cut.
      stackTrace: stackTrace == null
          ? null
          : _capStackTrace(LogRedaction.apply(stackTrace)),
    );

    _evictForNewEntry();
    _logs.add(entry);
    logCount.value = _logs.length;
    logRevision.value = ++_revision;

    if (kDebugMode) debugPrint(entry.toString());
  }

  /// Keeps warning/error entries longer than verbose/info noise.
  ///
  /// The previous implementation always removed the oldest entry, so a burst of
  /// verbose logs (lyrics retries, AutoMix analysis, slider changes) could push
  /// every diagnostic error out of the 5000-entry window.
  static void _evictForNewEntry() {
    if (_logs.length < _maxEntries) return;

    LogEntry? oldestLowPriority;
    for (final entry in _logs) {
      if (entry.level.index < LogLevel.warning.index) {
        oldestLowPriority = entry;
        break;
      }
    }

    if (oldestLowPriority != null) {
      _logs.remove(oldestLowPriority);
    } else {
      _logs.removeFirst();
    }
  }

  static void verbose(String category, String message) =>
      log(category, message, level: LogLevel.verbose);

  static void warn(String category, String message, {String? stackTrace}) =>
      log(category, message, level: LogLevel.warning, stackTrace: stackTrace);

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

  /// Plain-text export in the same format used by the copy action.
  static String exportText({
    String? category,
    LogLevel? level,
    String? search,
  }) {
    final buffer = StringBuffer();
    for (final entry in getLogs(
      category: category,
      level: level,
      search: search,
    )) {
      buffer.writeln(entry.toString());
    }
    return buffer.toString();
  }

  /// True while [entry] is still in the ring buffer (not yet evicted).
  /// L-5 fix: the log page prunes its expanded-stack-trace set with this so
  /// an expansion survives new log arrivals and is only dropped when the
  /// entry itself is evicted past the [_maxEntries] limit.
  static bool contains(LogEntry entry) => _logs.contains(entry);

  // ── Count helpers ────────────────────────────────────────────────────────────

  /// How many ring-buffer entries match [level], optionally restricted to the
  /// active [category] / [search] filters so the log page's per-level chips
  /// stay consistent with the filtered list (L-6 fix).
  static int countByLevel(LogLevel level, {String? category, String? search}) =>
      _logs.where((e) {
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
    logRevision.value = ++_revision;
  }
}
