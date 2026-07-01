part of '../synced_lyrics_view.dart';

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
    final matches = RegExp(r'\S+').allMatches(text).toList(growable: false);
    if (matches.isEmpty) return const [];

    final totalMs = (lineEnd - lineStart).inMilliseconds.clamp(100, 30000);
    final totalChars = matches.fold<int>(
      0,
      (sum, m) => sum + (m.end - m.start),
    );
    var cursorMs = 0;

    return List<_TimelineWord>.generate(matches.length, (i) {
      final m = matches[i];
      final start = lineStart + Duration(milliseconds: cursorMs);
      final share = ((m.end - m.start) / totalChars * totalMs).round();
      cursorMs = i == matches.length - 1 ? totalMs : (cursorMs + share);
      final end = lineStart + Duration(milliseconds: cursorMs);
      return _TimelineWord(
        text.substring(m.start, m.end),
        start,
        _safeEnd(start, end),
      );
    }, growable: false);
  }

  Duration _safeEnd(Duration start, Duration proposed) {
    if (proposed > start) return proposed;
    return start + const Duration(milliseconds: 120);
  }

  Duration _lineEndFor(int index) {
    final lineStart = widget.lyrics[index].timestamp;
    if (index + 1 < widget.lyrics.length) {
      return widget.lyrics[index + 1].timestamp;
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
