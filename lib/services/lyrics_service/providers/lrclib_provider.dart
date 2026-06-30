import 'dart:convert';

import '../../../services/log_service.dart';
import '../cancellation.dart';
import '../lrc_parser.dart';
import '../provider.dart';
import '../quality.dart';
import '../rate_limiter.dart';
import 'provider_http.dart';

/// Provider: lrclib.net — sumber utama untuk lirik synced (gratis, open).
/// Mendukung Enhanced LRC (word-timed) untuk beberapa lagu.
class LrclibProvider implements LyricsProvider {
  @override
  String get name => 'LRCLIB';

  @override
  bool get isOnline => true;

  @override
  Future<LyricsProviderResult?> fetch(
    LyricsQuery query,
    CancellationToken cancelToken,
  ) async {
    if (ProviderRateLimiter.instance.isLimited(name)) {
      LogService.verbose(name, 'Rate limited — skip');
      return null;
    }

    final artist = query.artist.split(',').first.trim();
    final title = query.title.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

    // Coba normalised dulu, fallback ke original
    String? raw = await _search(title, artist, cancelToken);
    raw ??= await _search(query.title, query.artist, cancelToken);

    if (raw == null) return null;

    final quality = LrcParser.detectQuality(raw);
    final lines = LrcParser.parseLrc(raw);
    if (lines.isEmpty) return null;

    LogService.verbose(name, '${lines.length} lines [${quality.displayName}]');
    return LyricsProviderResult(
      lines: lines,
      quality: quality,
      providerName: 'LRCLIB',
      isInternet: true,
      rawLrc: raw,
    );
  }

  Future<String?> _search(
    String title,
    String artist,
    CancellationToken cancelToken,
  ) async {
    final uri = Uri.parse(
      'https://lrclib.net/api/search'
      '?track_name=${Uri.encodeComponent(title)}'
      '&artist_name=${Uri.encodeComponent(artist)}',
    );

    final response = await ProviderHttp.get(
      uri,
      name,
      cancelToken,
      headers: {
        'User-Agent': 'MusicPlayerApp/2.0 (github.com/user/musicplayer)',
      },
    );
    if (response == null) return null;
    if (response.statusCode == 429) {
      ProviderRateLimiter.instance.markRateLimited(name);
      return null;
    }
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    if (data is! List || data.isEmpty) return null;

    // Scan semua hasil: pilih Enhanced LRC terbaik → synced → plain
    String? bestWord;
    String? bestSynced;
    String? bestPlain;
    for (final entry in data) {
      final synced = (entry['syncedLyrics'] as String?) ?? '';
      final plain = (entry['lyrics'] as String?) ?? '';
      if (synced.isNotEmpty) {
        final q = LrcParser.detectQuality(synced);
        if (q == LyricsQuality.wordTimedLrc && bestWord == null) {
          bestWord = synced;
        } else {
          bestSynced ??= synced;
        }
      }
      if (plain.isNotEmpty && bestPlain == null) bestPlain = plain;
      if (bestWord != null) break;
    }
    final result = bestWord ?? bestSynced ?? bestPlain;
    return (result == null || result.isEmpty) ? null : result;
  }
}
