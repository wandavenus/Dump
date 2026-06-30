import 'dart:convert';

import '../../../services/log_service.dart';
import '../cancellation.dart';
import '../lrc_parser.dart';
import '../provider.dart';
import '../quality.dart';
import '../rate_limiter.dart';
import 'provider_http.dart';

/// Provider: Musixmatch.
///
/// Musixmatch memiliki word-level synced lyrics ("Rich Sync") untuk
/// banyak lagu internasional. Menggunakan API unofficial dengan token
/// yang bisa diambil dari aplikasi desktop.
///
/// Jika tidak ada token, provider ini dilewati secara graceful.
class MusixmatchProvider implements LyricsProvider {
  /// Token Musixmatch (opsional). Jika null/empty, provider dilewati.
  final String? userToken;

  const MusixmatchProvider({this.userToken});

  @override
  String get name => 'Musixmatch';

  @override
  bool get isOnline => true;

  static const _richSyncUrl =
      'https://apic-desktop.musixmatch.com/ws/1.1/macro.subtitles.get'
      '?format=json&namespace=lyrics_richsynced'
      '&app_id=web-desktop-app-v1.0'
      '&usertoken={token}'
      '&q_artist={artist}'
      '&q_track={title}'
      '&q_duration={dur}'
      '&tags=playing&subtitle_format=mxm';

  static const _subtitleUrl =
      'https://apic-desktop.musixmatch.com/ws/1.1/macro.subtitles.get'
      '?format=json&namespace=lyrics_synced'
      '&app_id=web-desktop-app-v1.0'
      '&usertoken={token}'
      '&q_artist={artist}'
      '&q_track={title}'
      '&q_duration={dur}'
      '&subtitle_format=lrc';

  static const _headers = {
    'User-Agent': 'MusicPlayer/2.0',
    'Accept': 'application/json',
    'authority': 'apic-desktop.musixmatch.com',
    'Cookie': 'AWSELBCORS=0; AWSELB=0',
  };

  @override
  Future<LyricsProviderResult?> fetch(
    LyricsQuery query,
    CancellationToken cancelToken,
  ) async {
    final token = userToken?.trim() ?? '';
    if (token.isEmpty) {
      LogService.verbose(name, 'No token configured — skip');
      return null;
    }
    if (ProviderRateLimiter.instance.isLimited(name)) return null;

    try {
      final durSec =
          query.durationMs != null
              ? (query.durationMs! / 1000).round().toString()
              : '0';

      // Coba Rich Sync (word-timed) dulu
      final richUri = Uri.parse(
        _richSyncUrl
            .replaceFirst('{token}', Uri.encodeComponent(token))
            .replaceFirst('{artist}', Uri.encodeComponent(query.artist))
            .replaceFirst('{title}', Uri.encodeComponent(query.title))
            .replaceFirst('{dur}', durSec),
      );
      final richResp = await ProviderHttp.get(
        richUri,
        name,
        cancelToken,
        headers: _headers,
      );

      if (richResp != null) {
        if (richResp.statusCode == 429) {
          ProviderRateLimiter.instance.markRateLimited(
            name,
            duration: const Duration(minutes: 5),
          );
          return null;
        }
        if (richResp.statusCode == 200) {
          final result = _parseRichSync(richResp.body);
          if (result != null) return result;
        }
      }
      cancelToken.throwIfCancelled();

      // Fallback: synced LRC
      final subUri = Uri.parse(
        _subtitleUrl
            .replaceFirst('{token}', Uri.encodeComponent(token))
            .replaceFirst('{artist}', Uri.encodeComponent(query.artist))
            .replaceFirst('{title}', Uri.encodeComponent(query.title))
            .replaceFirst('{dur}', durSec),
      );
      final subResp = await ProviderHttp.get(
        subUri,
        name,
        cancelToken,
        headers: _headers,
      );
      if (subResp == null || subResp.statusCode != 200) return null;
      cancelToken.throwIfCancelled();

      return _parseSyncedLrc(subResp.body);
    } on CancelledException {
      return null;
    } catch (e) {
      LogService.verbose(name, 'Error: $e');
      return null;
    }
  }

  LyricsProviderResult? _parseRichSync(String body) {
    try {
      final data = jsonDecode(body);
      final macro = data['message']?['body']?['macro_calls'];
      if (macro == null) return null;

      // Coba jalur rich sync
      final richData = macro['track.richsync.get']?['message']?['body'];
      final richBody = richData?['richsync']?['richsync_body'] as String?;
      if (richBody != null && richBody.isNotEmpty) {
        // Rich sync adalah array JSON dengan format khusus MXM
        // Konversi ke LRC word-timed
        final lrc = _richSyncToLrc(richBody);
        if (lrc.isNotEmpty) {
          final lines = LrcParser.parseLrc(lrc);
          if (lines.isNotEmpty) {
            LogService.verbose(name, 'Rich sync ${lines.length} lines');
            return LyricsProviderResult(
              lines: lines,
              quality: LyricsQuality.wordTimedLrc,
              providerName: 'Musixmatch',
              isInternet: true,
              rawLrc: lrc,
            );
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Konversi Musixmatch Rich Sync JSON ke format LRC standard.
  String _richSyncToLrc(String richBody) {
    try {
      final List<dynamic> lines = jsonDecode(richBody);
      final buf = StringBuffer();
      for (final line in lines) {
        final ts = (line['ts'] as num?)?.toDouble() ?? 0.0;
        final text = (line['x'] as String?) ?? '';
        if (text.isEmpty) continue;
        final min = (ts ~/ 60).toString().padLeft(2, '0');
        final sec = (ts % 60).toStringAsFixed(2).padLeft(5, '0');
        buf.writeln('[$min:$sec]$text');
      }
      return buf.toString();
    } catch (_) {
      return '';
    }
  }

  LyricsProviderResult? _parseSyncedLrc(String body) {
    try {
      final data = jsonDecode(body);
      final macro = data['message']?['body']?['macro_calls'];
      final sub =
          macro?['track.subtitles.get']?['message']?['body']?['subtitle_list'];
      if (sub == null || sub is! List || sub.isEmpty) return null;

      final lrc = sub[0]['subtitle']?['subtitle_body'] as String?;
      if (lrc == null || lrc.isEmpty) return null;

      final quality = LrcParser.detectQuality(lrc);
      final lines = LrcParser.parseLrc(lrc);
      if (lines.isEmpty) return null;

      LogService.verbose(
        name,
        '${lines.length} lines [${quality.displayName}]',
      );
      return LyricsProviderResult(
        lines: lines,
        quality: quality,
        providerName: 'Musixmatch',
        isInternet: true,
        rawLrc: lrc,
      );
    } catch (_) {
      return null;
    }
  }
}
