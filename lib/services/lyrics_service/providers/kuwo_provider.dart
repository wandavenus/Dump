import 'dart:convert';

import '../../../services/log_service.dart';
import '../cancellation.dart';
import '../lrc_parser.dart';
import '../provider.dart';
import '../quality.dart';
import '../rate_limiter.dart';
import 'provider_http.dart';

/// Provider: Kuwo Music (酷我音乐).
///
/// Database lirik besar; mendukung synced LRC.
class KuwoProvider implements LyricsProvider {
  @override
  String get name => 'Kuwo';

  @override
  bool get isOnline => true;

  static const _searchUrl =
      'https://www.kuwo.cn/api/www/search/searchMusicBykeyWord'
      '?key={q}&pn=0&rn=5&mobi=1&reqId=&plat=web_www&httpsStatus=1';

  static const _lrcUrl =
      'https://m.kuwo.cn/newh5/singles/songinfoandlisten'
      '?musicId={id}&type=lrc&httpsStatus=1';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://www.kuwo.cn/',
    'Accept': 'application/json, text/plain, */*',
    'csrf': 'kkMf',
    'Cookie': 'kw_token=kkMf',
  };

  @override
  Future<LyricsProviderResult?> fetch(
    LyricsQuery query,
    CancellationToken cancelToken,
  ) async {
    if (ProviderRateLimiter.instance.isLimited(name)) return null;

    try {
      // 1. Cari lagu
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
      final list = searchData['data']?['list'];
      if (list == null || list is! List || list.isEmpty) return null;

      final musicId = list[0]['musicrid']?.toString() ?? list[0]['rid']?.toString() ?? '';
      if (musicId.isEmpty) return null;

      // Ambil hanya numeric ID
      final numericId = musicId.replaceAll(RegExp('[^0-9]'), '');
      if (numericId.isEmpty) return null;

      // 2. Ambil LRC
      final lrcUri = Uri.parse(
        _lrcUrl.replaceFirst('{id}', numericId),
      );
      final lrcResp = await ProviderHttp.get(
        lrcUri, name, cancelToken, headers: _headers,
      );
      if (lrcResp == null || lrcResp.statusCode != 200) return null;
      cancelToken.throwIfCancelled();

      final lrcData = jsonDecode(lrcResp.body);
      // Coba beberapa jalur response
      String? lrc = lrcData['data']?['lrclist'] is List
          ? _buildLrcFromList(lrcData['data']['lrclist'])
          : (lrcData['data']?['lrc'] as String?);

      if (lrc == null || lrc.trim().isEmpty) return null;

      final quality = LrcParser.detectQuality(lrc);
      final lines   = LrcParser.parseLrc(lrc);
      if (lines.isEmpty) return null;

      LogService.verbose(name, '${lines.length} lines [${quality.displayName}]');
      return LyricsProviderResult(
        lines: lines,
        quality: quality,
        providerName: 'Kuwo Music',
        isInternet: true,
        rawLrc: lrc,
      );
    } on CancelledException {
      return null;
    } catch (e) {
      LogService.verbose(name, 'Error: $e');
      return null;
    }
  }

  /// Kuwo kadang mengembalikan lirik sebagai array [{time, lineLyric}].
  String? _buildLrcFromList(dynamic list) {
    if (list is! List || list.isEmpty) return null;
    final buf = StringBuffer();
    for (final item in list) {
      final time = (item['time'] as num?)?.toDouble() ?? 0.0;
      final text = (item['lineLyric'] as String?) ?? '';
      if (text.isEmpty) continue;
      final min = (time ~/ 60).toString().padLeft(2, '0');
      final sec = (time % 60).toStringAsFixed(2).padLeft(5, '0');
      buf.writeln('[$min:$sec]$text');
    }
    return buf.isEmpty ? null : buf.toString();
  }
}
