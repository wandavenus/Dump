part of '../lyrics_service.dart';

class LyricsService {
  static final Map<String, LyricsResult> _cache = {};
  static const _channel = MethodChannel('musicplayer/media_store');

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Ambil lirik: embedded tag → file .lrc lokal → internet.
  static Future<LyricsResult> fetchLyrics({
    required String title,
    required String artist,
    String? filePath,
  }) async {
    final key = '$artist|$title|${filePath ?? ''}';
    if (_cache.containsKey(key)) return _cache[key]!;

    // 1. Embedded tag dalam file audio (MP3/M4A/FLAC/OGG/WAV)
    if (filePath != null && filePath.isNotEmpty && !kIsWeb) {
      final embedded = await _getEmbeddedLyrics(filePath);
      if (embedded.isNotEmpty) {
        final result = LyricsResult(embedded, LyricsSource.embedded);
        _cache[key] = result;
        LogService.log('Lyrics', 'Embedded tag: $title');
        return result;
      }

      // 2. File .lrc di folder yang sama dengan file audio
      final sameDir = await _getLocalLrc(filePath, null);
      if (sameDir.isNotEmpty) {
        final result = LyricsResult(sameDir, LyricsSource.localFile);
        _cache[key] = result;
        LogService.log('Lyrics', 'Local .lrc same dir: $title');
        return result;
      }

      // 3. File .lrc di folder lirik yang dikonfigurasi user
      final configuredFolder = AudioEffectsService.lyricsPath.value;
      if (configuredFolder.isNotEmpty) {
        final folderLrc = await _getLocalLrc(filePath, configuredFolder);
        if (folderLrc.isNotEmpty) {
          final result = LyricsResult(folderLrc, LyricsSource.localFile);
          _cache[key] = result;
          LogService.log('Lyrics', 'Local .lrc folder: $title');
          return result;
        }
      }
    }

    // 4. Internet (lrclib.net)
    final internet = await _fetchFromInternet(title, artist);
    if (internet.isNotEmpty) {
      final result = LyricsResult(internet, LyricsSource.internet);
      _cache[key] = result;
      return result;
    }

    return const LyricsResult([], LyricsSource.none);
  }

  /// Bersihkan cache (panggil saat folder lirik berubah).
  static void clearCache() => _cache.clear();

  // ── 1. Embedded tag ───────────────────────────────────────────────────────

  static Future<List<LyricLine>> _getEmbeddedLyrics(String filePath) async {
    try {
      final raw = await _channel.invokeMethod<String>(
        'getEmbeddedLyrics',
        {'path': filePath},
      );
      if (raw == null || raw.trim().isEmpty) return [];
      return _parseLyricsString(raw.trim());
    } catch (_) {
      return [];
    }
  }

  // ── 2. File .lrc lokal ────────────────────────────────────────────────────

  static Future<List<LyricLine>> _getLocalLrc(
    String audioPath,
    String? overrideFolder,
  ) async {
    try {
      final nameNoExt = p.basenameWithoutExtension(audioPath);
      final folder = overrideFolder ?? p.dirname(audioPath);
      final lrcFile = File(p.join(folder, '$nameNoExt.lrc'));
      if (!await lrcFile.exists()) return [];
      final raw = await lrcFile.readAsString();
      return parseLrc(raw);
    } catch (_) {
      return [];
    }
  }

  // ── 3. Internet ───────────────────────────────────────────────────────────

  static Future<List<LyricLine>> _fetchFromInternet(
    String title,
    String artist,
  ) async {
    final prefKey = 'lyrics_${artist.trim()}|${title.trim()}';
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(prefKey);
      if (cached != null && cached.isNotEmpty) return parseLrc(cached);

      final normalArtist = artist.split(',').first.trim();
      final normalTitle = title.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

      String? raw = await _searchLrcLib(normalTitle, normalArtist);
      raw ??= await _searchLrcLib(title, artist);
      if (raw == null || raw.isEmpty) return [];

      await prefs.setString(prefKey, raw);
      LogService.log('Lyrics', 'Internet: $title');
      return parseLrc(raw);
    } catch (e) {
      LogService.warn('Lyrics', 'Internet error: $e');
      return [];
    }
  }

  static Future<String?> _searchLrcLib(String track, String artist) async {
    final uri = Uri.parse(
      'https://lrclib.net/api/search'
      '?track_name=${Uri.encodeComponent(track)}'
      '&artist_name=${Uri.encodeComponent(artist)}',
    );
    final response = await http
        .get(uri, headers: {'User-Agent': 'MusicPlayer/1.0'})
        .timeout(const Duration(seconds: 8));
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
    // Teks biasa: setiap baris = satu lyric line
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

  /// Parse format LRC [mm:ss.xx]teks — publik agar bisa dipakai di tempat lain.
  static List<LyricLine> parseLrc(String lrc) {
    final result = <LyricLine>[];
    for (final line in lrc.split('\n')) {
      final match =
          RegExp(r'^\[(\d+):(\d+(?:\.\d+)?)\](.*)$').firstMatch(line.trim());
      if (match == null) continue;
      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = double.tryParse(match.group(2) ?? '') ?? 0;
      final text = (match.group(3) ?? '').trim();
      result.add(LyricLine(
        timestamp: Duration(
          milliseconds: (((minutes * 60) + seconds) * 1000).round(),
        ),
        text: text,
      ));
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }
}
