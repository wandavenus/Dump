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
    return switch (source) {
      LyricsSource.embedded  => 'Dari tag file',
      LyricsSource.localFile => 'Dari file .lrc',
      LyricsSource.internet  => 'Dari internet',
      LyricsSource.none      => '',
    };
  }
}
