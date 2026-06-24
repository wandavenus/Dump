part of '../lyrics_service.dart';

class LyricsService {
  static final Map<String, LyricsResult> _cache = {};
  static const _channel = MethodChannel('musicplayer/media_store');

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetch lyrics: embedded tag → same-dir .lrc → configured folder .lrc → internet.
  static Future<LyricsResult> fetchLyrics({
    required String title,
    required String artist,
    String? filePath,
  }) async {
    final key = '$artist|$title|${filePath ?? ''}';

    // Cache hit
    if (_cache.containsKey(key)) {
      final cached = _cache[key]!;
      LogService.verbose('Lyrics',
          'Cache hit: "$title" — ${cached.lines.length} lines (${cached.sourceLabel})');
      return cached;
    }

    final sw = Stopwatch()..start();
    LogService.log('Lyrics', 'Fetching: "$title" — $artist');

    // 1. Embedded tag in the audio file
    if (filePath != null && filePath.isNotEmpty && !kIsWeb) {
      final embedded = await _getEmbeddedLyrics(filePath);
      if (embedded.isNotEmpty) {
        final result = LyricsResult(embedded, LyricsSource.embedded);
        _cache[key] = result;
        LogService.log('Lyrics',
            'Found embedded tag: "$title" — ${embedded.length} lines (${sw.elapsedMilliseconds}ms)');
        return result;
      }

      // 2. .lrc in the same directory as the audio file
      final sameDir = await _getLocalLrc(filePath, null);
      if (sameDir.isNotEmpty) {
        final result = LyricsResult(sameDir, LyricsSource.localFile);
        _cache[key] = result;
        LogService.log('Lyrics',
            'Found same-dir .lrc: "$title" — ${sameDir.length} lines (${sw.elapsedMilliseconds}ms)');
        return result;
      }

      // 3. .lrc in the user-configured lyrics folder
      final configuredFolder = AudioEffectsService.lyricsPath.value;
      if (configuredFolder.isNotEmpty) {
        final folderLrc = await _getLocalLrc(filePath, configuredFolder);
        if (folderLrc.isNotEmpty) {
          final result = LyricsResult(folderLrc, LyricsSource.localFile);
          _cache[key] = result;
          LogService.log('Lyrics',
              'Found folder .lrc: "$title" — ${folderLrc.length} lines (${sw.elapsedMilliseconds}ms)');
          return result;
        }
      }
    }

    // 4. Internet (lrclib.net)
    LogService.verbose('Lyrics', 'Trying internet for "$title" — $artist');
    final internet = await _fetchFromInternet(title, artist);
    if (internet.isNotEmpty) {
      final result = LyricsResult(internet, LyricsSource.internet);
      _cache[key] = result;
      LogService.log('Lyrics',
          'Internet lyrics found: "$title" — ${internet.length} lines (${sw.elapsedMilliseconds}ms)');
      return result;
    }

    LogService.warn('Lyrics',
        'Not found: "$title" — $artist (${sw.elapsedMilliseconds}ms searched)');
    return const LyricsResult([], LyricsSource.none);
  }

  /// Clear cache (call when lyrics folder path changes).
  static void clearCache() {
    final count = _cache.length;
    _cache.clear();
    LogService.verbose('Lyrics', 'Cache cleared ($count entries removed)');
  }

  // ── 1. Embedded tag ───────────────────────────────────────────────────────

  static Future<List<LyricLine>> _getEmbeddedLyrics(String filePath) async {
    try {
      final raw = await _channel.invokeMethod<String>(
        'getEmbeddedLyrics',
        {'path': filePath},
      );
      if (raw == null || raw.trim().isEmpty) return [];
      final lines = _parseLyricsString(raw.trim());
      LogService.verbose('Lyrics', 'Embedded tag read: ${lines.length} lines from $filePath');
      return lines;
    } catch (e) {
      LogService.verbose('Lyrics', 'Embedded tag error: $e');
      return [];
    }
  }

  // ── 2. Local .lrc file ────────────────────────────────────────────────────

  static Future<List<LyricLine>> _getLocalLrc(
    String audioPath,
    String? overrideFolder,
  ) async {
    try {
      final nameNoExt = p.basenameWithoutExtension(audioPath);
      final folder = overrideFolder ?? p.dirname(audioPath);
      final lrcPath = p.join(folder, '$nameNoExt.lrc');
      final lrcFile = File(lrcPath);
      if ((await lrcFile.stat()).type == FileSystemEntityType.notFound) { // ignore: avoid_slow_async_io
        LogService.verbose('Lyrics', 'No .lrc at: $lrcPath');
        return [];
      }
      final raw = await lrcFile.readAsString();
      final lines = parseLrc(raw);
      LogService.verbose('Lyrics', 'Read .lrc: $lrcPath — ${lines.length} lines');
      return lines;
    } catch (e) {
      LogService.verbose('Lyrics', 'Local .lrc read error: $e');
      return [];
    }
  }

  // ── 3. Internet (lrclib.net) ──────────────────────────────────────────────

  static Future<List<LyricLine>> _fetchFromInternet(
    String title,
    String artist,
  ) async {
    final prefKey = 'lyrics_${artist.trim()}|${title.trim()}';
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(prefKey);
      if (cached != null && cached.isNotEmpty) {
        final lines = parseLrc(cached);
        LogService.verbose('Lyrics',
            'SharedPrefs cache hit for "$title" — ${lines.length} lines');
        return lines;
      }

      final normalArtist = artist.split(',').first.trim();
      final normalTitle  = title.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

      LogService.verbose('Lyrics',
          'lrclib.net query: "$normalTitle" — "$normalArtist"');

      String? raw = await _searchLrcLib(normalTitle, normalArtist);
      raw ??= await _searchLrcLib(title, artist);

      if (raw == null || raw.isEmpty) {
        LogService.verbose('Lyrics', 'lrclib.net: no result for "$title"');
        return [];
      }

      await prefs.setString(prefKey, raw);
      final lines = parseLrc(raw);
      LogService.log('Lyrics',
          'lrclib.net success: "$title" — ${lines.length} synced lines');
      return lines;
    } catch (e) {
      LogService.warn('Lyrics', 'Internet fetch error: $e');
      return [];
    }
  }

  static Future<String?> _searchLrcLib(String track, String artist) async {
    final uri = Uri.parse(
      'https://lrclib.net/api/search'
      '?track_name=${Uri.encodeComponent(track)}'
      '&artist_name=${Uri.encodeComponent(artist)}',
    );
    final sw = Stopwatch()..start();
    final response = await http
        .get(uri, headers: {'User-Agent': 'MusicPlayer/1.0'})
        .timeout(const Duration(seconds: 8));
    LogService.verbose('Lyrics',
        'lrclib.net HTTP ${response.statusCode} in ${sw.elapsedMilliseconds}ms');
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is! List || data.isEmpty) return null;
    final synced =
        (data.first['syncedLyrics'] ?? data.first['lyrics'] ?? '') as String;
    return synced.isEmpty ? null : synced;
  }

  // ── Parser ────────────────────────────────────────────────────────────────

  static List<LyricLine> _parseLyricsString(String raw) {
    if (RegExp(r'^\[\d+:\d+', multiLine: true).hasMatch(raw)) {
      return parseLrc(raw);
    }
    // Plain text: each line is a lyric line with a 4-second offset
    int offset = 0;
    return raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) {
          final line = LyricLine(
            timestamp: Duration(seconds: offset * 4),
            text: l,
          );
          offset++;
          return line;
        })
        .toList();
  }

  /// Parse LRC format — public so it can be reused elsewhere.
  ///
  /// Handles:
  ///   • Standard:            `[mm:ss.xx]text`
  ///   • No centiseconds:     `[mm:ss]text`
  ///   • Multi-timestamp:     `[mm:ss.xx][mm:ss.xx]text` → two LyricLines
  ///   • Metadata tags:       `[ti:]`, `[ar:]`, `[al:]`, `[by:]`, `[offset:]` → skipped
  ///   • Inline karaoke times:`<mm:ss.xx>` inside the text → stripped
  ///   • Empty text lines:    skipped (keep list clean)
  ///   • Windows line endings: `\r\n` → handled by trim()
  static List<LyricLine> parseLrc(String lrc) {
    // Regex for a single [mm:ss] or [mm:ss.xx] or [mm:ss.xxx] timestamp.
    final tsRe = RegExp(r'\[(\d+):(\d+(?:[.,]\d+)?)\]');

    // Known metadata prefixes — skip these lines entirely.
    final metaRe = RegExp(
      r'^\[(?:ti|ar|al|by|offset|length|re|ve|total|author|created)\s*:',
      caseSensitive: false,
    );

    // Inline karaoke word-timings like <01:23.45> — strip from text.
    final inlineRe = RegExp(r'<\d+:\d+(?:[.,]\d+)?>');

    final result = <LyricLine>[];

    for (final rawLine in lrc.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (metaRe.hasMatch(line)) continue;

      // Collect all leading timestamps.
      final List<Duration> timestamps = [];
      int cursor = 0;
      for (final m in tsRe.allMatches(line)) {
        // Only accept timestamps that appear before any non-timestamp text.
        // A timestamp embedded mid-text (karaoke) is handled by inlineRe strip below.
        if (m.start > cursor && line.substring(cursor, m.start).trim().isNotEmpty) break;
        final min = int.tryParse(m.group(1) ?? '') ?? 0;
        // Accept both '.' and ',' as decimal separator (regional LRC variants).
        final secStr = (m.group(2) ?? '').replaceAll(',', '.');
        final sec    = double.tryParse(secStr) ?? 0;
        timestamps.add(Duration(milliseconds: ((min * 60 + sec) * 1000).round()));
        cursor = m.end;
      }

      if (timestamps.isEmpty) continue;

      // Text is everything after the last leading timestamp, with inline timings stripped.
      final rawText = line.substring(cursor).replaceAll(inlineRe, '').trim();
      if (rawText.isEmpty) continue;

      for (final ts in timestamps) {
        result.add(LyricLine(timestamp: ts, text: rawText));
      }
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }
}
