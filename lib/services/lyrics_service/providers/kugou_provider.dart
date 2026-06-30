import 'dart:convert';

import '../../../services/log_service.dart';
import '../cancellation.dart';
import '../lrc_parser.dart';
import '../provider.dart';
import '../quality.dart';
import '../rate_limiter.dart';
import 'provider_http.dart';

/// Provider: Kugou Music (酷狗音乐).
///
/// Kugou memiliki database lirik yang sangat besar termasuk Enhanced LRC.
/// API pencarian → hash → download LRC.
class KugouProvider implements LyricsProvider {
  @override
  String get name => 'Kugou';

  @override
  bool get isOnline => true;

  static const _searchUrl =
      'https://mobilecdn.kugou.com/api/v3/search/song'
      '?format=json&keyword={q}&page=1&pagesize=8&showtype=1';

  static const _lyricSearchUrl =
      'https://lyrics.kugou.com/search'
      '?ver=1&man=yes&client=pc&keyword={q}&duration={dur}&hash={hash}';

  static const _lyricGetUrl =
      'https://lyrics.kugou.com/download'
      '?ver=1&client=pc&id={id}&accesskey={key}&fmt=lrc&charset=utf8';

  static const _headers = {
    'User-Agent': 'KuGou2012-3751',
    'Accept': 'application/json',
  };

  @override
  Future<LyricsProviderResult?> fetch(
    LyricsQuery query,
    CancellationToken cancelToken,
  ) async {
    if (ProviderRateLimiter.instance.isLimited(name)) return null;

    try {
      // 1. Cari lagu → ambil hash
      final q = '${query.artist} ${query.title}'.trim();
      final searchUri = Uri.parse(
        _searchUrl.replaceFirst('{q}', Uri.encodeComponent(q)),
      );
      final searchResp = await ProviderHttp.get(
        searchUri, name, cancelToken, headers: _headers,
      );
      if (searchResp == null || searchResp.statusCode == 429) {
        if (searchResp?.statusCode == 429) {
          ProviderRateLimiter.instance.markRateLimited(name);
        }
        return null;
      }
      if (searchResp.statusCode != 200) return null;
      cancelToken.throwIfCancelled();

      final searchData = jsonDecode(searchResp.body);
      final songs = searchData['data']?['info'];
      if (songs == null || songs is! List || songs.isEmpty) return null;

      final song = songs[0];
      final hash = (song['hash'] as String?) ?? '';
      final duration = (song['duration'] as num?)?.toInt() ?? 0;
      if (hash.isEmpty) return null;

      // 2. Cari entri lirik dengan hash + duration
      final lyricSearchUri = Uri.parse(
        _lyricSearchUrl
            .replaceFirst('{q}', Uri.encodeComponent(q))
            .replaceFirst('{dur}', (duration * 1000).toString())
            .replaceFirst('{hash}', hash),
      );
      final lyricSearchResp = await ProviderHttp.get(
        lyricSearchUri, name, cancelToken, headers: _headers,
      );
      if (lyricSearchResp == null || lyricSearchResp.statusCode != 200) return null;
      cancelToken.throwIfCancelled();

      final lyricSearchData = jsonDecode(lyricSearchResp.body);
      final candidates = lyricSearchData['candidates'];
      if (candidates == null || candidates is! List || candidates.isEmpty) return null;

      final candidate = candidates[0];
      final lyricId   = '${candidate['id'] ?? ''}';
      final accessKey = '${candidate['accesskey'] ?? ''}';
      if (lyricId.isEmpty || accessKey.isEmpty) return null;

      // 3. Download LRC
      final lyricGetUri = Uri.parse(
        _lyricGetUrl
            .replaceFirst('{id}', Uri.encodeComponent(lyricId))
            .replaceFirst('{key}', Uri.encodeComponent(accessKey)),
      );
      final lyricGetResp = await ProviderHttp.get(
        lyricGetUri, name, cancelToken, headers: _headers,
      );
      if (lyricGetResp == null || lyricGetResp.statusCode != 200) return null;
      cancelToken.throwIfCancelled();

      final lyricData = jsonDecode(lyricGetResp.body);
      final rawContent = lyricData['content'] as String?;
      if (rawContent == null || rawContent.isEmpty) return null;

      // Kugou mengembalikan content dalam base64
      String content;
      try {
        content = utf8.decode(base64Decode(rawContent));
      } catch (_) {
        content = rawContent;
      }

      final quality = LrcParser.detectQuality(content);
      final lines   = LrcParser.parseLrc(content);
      if (lines.isEmpty) return null;

      LogService.verbose(name, '${lines.length} lines [${quality.displayName}]');
      return LyricsProviderResult(
        lines: lines,
        quality: quality,
        providerName: 'Kugou Music',
        isInternet: true,
        rawLrc: content,
      );
    } on CancelledException {
      return null;
    } catch (e) {
      LogService.verbose(name, 'Error: $e');
      return null;
    }
  }
}
