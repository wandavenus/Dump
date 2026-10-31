part of '../synced_lyrics_view.dart';

typedef _KaraokeLayoutConfiguration = ({
  double width,
  double fontSize,
  double textScaleFactor,
  TextAlign textAlign,
  Color activeColor,
  Color dimColor,
});

extension _SyncedLyricsViewKaraokeState on _SyncedLyricsViewState {
  /// Captures the geometry-affecting configuration and schedules prewarming.
  ///
  /// Current and nearby lines are prepared outside the widget paint path.
  /// The visible current line gets animation priority; neighboring lines use
  /// idle priority so they do not compete with active frames.
  void _prepareKaraokeLayouts(double width) {
    if (!width.isFinite || width <= 0) return;

    final configuration = (
      width: width,
      fontSize: LyricsSettings.fontSize.value,
      textScaleFactor: MediaQuery.textScalerOf(context).scale(1.0),
      textAlign: LyricsSettings.resolvedTextAlign,
      activeColor: LyricsSettings.resolvedActiveColor,
      dimColor: Colors.white.withValues(alpha: 0.48),
    );

    if (_karaokeLayoutConfiguration != configuration) {
      _karaokeLayoutCache.clear();
      _karaokePrewarmGeneration++;
      _karaokePrewarmAnchorIndex = -1;
      _karaokePrewarmVisibility = null;
      _karaokeLayoutConfiguration = configuration;
    }

    final karaokeEnabled = LyricsSettings.karaokeMode.value;
    if (!karaokeEnabled || widget.lyrics.isEmpty) {
      if (_karaokePrewarmEnabled != false) {
        _karaokePrewarmGeneration++;
        _karaokePrewarmAnchorIndex = -1;
        _karaokePrewarmVisibility = null;
        _karaokePrewarmEnabled = false;
      }
      return;
    }
    _karaokePrewarmEnabled = true;

    _scheduleKaraokePrewarm();
  }

  bool _isKaraokeLinePrepared(int index) {
    final configuration = _karaokeLayoutConfiguration;
    if (configuration == null ||
        index < 0 ||
        index >= widget.lyrics.length ||
        index >= _wordTextTimelines.length) {
      return false;
    }

    final text = widget.lyrics[index].text;
    final direction = LyricsTextDirection.resolve(text);
    return _karaokeLayoutCache.contains(
      lineIndex: index,
      text: text,
      wordTexts: _wordTextTimelines[index],
      maxWidth: configuration.width,
      fontSize: configuration.fontSize,
      textScaleFactor: configuration.textScaleFactor,
      textAlign: direction == TextDirection.rtl
          ? TextAlign.right
          : configuration.textAlign,
      textDirection: direction,
      activeColor: configuration.activeColor,
      dimColor: configuration.dimColor,
    );
  }

  bool _warmKaraokeLine(int index) {
    if (_isKaraokeLinePrepared(index)) return false;
    final configuration = _karaokeLayoutConfiguration;
    if (configuration == null ||
        index < 0 ||
        index >= widget.lyrics.length ||
        index >= _wordTextTimelines.length) {
      return false;
    }

    final text = widget.lyrics[index].text;
    final direction = LyricsTextDirection.resolve(text);
    _karaokeLayoutCache.obtain(
      lineIndex: index,
      text: text,
      wordTexts: _wordTextTimelines[index],
      maxWidth: configuration.width,
      fontSize: configuration.fontSize,
      textScaleFactor: configuration.textScaleFactor,
      textAlign: direction == TextDirection.rtl
          ? TextAlign.right
          : configuration.textAlign,
      textDirection: direction,
      activeColor: configuration.activeColor,
      dimColor: configuration.dimColor,
    );
    return true;
  }

  void _scheduleKaraokePrewarm() {
    if (_karaokeLayoutConfiguration == null) return;
    if (_karaokePrewarmAnchorIndex == _currentIndex &&
        _karaokePrewarmVisibility == widget.isVisible) {
      return;
    }
    _karaokePrewarmAnchorIndex = _currentIndex;
    _karaokePrewarmVisibility = widget.isVisible;

    final indices = <int>[_currentIndex];
    for (var offset = 1; offset <= 8; offset++) {
      indices.add(_currentIndex + offset);
    }
    for (var offset = 1; offset <= 2; offset++) {
      indices.add(_currentIndex - offset);
    }

    final validIndices = indices
        .where((index) => index >= 0 && index < widget.lyrics.length)
        .toList(growable: false);
    if (validIndices.isEmpty) return;

    final generation = ++_karaokePrewarmGeneration;

    void scheduleAt(int cursor) {
      unawaited(
        SchedulerBinding.instance.scheduleTask<void>(
          () {
            if (!mounted || generation != _karaokePrewarmGeneration) return;
            final index = validIndices[cursor];
            final prepared = _warmKaraokeLine(index);
            if (prepared && widget.isVisible && index == _currentIndex) {
              _refresh();
            }
            final next = cursor + 1;
            if (next < validIndices.length) scheduleAt(next);
          },
          cursor <= 1 && widget.isVisible
              ? Priority.animation
              : Priority.idle,
          debugLabel: 'lyrics-karaoke-layout-prewarm',
        ),
      );
    }

    scheduleAt(0);
  }
}
