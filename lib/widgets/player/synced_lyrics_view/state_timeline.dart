part of '../synced_lyrics_view.dart';

// Batas gap antar baris sebelum dianggap instrumental (ms).
// Gap lebih dari ini → kata terakhir tidak mengisi selambat jarak penuh.
const int _kInstrumentalThresholdMs = 3500;

extension _SyncedLyricsViewTimelineState on _SyncedLyricsViewState {
  // ── WordTimeline generation ───────────────────────────────────────────────

  void _rebuildWordTimelines() {
    final elrcLines = (widget.rawLrc == null || widget.rawLrc!.isEmpty)
        ? const <List<ElrcWord>>[]
        : ElrcWordExtractor.extractAll(widget.rawLrc!);

    _wordTimelines = List<List<_TimelineWord>>.generate(widget.lyrics.length, (
      i,
    ) {
      final lineStart = widget.lyrics[i].timestamp;
      final lineEnd = _lineEndFor(i);
      if (i < elrcLines.length && elrcLines[i].isNotEmpty) {
        return _timelineFromElrc(elrcLines[i], lineStart, lineEnd);
      }
      return _syntheticTimelineForLine(
        widget.lyrics[i].text,
        lineStart,
        lineEnd,
      );
    }, growable: false);
  }

  List<_TimelineWord> _timelineFromElrc(
    List<ElrcWord> words,
    Duration lineStart,
    Duration lineEnd,
  ) {
    return List<_TimelineWord>.generate(words.length, (i) {
      final start = words[i].start;
      final end = i + 1 < words.length ? words[i + 1].start : lineEnd;
      return _TimelineWord(words[i].text, start, _safeEnd(start, end));
    }, growable: false);
  }

  List<_TimelineWord> _syntheticTimelineForLine(
    String text,
    Duration lineStart,
    Duration lineEnd,
  ) {
    final matches = _syntheticWordRanges(text);
    if (matches.isEmpty) return const [];

    final totalMs = (lineEnd - lineStart).inMilliseconds.clamp(100, 30000);
    final totalChars = matches.fold<int>(
      0,
      (sum, range) => sum + range.$2 - range.$1,
    );
    var cursorMs = 0;

    return List<_TimelineWord>.generate(matches.length, (i) {
      final (startIndex, endIndex) = matches[i];
      final start = lineStart + Duration(milliseconds: cursorMs);
      final share = ((endIndex - startIndex) / totalChars * totalMs).round();
      cursorMs = i == matches.length - 1 ? totalMs : (cursorMs + share);
      final end = lineStart + Duration(milliseconds: cursorMs);
      return _TimelineWord(
        text.substring(startIndex, endIndex),
        start,
        _safeEnd(start, end),
      );
    }, growable: false);
  }

  /// Split ordinary LRC lines into animatable units.
  ///
  /// Latin text remains whitespace-delimited, while Japanese/CJK text has no
  /// spaces between words. Treating an entire CJK line as one word makes the
  /// karaoke fill jump across the line at once, so each CJK code point gets
  /// its own synthetic time slice.
  List<(int, int)> _syntheticWordRanges(String text) {
    final codePoints = <(int rune, int start, int end)>[];
    var offset = 0;
    for (final rune in text.runes) {
      final end = offset + (rune > 0xFFFF ? 2 : 1);
      codePoints.add((rune, offset, end));
      offset = end;
    }

    final ranges = <(int, int)>[];
    var i = 0;
    while (i < codePoints.length) {
      final point = codePoints[i];
      if (_isKaraokeWhitespace(point.$1)) {
        i++;
        continue;
      }

      if (_isCjkKaraokeRune(point.$1)) {
        ranges.add((point.$2, point.$3));
        i++;
        continue;
      }

      final start = point.$2;
      var end = point.$3;
      i++;
      while (i < codePoints.length &&
          !_isKaraokeWhitespace(codePoints[i].$1) &&
          !_isCjkKaraokeRune(codePoints[i].$1)) {
        end = codePoints[i].$3;
        i++;
      }
      ranges.add((start, end));
    }
    return ranges;
  }

  bool _isKaraokeWhitespace(int rune) {
    return String.fromCharCode(rune).trim().isEmpty;
  }

  bool _isCjkKaraokeRune(int rune) {
    return (rune >= 0x3000 && rune <= 0x30FF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0xAC00 && rune <= 0xD7AF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x20000 && rune <= 0x2FA1F);
  }

  Duration _safeEnd(Duration start, Duration proposed) {
    if (proposed > start) return proposed;
    return start + const Duration(milliseconds: 120);
  }

  Duration _lineEndFor(int index) {
    final lineStart = widget.lyrics[index].timestamp;
    if (index + 1 < widget.lyrics.length) {
      final nextStart = widget.lyrics[index + 1].timestamp;
      final gapMs = (nextStart - lineStart).inMilliseconds;
      // Kalau gap ke baris berikutnya melebihi threshold, kemungkinan ada
      // bagian instrumental. Cap lineEnd agar kata terakhir tidak mengisi
      // sangat lambat selama jeda musik.
      if (gapMs > _kInstrumentalThresholdMs) {
        return lineStart +
            const Duration(milliseconds: _kInstrumentalThresholdMs);
      }
      return nextStart;
    }
    return lineStart +
        Duration(milliseconds: _computeLineDurationMs(index).round());
  }

  void _activateTimelineForCurrentLine(Duration position) {
    final timeline = _currentIndex < _wordTimelines.length
        ? _wordTimelines[_currentIndex]
        : const <_TimelineWord>[];
    _karaokeController.setTimeline(timeline, position);
  }
}
