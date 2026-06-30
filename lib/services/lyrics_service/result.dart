part of '../lyrics_service.dart';

class LyricsResult {
  final List<LyricLine> lines;
  final LyricsSource source;
  final LyricsQuality quality;
  final String providerName;

  /// String LRC asli termasuk inline word timestamps (Enhanced LRC).
  /// Null untuk lirik embedded, file lokal non-ELRC, atau saat tidak tersedia.
  /// Digunakan oleh renderer ELRC untuk highlighting kata yang akurat.
  final String? rawLrc;

  const LyricsResult(
    this.lines,
    this.source, {
    this.quality = LyricsQuality.none,
    this.providerName = '',
    this.rawLrc,
  });

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  String get sourceLabel {
    if (providerName.isNotEmpty) return providerName;
    switch (source) {
      case LyricsSource.embedded:
        return 'Dari tag file';
      case LyricsSource.localFile:
        return 'Dari file .lrc';
      case LyricsSource.internet:
        return 'Dari internet';
      case LyricsSource.none:
        return '';
    }
  }
}
