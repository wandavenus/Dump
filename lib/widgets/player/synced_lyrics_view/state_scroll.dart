part of '../synced_lyrics_view.dart';

extension _SyncedLyricsViewScrollState on _SyncedLyricsViewState {
  // ── Scroll ────────────────────────────────────────────────────────────────

  /// Jumps the currently-live internal scrollable by [deltaY] pixels, using
  /// the real [ScrollPosition] captured from the last [ScrollNotification]
  /// (see [_SyncedLyricsViewBuildState._buildLyricsView]). This is a direct,
  /// synchronous [ScrollPosition.jumpTo] — no animation controller involved —
  /// so it tracks the forwarded drag 1:1, exactly like a normal user drag.
  void _jumpByDelta(double deltaY) {
    final ctx = liveScrollContext;
    if (ctx == null || !ctx.mounted) return;
    final position = Scrollable.maybeOf(ctx)?.position;
    if (position == null || !position.hasPixels) return;
    final target = (position.pixels - deltaY).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    position.jumpTo(target);
  }

  /// Releases the currently-live internal scrollable into a normal ballistic
  /// fling, using the same physics a genuine drag-to-scroll gesture ends
  /// with. [velocity] must already be in scroll-offset space (i.e. negated
  /// relative to the raw forwarded [DragEndDetails.primaryVelocity], which
  /// is in on-screen finger space — see [_jumpByDelta]'s sign convention).
  /// Without this, a forwarded drag that stops abruptly on release (a plain
  /// jumpTo has no built-in momentum) feels rigid compared to scrolling the
  /// list directly.
  void _flingByVelocity(double velocity) {
    final ctx = liveScrollContext;
    if (ctx == null || !ctx.mounted) return;
    final position = Scrollable.maybeOf(ctx)?.position;
    if (position is ScrollPositionWithSingleContext) {
      position.goBallistic(velocity);
    }
  }

  void _scrollToCenter(int index, {bool animate = true}) {
    if (_userIsManualScrolling && animate) return;
    if (_pendingViewportRestorePixels != null && animate) return;
    if (animate) {
      unawaited(
        _itemScrollController.scrollTo(
          index: index,
          // Let the line movement ease into the highlight slightly more slowly
          // so the transition does not feel like the queue snaps into place.
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.2,
        ),
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
