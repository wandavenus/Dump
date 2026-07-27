import 'dart:convert';

import '../../../services/log_service.dart';
import '../cancellation.dart';
import '../lrc_parser.dart';
import '../provider.dart';
import '../quality.dart';
import 'provider_http.dart';

/// Provider: Apple Music (word-timed "Syllable" lyrics).
///
/// Dua langkah, keduanya publik/gratis dan tanpa perlu akun/token apapun:
///   1. iTunes Search API (search.itunes.apple.com) — cari trackId Apple
///      Music berdasarkan judul+artis. Endpoint publik resmi Apple, tidak
///      butuh developer token.
///   2. lyrics.paxsenix.org — proxy publik yang mengambil lirik Apple Music
///      (endpoint `/apple-music/lyrics?id=`) menggunakan trackId tersebut.
///      Ini bukan API resmi Apple; jika proxy ini down/berubah, provider
///      akan gagal graceful (return null) seperti provider lain.
///
/// Kualitas: banyak lagu populer punya "Syllable" sync (word-timed),
/// setara dengan Enhanced LRC — dikonversi ke format inline `<mm:ss.xxx>`
/// agar kompatibel dengan [LrcParser] dan renderer ELRC yang sudah ada.
class AppleMusicProvider implements LyricsProvider {
  @override
  String get name => 'Apple Music';

  @override
  bool get isOnline => true;

  static const _searchUrl = 'https://itunes.apple.com/search';
  static const _lyricsUrl = 'https://lyrics.paxsenix.org/apple-music/lyrics';

  @override
  Future<LyricsProviderResult?> fetch(
    LyricsQuery query,
    CancellationToken cancelToken,
  ) async {
    try {
      final trackId = await _searchTrackId(query, cancelToken);
      if (trackId == null) return null;
      cancelToken.throwIfCancelled();

      final raw = await _fetchLyrics(trackId, cancelToken);
      if (raw == null) return null;

      final result = _parseSyllableJson(raw);
      if (result == null) {
        LogService.verbose(name, 'Empty/unparseable lyrics for id=$trackId');
      }
      return result;
    } on CancelledException {
      return null;
    } catch (e) {
      LogService.verbose(name, 'Error: $e');
      return null;
    }
  }

  // ── Step 1: cari trackId via iTunes Search API ──────────────────────────

  Future<int?> _searchTrackId(
    LyricsQuery query,
    CancellationToken cancelToken,
  ) async {
    final term = '${query.artist} ${query.title}'.trim();
    final uri = Uri.parse(_searchUrl).replace(queryParameters: {
      'term': term,
      'entity': 'song',
      'limit': '5',
    });

    final response = await ProviderHttp.get(uri, name, cancelToken);
    if (response == null) return null;
    if (response.statusCode != 200) return null;

    final data = ProviderHttp.asJsonMap(jsonDecode(response.body));
    final rawResults = data?['results'];
    final results =
        rawResults is List ? rawResults.cast<Object?>() : const <Object?>[];
    if (results.isEmpty) return null;

    final wantTitle = query.title.toLowerCase().trim();
    final wantArtist = query.artist.toLowerCase().trim();
    final wantDurationMs = query.durationMs;

    // Pilih hasil terbaik: cocokkan judul, lalu durasi jika tersedia.
    Map<String, dynamic>? best;
    int bestScore = -1;
    for (final entry in results) {
      final entryMap = ProviderHttp.asJsonMap(entry);
      if (entryMap == null) continue;
      final trackName =
          (entryMap['trackName'] as String? ?? '').toLowerCase();
      final artistName =
          (entryMap['artistName'] as String? ?? '').toLowerCase();
      final durationMs = entryMap['trackTimeMillis'] as int?;

      int score = 0;
      if (trackName == wantTitle) {
        score += 3;
      } else if (trackName.contains(wantTitle) || wantTitle.contains(trackName)) {
        score += 1;
      }
      if (artistName == wantArtist) {
        score += 3;
      } else if (artistName.contains(wantArtist) || wantArtist.contains(artistName)) {
        score += 1;
      }
      if (wantDurationMs != null && durationMs != null) {
        final diff = (durationMs - wantDurationMs).abs();
        if (diff < 3000) score += 2;
      }

      if (score > bestScore) {
        bestScore = score;
        best = entryMap;
      }
    }

    if (best == null || bestScore <= 0) return null;
    return best['trackId'] as int?;
  }

  // ── Step 2: ambil lirik via proxy paxsenix ───────────────────────────────

  Future<String?> _fetchLyrics(
    int trackId,
    CancellationToken cancelToken,
  ) async {
    final uri = Uri.parse(_lyricsUrl).replace(queryParameters: {
      'id': trackId.toString(),
    });

    final response = await ProviderHttp.get(uri, name, cancelToken);
    if (response == null) return null;
    if (response.statusCode != 200) return null;
    return response.body;
  }

  // ── Parsing: JSON "Syllable"/"Line" → LyricsProviderResult ─────────────

  LyricsProviderResult? _parseSyllableJson(String body) {
    final data = ProviderHttp.asJsonMap(jsonDecode(body));
    if (data == null) return null;
    if (data.containsKey('detail') || data.containsKey('error')) return null;

    final content = data['content'];
    final contentLines =
        content is List ? content.cast<Object?>() : const <Object?>[];
    if (contentLines.isEmpty) return null;

    final type = (data['type'] as String? ?? '').toLowerCase();
    final buf = StringBuffer();
    bool anyWordTiming = false;

    for (final line in contentLines) {
      final lineMap = ProviderHttp.asJsonMap(line);
      if (lineMap == null) continue;
      if (lineMap['background'] == true) continue; // lewati backing vocals

      final startMs = (lineMap['timestamp'] as num?)?.toInt();
      if (startMs == null) continue;

      final words = lineMap['text'];
      if (words is List && words.isNotEmpty && type == 'syllable') {
        buf.write('[${_msToTag(startMs)}]');
        for (int i = 0; i < words.length; i++) {
          final w = ProviderHttp.asJsonMap(words[i]);
          if (w == null) continue;
          final wordText = (w['text'] as String? ?? '');
          final wordStart = (w['timestamp'] as num?)?.toInt();
          if (wordText.isEmpty || wordStart == null) continue;
          buf.write('<${_msToTag(wordStart)}>$wordText');
          final part = w['part'] == true;
          if (!part && i < words.length - 1) buf.write(' ');
        }
        buf.writeln();
        anyWordTiming = true;
      } else {
        // Line-level saja: gabungkan seluruh teks kata jadi satu baris.
        final text = words is List
            ? words
                .map(ProviderHttp.asJsonMap)
                .whereType<Map<String, dynamic>>()
                .map((w) => w['text'] as String? ?? '')
                .where((t) => t.isNotEmpty)
                .join(' ')
            : (words is String ? words : '');
        if (text.isEmpty) continue;
        buf.writeln('[${_msToTag(startMs)}]$text');
      }
    }

    final raw = buf.toString();
    if (raw.trim().isEmpty) return null;

    // Kualitas ditentukan langsung dari tipe respons paxsenix — lebih andal
    // daripada heuristik LrcParser untuk lirik dengan sedikit baris.
    final quality = anyWordTiming
        ? LyricsQuality.wordTimedLrc
        : LyricsQuality.lineTimedLrc;

    final parsedLines = LrcParser.parseLrc(raw);
    if (parsedLines.isEmpty) return null;

    LogService.verbose(
      name,
      '${parsedLines.length} lines [${quality.displayName}]',
    );
    return LyricsProviderResult(
      lines: parsedLines,
      quality: quality,
      providerName: 'Apple Music',
      isInternet: true,
      rawLrc: raw,
    );
  }

  String _msToTag(int ms) {
    final min = ms ~/ 60000;
    final sec = (ms % 60000) / 1000.0;
    return '$min:${sec.toStringAsFixed(3).padLeft(6, '0')}';
  }
}
