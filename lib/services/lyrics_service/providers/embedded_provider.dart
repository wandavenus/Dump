import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/log_service.dart';
import '../cancellation.dart';
import '../lrc_parser.dart';
import '../provider.dart';
import '../quality.dart';

/// Provider: tag lirik yang tertanam di dalam file audio (USLT/SYLT/LYRICS).
/// Hanya tersedia di Android (non-web).
class EmbeddedProvider implements LyricsProvider {
  static const _channel = MethodChannel('musicplayer/media_store');

  @override
  String get name => 'Embedded Tag';

  @override
  bool get isOnline => false;

  @override
  Future<LyricsProviderResult?> fetch(
    LyricsQuery query,
    CancellationToken cancelToken,
  ) async {
    if (kIsWeb) return null;
    final path = query.filePath;
    if (path == null || path.isEmpty) return null;

    try {
      cancelToken.throwIfCancelled();
      final raw = await _channel.invokeMethod<String>(
        'getEmbeddedLyrics',
        {'path': path},
      );
      if (raw == null || raw.trim().isEmpty) return null;
      cancelToken.throwIfCancelled();

      final parsed = LrcParser.parse(raw.trim());
      if (parsed.isEmpty) return null;

      LogService.verbose('EmbeddedProvider',
          '${parsed.lines.length} lines [${parsed.quality.displayName}]');
      return LyricsProviderResult(
        lines: parsed.lines,
        quality: parsed.quality,
        providerName: 'Dari tag file',
        isInternet: false,
        rawLrc: raw.trim(),
      );
    } on CancelledException {
      return null;
    } catch (e) {
      LogService.verbose('EmbeddedProvider', 'Error: $e');
      return null;
    }
  }
}
