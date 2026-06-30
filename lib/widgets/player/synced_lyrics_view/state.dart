part of '../synced_lyrics_view.dart';

class _SyncedLyricsViewState extends State<SyncedLyricsView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ItemScrollController _itemScrollController = ItemScrollController();
  int _currentIndex = 0;

  Duration _anchorPos = Duration.zero;
  int _anchorWallMs = 0;
  bool _isPlaying = false;
  double _speed = 1.0;

  late final Ticker _frameTicker;
  StreamSubscription<Duration>? _posSub;

  // ── Format-agnostic karaoke renderer state ───────────────────────────────
  List<List<_TimelineWord>> _wordTimelines = const [];
  final _KaraokeLineController _karaokeController = _KaraokeLineController();

  // ── Manual-scroll suppression ──────────────────────────────────────────────
  bool _userIsManualScrolling = false;
  Timer? _scrollResumeTimer;

  // ── Single merged listenable for all display settings ─────────────────────
  late final Listenable _settingsListenable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frameTicker = createTicker(_onFrameTick);

    _settingsListenable = Listenable.merge([
      LyricsSettings.fontSize,
      LyricsSettings.textAlign,
      LyricsSettings.activeColor,
      LyricsSettings.karaokeMode,
    ]);

    _rebuildWordTimelines();

    final s = AudioService.playbackState.value;
    _syncFromPlaybackState(s);
    _anchorPos = s.position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    _currentIndex = _computeLineIndex(s.position);
    _activateTimelineForCurrentLine(s.position);

    if (_isPlaying) _frameTicker.start();

    _posSub = AudioService.positionStream.listen(_onPosition);
    AudioService.playbackState.addListener(_onPlaybackState);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToCenter(_currentIndex, animate: false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (_frameTicker.isActive) _frameTicker.stop();
        break;

      case AppLifecycleState.resumed:
        final s = AudioService.playbackState.value;
        _syncFromPlaybackState(s);

        if (_isPlaying && !_frameTicker.isActive) _frameTicker.start();

        final currentPos = _interpolatedPosition;
        _maybeUpdateCurrentLine(currentPos, allowBinarySearch: true);
        if (mounted) setState(() {});

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToCenter(_currentIndex, animate: true);
        });
        break;

      default:
        break;
    }
  }

  @override
  void didUpdateWidget(SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics || old.rawLrc != widget.rawLrc) {
      _rebuildWordTimelines();
      
      final currentPos = _interpolatedPosition;
      _currentIndex = _computeLineIndex(currentPos);
      _activateTimelineForCurrentLine(currentPos);
    }

    if (!old.isVisible && widget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToCenter(_currentIndex, animate: false);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    AudioService.playbackState.removeListener(_onPlaybackState);
    _frameTicker.dispose();
    _karaokeController.dispose();
    _scrollResumeTimer?.cancel();
    super.dispose();
  }

  // ── WordTimeline generation ───────────────────────────────────────────────

  void _rebuildWordTimelines() {
    final elrcLines =
        (widget.rawLrc == null || widget.rawLrc!.isEmpty)
            ? const <List<ElrcWord>>[]
            : ElrcWordExtractor.extractAll(widget.rawLrc!);

    _wordTimelines = List<List<_TimelineWord>>.generate(widget.lyrics.length, (i) {
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
    final timeline =
        _currentIndex < _wordTimelines.length
            ? _wordTimelines[_currentIndex]
            : const <_TimelineWord>[];
    _karaokeController.setTimeline(timeline, position);
  }

  // ── Playback state ────────────────────────────────────────────────────────

  void _syncFromPlaybackState(AudioPlaybackState s) {
    _isPlaying = s.isPlaying;
    _speed = s.speed.clamp(0.1, 4.0);
  }

  void _onPlaybackState() {
    final s = AudioService.playbackState.value;
    final wasPlaying = _isPlaying;
    _syncFromPlaybackState(s);

    if (_isPlaying) {
      if (!_frameTicker.isActive) _frameTicker.start();
    } else {
      if (_frameTicker.isActive) _frameTicker.stop();
      if (wasPlaying) {
        _anchorPos = s.position;
        _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
        _karaokeController.updatePosition(s.position);
      }
    }
  }

  void _onPosition(Duration position) {
    _anchorPos = position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;

    if (_isPlaying && !_frameTicker.isActive) _frameTicker.start();

    _maybeUpdateCurrentLine(position, allowBinarySearch: true);
    _karaokeController.updatePosition(position);
  }

  void _onFrameTick(Duration _) {
    if (!mounted || widget.lyrics.isEmpty) return;
    final position = _interpolatedPosition;
    _maybeUpdateCurrentLine(position, allowBinarySearch: false);
    _karaokeController.updatePosition(position);
  }

  Duration get _interpolatedPosition {
    if (!_isPlaying) return _anchorPos;
    final wallElapsedMs = DateTime.now().millisecondsSinceEpoch - _anchorWallMs;
    final audioElapsedMs = (wallElapsedMs * _speed).round();
    return _anchorPos + Duration(milliseconds: audioElapsedMs);
  }

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
        while (activeIndex > 0 && position < widget.lyrics[activeIndex].timestamp) {
          activeIndex--;
        }
      } else {
        activeIndex = _computeLineIndex(position);
      }
    }

    if (activeIndex == _currentIndex) return;

    _currentIndex = activeIndex;
    _activateTimelineForCurrentLine(position);
    if (mounted) setState(() {});
    _scrollToCenter(_currentIndex, animate: true);
  }

  // ── Scroll ────────────────────────────────────────────────────────────────

  void _scrollToCenter(int index, {bool animate = true}) {
    if (_userIsManualScrolling && animate) return;
    if (animate) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
    } else {
      _itemScrollController.jumpTo(index: index, alignment: 0.3);
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
      total +=
          (widget.lyrics[i + 1].timestamp - widget.lyrics[i].timestamp)
              .inMilliseconds
              .toDouble();
      count++;
    }
    return count > 0 ? (total / count).clamp(500.0, 5000.0) : 3000.0;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification) {
          if (n.direction != ScrollDirection.idle) {
            _userIsManualScrolling = true;
            _scrollResumeTimer?.cancel();
          }
        } else if (n is ScrollEndNotification && _userIsManualScrolling) {
          _scrollResumeTimer?.cancel();
          _scrollResumeTimer = Timer(const Duration(seconds: 3), () {
            if (!mounted) return;
            _userIsManualScrolling = false;
            _scrollToCenter(_currentIndex, animate: true);
          });
        }
        return false;
      },
      child: AnimatedBuilder(
        animation: _settingsListenable,
        builder: (context, _) {
          final double fs = LyricsSettings.fontSize.value;
          final Color active = LyricsSettings.resolvedActiveColor;
          final TextAlign align = LyricsSettings.resolvedTextAlign;
          final bool karaokeOn = LyricsSettings.karaokeMode.value;
          final Color dim = Colors.white.withValues(alpha: 0.35);

          return ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            padding: widget.padding.resolve(TextDirection.ltr),
            itemCount: widget.lyrics.length,
            itemBuilder: (context, index) {
              final isActive = index == _currentIndex;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
  final targetPos = widget.lyrics[index].timestamp;

  // ── Optimistic update biar Ticker ga narik mundur ──────────────────
  _anchorPos = targetPos;
  _anchorWallMs = DateTime.now().millisecondsSinceEpoch;

  _maybeUpdateCurrentLine(targetPos, allowBinarySearch: true);
  _karaokeController.updatePosition(targetPos);
  // ───────────────────────────────────────────────────────────────────

  // Baru deh panggil native seek-nya
  AudioService.seek(targetPos);
},
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: fs,
                      fontWeight: FontWeight.bold,
                      color: isActive ? active : dim,
                      height: 1.4,
                    ),
                    child: isActive && karaokeOn
                        ? _UnifiedKaraokeLine(
                            key: ValueKey(_currentIndex),
                            text: widget.lyrics[index].text,
                            timeline: _wordTimelines[index],
                            controller: _karaokeController,
                            activeColor: active,
                            dimColor: dim,
                            fontSize: fs,
                            textAlign: align,
                            textScaleFactor: MediaQuery.textScalerOf(context).scale(1.0),
                            textDirection: Directionality.of(context),
                          )
                        : Text(widget.lyrics[index].text, textAlign: align),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

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

class _UnifiedKaraokeLine extends StatelessWidget {
  final String text;
  final List<_TimelineWord> timeline;
  final _KaraokeLineController controller;
  final Color activeColor;
  final Color dimColor;
  final double fontSize;
  final TextAlign textAlign;
  final double textScaleFactor;
  final TextDirection textDirection;

  const _UnifiedKaraokeLine({
    super.key,
    required this.text,
    required this.timeline,
    required this.controller,
    required this.activeColor,
    required this.dimColor,
    required this.fontSize,
    required this.textAlign,
    required this.textScaleFactor,
    required this.textDirection,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _KaraokeLinePainter(
        text: text,
        timeline: timeline,
        controller: controller,
        activeColor: activeColor,
        dimColor: dimColor,
        fontSize: fontSize,
        textAlign: textAlign,
        textScaleFactor: textScaleFactor,
        textDirection: textDirection,
      ),
      child: Text(
        text,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.4,
          fontWeight: FontWeight.bold,
          color: Colors.transparent,
        ),
      ),
    );
  }
}

class _KaraokeLinePainter extends CustomPainter {
  final String text;
  final List<_TimelineWord> timeline;
  final _KaraokeLineController controller;
  final Color activeColor;
  final Color dimColor;
  final double fontSize;
  final TextAlign textAlign;
  final double textScaleFactor;
  final TextDirection textDirection;

  TextPainter? _basePainter;
  TextPainter? _highlightPainter;
  List<List<Rect>> _wordRects = const [];
  double _lastWidth = -1;

  _KaraokeLinePainter({
    required this.text,
    required this.timeline,
    required this.controller,
    required this.activeColor,
    required this.dimColor,
    required this.fontSize,
    required this.textAlign,
    required this.textScaleFactor,
    required this.textDirection,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    _ensureLayout(size.width);
    final base = _basePainter;
    final highlight = _highlightPainter;
    if (base == null || highlight == null) return;

    base.paint(canvas, Offset.zero);

    if (timeline.isEmpty || _wordRects.length != timeline.length) return;

    final cursor = controller.cursor.clamp(0, timeline.length - 1);
    final word = timeline[cursor];
    final startMs = word.start.inMilliseconds.toDouble();
    final endMs = word.end.inMilliseconds.toDouble();
    final durationMs = (endMs - startMs).clamp(1.0, 30000.0);
    final progress = ((controller.position.inMilliseconds - startMs) / durationMs).clamp(0.0, 1.0);

    final Path clipPath = Path();
    
    for (int i = 0; i <= cursor; i++) {
      final rects = _wordRects[i];
      if (i < cursor) {
        for (final rect in rects) {
          clipPath.addRect(rect);
        }
      } else {
        for (final rect in rects) {
          final clipW = rect.width * progress;
          if (textDirection == TextDirection.rtl) {
            clipPath.addRect(Rect.fromLTRB(rect.right - clipW, rect.top, rect.right, rect.bottom));
          } else {
            clipPath.addRect(Rect.fromLTRB(rect.left, rect.top, rect.left + clipW, rect.bottom));
          }
        }
      }
    }

    if (!clipPath.getBounds().isEmpty) {
      canvas.save();
      canvas.clipPath(clipPath);
      highlight.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  void _ensureLayout(double width) {
    if (_basePainter != null && _lastWidth == width) return;
    _lastWidth = width;

    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      color: dimColor,
      height: 1.4,
    );
    _basePainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout(maxWidth: width);
    
    _highlightPainter = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(color: activeColor)),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout(maxWidth: width);

    _cacheWordPixels();
  }

  void _cacheWordPixels() {
    if (timeline.isEmpty || text.isEmpty) {
      _wordRects = const [];
      return;
    }
    final painter = _basePainter!;
    final rectsList = <List<Rect>>[];
    var searchFrom = 0;
    
    for (final word in timeline) {
      final index = text.indexOf(word.text, searchFrom);
      if (index < 0) {
        rectsList.add(const []);
        continue;
      }
      searchFrom = index + word.text.length;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: searchFrom),
      );
      rectsList.add(boxes.map((b) => b.toRect()).toList());
    }
    _wordRects = List<List<Rect>>.unmodifiable(rectsList);
  }

  @override
  bool shouldRepaint(covariant _KaraokeLinePainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.timeline != timeline ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.dimColor != dimColor ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.textAlign != textAlign ||
        oldDelegate.textScaleFactor != textScaleFactor ||
        oldDelegate.textDirection != textDirection;
  }
}
