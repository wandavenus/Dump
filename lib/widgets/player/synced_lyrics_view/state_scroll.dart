part of '../synced_lyrics_view.dart';

extension _SyncedLyricsViewScrollState on _SyncedLyricsViewState {
  // ── Scroll ────────────────────────────────────────────────────────────────

  void _scrollToCenter(int index, {bool animate = true}) {
    if (_userIsManualScrolling && animate) return;
    if (animate) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    } else {
      _itemScrollController.jumpTo(index: index, alignment: 0.2);
    }
  }

  double _computeLineDurationMs(int index) {
    if (widget.lyrics.length < 2) return 3000.0;
    final lineStart = widget.lyrics[index].timestamp;
    if (index + 1 < widget.lyrics.length) {
      return (widget.lyrics[index + 1].timestamp - lineStart).inMilliseconds
          .toDouble()
          .clamp(100.0, 30000.0);
    }
    final sampleStart = (index - 5).clamp(0, index - 1);
    double total = 0;
    int count = 0;
    for (int i = sampleStart; i < index; i++) {
      total += (widget.lyrics[i + 1].timestamp - widget.lyrics[i].timestamp)
          .inMilliseconds
          .toDouble();
      count++;
    }
    return count > 0 ? (total / count).clamp(500.0, 5000.0) : 3000.0;
  }
}
