part of '../synced_lyrics_view.dart';

extension _SyncedLyricsViewIndexingState on _SyncedLyricsViewState {
  // ── Line index ────────────────────────────────────────────────────────────

  int _computeLineIndex(Duration position) {
    if (widget.lyrics.isEmpty) return 0;
    int lo = 0, hi = widget.lyrics.length - 1, activeIndex = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (widget.lyrics[mid].timestamp <= position) {
        activeIndex = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return activeIndex;
  }

  void _maybeUpdateCurrentLine(
    Duration position, {
    required bool allowBinarySearch,
  }) {
    if (widget.lyrics.isEmpty) return;

    var activeIndex = _currentIndex;

    if (activeIndex >= widget.lyrics.length) {
      activeIndex = widget.lyrics.length - 1;
    }

    if (activeIndex + 1 < widget.lyrics.length &&
        position >= widget.lyrics[activeIndex + 1].timestamp) {
      do {
        activeIndex++;
      } while (activeIndex + 1 < widget.lyrics.length &&
          position >= widget.lyrics[activeIndex + 1].timestamp);
    } else if (position < widget.lyrics[activeIndex].timestamp) {
      if (!allowBinarySearch) {
        while (activeIndex > 0 &&
            position < widget.lyrics[activeIndex].timestamp) {
          activeIndex--;
        }
      } else {
        activeIndex = _computeLineIndex(position);
      }
    }

    if (activeIndex == _currentIndex) return;

    _currentIndex = activeIndex;
    _activateTimelineForCurrentLine(position);
    if (mounted) _refresh();
    _scrollToCenter(_currentIndex, animate: true);
  }
}
