import 'dart:convert';

import '../../../services/log_service.dart';
import '../cancellation.dart';
import '../lrc_parser.dart';
import '../provider.dart';
import '../quality.dart';
import '../rate_limiter.dart';
import 'provider_http.dart';

/// Provider: NetEase Music (网易云音乐).
///
/// Mendukung Karaoke LRC (klyric) — word-timed untuk banyak lagu.
/// Cocok untuk musik China, K-Pop, dan artis internasional populer.
class NeteaseProvider implements LyricsProvider {
  @override
  String get name => 'NetEase';

  @override
  bool get isOnline => true;

  static const _searchUrl =
      'https://music.163.com/api/search/get?s={q}&type=1&offset=0&total=false&limit=5';
  static const _lyricUrl =
      'https://music.163.com/api/song/lyric?os=pc&id={id}&lv=-1&kv=-1&tv=-1';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://music.163.com/',
    'Accept': 'application/json, text/plain, */*',
  };

  @override
  Future<LyricsProviderResult?> fetch(
    LyricsQuery query,
    CancellationToken cancelToken,
  ) async {
    if (ProviderRateLimiter.instance.isLimited(name)) return null;

    try {
      // 1. Cari ID lagu
      final q = '${query.artist} ${query.title}'.trim();
      final searchUri = Uri.parse(
        _searchUrl.replaceFirst('{q}', Uri.encodeComponent(q)),
      );
      final searchResp = await ProviderHttp.get(
        searchUri, name, cancelToken, headers: _headers,
      );
      if (searchResp == null || searchResp.statusCode != 200) return null;
      cancelToken.throwIfCancelled();

      final searchData = jsonDecode(searchResp.body);
      final songs = searchData['result']?['songs'];
      if (songs == null || songs is! List || songs.isEmpty) return null;

      final songId = songs[0]['id'];
      if (songId == null) return null;

      // 2. Ambil lirik
      final lyricUri = Uri.parse(
        _lyricUrl.replaceFirst('{id}', songId.toString()),
      );
      final lyricResp = await ProviderHttp.get(
        lyricUri, name, cancelToken, headers: _headers,
      );
      if (lyricResp == null) return null;
      if (lyricResp.statusCode == 429) {
        ProviderRateLimiter.instance.markRateLimited(name);
        return null;
      }
      if (lyricResp.statusCode != 200) return null;
      cancelToken.throwIfCancelled();

      final lyricData = jsonDecode(lyricResp.body);

      // Pilih klyric (word-timed) → lrc (line-timed) → tlyric (terjemahan)
      final klyric = (lyricData['klyric']?['lyric'] as String?) ?? '';
      final lrc    = (lyricData['lrc']?['lyric']    as String?) ?? '';

      final raw = klyric.isNotEmpty ? klyric : lrc;
      if (raw.isEmpty) return null;

      final quality = LrcParser.detectQuality(raw);
      final lines   = LrcParser.parseLrc(raw);
      if (lines.isEmpty) return null;

      LogService.verbose(name, '${lines.length} lines [${quality.displayName}]');
      return LyricsProviderResult(
        lines: lines,
        quality: quality,
        providerName: 'NetEase Music',
        isInternet: true,
        rawLrc: raw,
      );
    } on CancelledException {
      return null;
    } catch (e) {
      LogService.verbose(name, 'Error: $e');
      return null;
    }
  }
}
