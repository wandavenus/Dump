part of '../synced_lyrics_view.dart';

class _TimelineWord {
  final String text;
  final Duration start;
  final Duration end;

  const _TimelineWord(this.text, this.start, this.end);
}

class _KaraokeLineController extends ChangeNotifier {
  List<_TimelineWord> _timeline = const [];
  int _cursor = 0;
  Duration _position = Duration.zero;

  List<_TimelineWord> get timeline => _timeline;
  int get cursor => _cursor;
  Duration get position => _position;

  void setTimeline(List<_TimelineWord> timeline, Duration position) {
    _timeline = timeline;
    _position = position;
    _cursor = _findCursor(position);
    notifyListeners();
  }

  void updatePosition(Duration position) {
    _position = position;
    if (_timeline.isNotEmpty && position < _timeline[_cursor].start) {
      _cursor = _findCursor(position);
    } else {
      while (_cursor + 1 < _timeline.length &&
          position >= _timeline[_cursor + 1].start) {
        _cursor++;
      }
    }
    notifyListeners();
  }

  int _findCursor(Duration position) {
    if (_timeline.isEmpty) return 0;
    int lo = 0, hi = _timeline.length - 1, activeIndex = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_timeline[mid].start <= position) {
        activeIndex = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return activeIndex;
  }
}
