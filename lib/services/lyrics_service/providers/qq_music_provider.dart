import 'dart:convert';

import '../../../services/log_service.dart';
import '../cancellation.dart';
import '../lrc_parser.dart';
import '../provider.dart';
import '../quality.dart';
import '../rate_limiter.dart';
import 'provider_http.dart';

/// Provider: QQ Music (QQ音乐).
///
/// QQ Music mendukung Enhanced LRC melalui `lyric` field.
/// Memerlukan header Referer khusus.
class QQMusicProvider implements LyricsProvider {
  @override
  String get name => 'QQ Music';

  @override
  bool get isOnline => true;

  static const _searchUrl =
      'https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp'
      '?p=1&n=5&w={q}&format=json&aggr=1&cr=1&catZhida=1&lossless=0&sem=0&t=0&new_json=1';

  static const _lyricUrl =
      'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcgi'
      '?songmid={mid}&g_tk=5381&loginUin=0&hostUin=0&format=json'
      '&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://y.qq.com/',
    'Accept': 'application/json, text/plain, */*',
    'Origin': 'https://y.qq.com',
  };

  @override
  Future<LyricsProviderResult?> fetch(
    LyricsQuery query,
    CancellationToken cancelToken,
  ) async {
    if (ProviderRateLimiter.instance.isLimited(name)) return null;

    try {
      // 1. Cari lagu → songmid
      final q = '${query.artist} ${query.title}'.trim();
      final searchUri = Uri.parse(
        _searchUrl.replaceFirst('{q}', Uri.encodeComponent(q)),
      );
      final searchResp = await ProviderHttp.get(
        searchUri, name, cancelToken, headers: _headers,
      );
      if (searchResp == null) return null;
      if (searchResp.statusCode == 429) {
        ProviderRateLimiter.instance.markRateLimited(name);
        return null;
      }
      if (searchResp.statusCode != 200) return null;
      cancelToken.throwIfCancelled();

      final searchData = jsonDecode(searchResp.body);
      final songs = searchData['data']?['song']?['list'];
      if (songs == null || songs is! List || songs.isEmpty) return null;

      final songmid = songs[0]['songmid']?.toString() ?? '';
      if (songmid.isEmpty) return null;

      // 2. Ambil lirik
      final lyricUri = Uri.parse(
        _lyricUrl.replaceFirst('{mid}', Uri.encodeComponent(songmid)),
      );
      final lyricResp = await ProviderHttp.get(
        lyricUri, name, cancelToken, headers: _headers,
      );
      if (lyricResp == null || lyricResp.statusCode != 200) return null;
      cancelToken.throwIfCancelled();

      final lyricData = jsonDecode(lyricResp.body);
      // QQ Music mengembalikan lirik dalam base64
      String? b64 = lyricData['lyric'] as String?;
      if (b64 == null || b64.isEmpty) return null;

      String raw;
      try {
        raw = utf8.decode(base64Decode(b64));
      } catch (_) {
        raw = b64;
      }

      final quality = LrcParser.detectQuality(raw);
      final lines   = LrcParser.parseLrc(raw);
      if (lines.isEmpty) return null;

      LogService.verbose(name, '${lines.length} lines [${quality.displayName}]');
      return LyricsProviderResult(
        lines: lines,
        quality: quality,
        providerName: 'QQ Music',
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
