part of '../lyrics_service.dart';

class LyricsResult {
  final List<LyricLine> lines;
  final LyricsSource source;
  const LyricsResult(this.lines, this.source);

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  String get sourceLabel {
    switch (source) {
      case LyricsSource.embedded:  return 'Dari tag file';
      case LyricsSource.localFile: return 'Dari file .lrc';
      case LyricsSource.internet:  return 'Dari internet';
      case LyricsSource.none:      return '';
    }
  }
}
