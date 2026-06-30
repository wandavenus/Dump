part of '../synced_lyrics_view.dart';

class _SyncedLyricsViewState extends State<SyncedLyricsView>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  final ItemScrollController _itemScrollController = ItemScrollController();
  int _currentIndex = 0;

  late final AnimationController _charCtrl;

  Duration _anchorPos = Duration.zero;
  int _anchorWallMs = 0;
  bool _isPlaying = false;
  double _speed = 1.0;

  late final Ticker _frameTicker;
  StreamSubscription<Duration>? _posSub;

  // ── Pre-computed karaoke state (standard character-fill) ───────────────────
  // Updated only when _currentIndex changes — never on every frame.
  List<String> _karaokeChars = [];
  int _karaokeNonSpaceCount = 0;
  double _karaokeLineDurationMs = 3000.0;

  // ── Pre-computed ELRC word state ───────────────────────────────────────────
  // Populated once from rawLrc when available; updated per line-change.
  List<List<ElrcWord>> _elrcWordLines = const [];
  List<ElrcWord> _currentLineElrcWords = const [];

  // ── Manual-scroll suppression ──────────────────────────────────────────────
  bool _userIsManualScrolling = false;
  Timer? _scrollResumeTimer;

  // ── Single merged listenable for all display settings ─────────────────────
  late final Listenable _settingsListenable;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _charCtrl = AnimationController(vsync: this);
    _frameTicker = createTicker(_onFrameTick);

    _settingsListenable = Listenable.merge([
      LyricsSettings.fontSize,
      LyricsSettings.textAlign,
      LyricsSettings.activeColor,
      LyricsSettings.karaokeMode,
    ]);

    _parseElrcWords();

    final s = AudioService.playbackState.value;
    _syncFromPlaybackState(s);
    _anchorPos = s.position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    _currentIndex = _computeLineIndex(s.position);
    _updateKaraokePrecompute();

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
        _anchorPos = _interpolatedPosition;
        _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
        if (_frameTicker.isActive) _frameTicker.stop();

      case AppLifecycleState.resumed:
        final s = AudioService.playbackState.value;
        _anchorPos = s.position;
        _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
        _syncFromPlaybackState(s);

        _currentIndex = _computeLineIndex(s.position);
        _charCtrl.value = 0.0;
        _updateKaraokePrecompute();
        if (mounted) setState(() {});

        if (_isPlaying && !_frameTicker.isActive) _frameTicker.start();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToCenter(_currentIndex, animate: true);
        });

      default:
    }
  }

  @override
  void didUpdateWidget(SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics || old.rawLrc != widget.rawLrc) {
      _parseElrcWords();
      _currentIndex = 0;
      _charCtrl.value = 0.0;
      _anchorPos = Duration.zero;
      _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
      _updateKaraokePrecompute();
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
    _charCtrl.dispose();
    _scrollResumeTimer?.cancel();
    super.dispose();
  }

  // ── ELRC parse (once per song) ────────────────────────────────────────────

  void _parseElrcWords() {
    final raw = widget.rawLrc;
    if (raw == null || raw.isEmpty) {
      _elrcWordLines = const [];
      _currentLineElrcWords = const [];
      return;
    }
    _elrcWordLines = ElrcWordExtractor.extractAll(raw);
    _currentLineElrcWords = const [];
  }

  // ── Pre-compute ───────────────────────────────────────────────────────────

  /// Rebuild karaoke data for the current line.
  /// Called once when [_currentIndex] changes — never per frame.
  void _updateKaraokePrecompute() {
    if (widget.lyrics.isEmpty || _currentIndex >= widget.lyrics.length) {
      _karaokeChars = [];
      _karaokeNonSpaceCount = 0;
      _karaokeLineDurationMs = 3000.0;
      _currentLineElrcWords = const [];
      return;
    }

    // Standard character-fill state
    final text = widget.lyrics[_currentIndex].text;
    _karaokeChars = text.characters.toList();
    _karaokeNonSpaceCount = _karaokeChars.where((c) => c != ' ').length;
    _karaokeLineDurationMs = _computeLineDurationMs(_currentIndex);

    // ELRC word state — indexed in parallel with widget.lyrics
    if (_elrcWordLines.isNotEmpty &&
        _currentIndex < _elrcWordLines.length) {
      _currentLineElrcWords = _elrcWordLines[_currentIndex];
    } else {
      _currentLineElrcWords = const [];
    }
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
        _updateKaraokeProgress(s.position);
      }
    }
  }

  void _onPosition(Duration position) {
    _anchorPos = position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    _isPlaying = true;

    if (!_frameTicker.isActive) _frameTicker.start();

    _maybeUpdateCurrentLine(position);
  }

  void _onFrameTick(Duration _) {
    if (!mounted || widget.lyrics.isEmpty) return;
    _updateKaraokeProgress(_interpolatedPosition);
  }

  Duration get _interpolatedPosition {
    if (!_isPlaying) return _anchorPos;
    final wallElapsedMs = DateTime.now().millisecondsSinceEpoch - _anchorWallMs;
    final audioElapsedMs = (wallElapsedMs * _speed).round();
    return _anchorPos + Duration(milliseconds: audioElapsedMs);
  }

  // ── Line index ────────────────────────────────────────────────────────────

  /// Binary search — O(log n).
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

  void _maybeUpdateCurrentLine(Duration position) {
    if (widget.lyrics.isEmpty) return;
    final activeIndex = _computeLineIndex(position);
    if (activeIndex == _currentIndex) return;

    _currentIndex = activeIndex;
    _charCtrl.value = 0.0;
    _updateKaraokePrecompute();

    if (mounted) setState(() {});

    _scrollToCenter(_currentIndex, animate: true);
  }

  void _updateKaraokeProgress(Duration position) {
    if (widget.lyrics.isEmpty) return;
    final idx = _currentIndex;
    if (idx >= widget.lyrics.length) return;

    final lineStart = widget.lyrics[idx].timestamp;
    final lineEnd = (idx + 1 < widget.lyrics.length)
        ? widget.lyrics[idx + 1].timestamp
        : lineStart + const Duration(seconds: 5);

    final double totalMs = (lineEnd - lineStart).inMilliseconds.toDouble();
    if (totalMs <= 0) {
      _charCtrl.value = 1.0;
      return;
    }

    final double elapsedMs =
        (position - lineStart).inMilliseconds.toDouble().clamp(0.0, totalMs);
    final double progress = elapsedMs / totalMs;

    // Threshold prevents micro-updates that waste GPU time without visual change.
    final double threshold = 0.5 / totalMs;
    if ((_charCtrl.value - progress).abs() > threshold) {
      _charCtrl.value = progress;
    }
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
      _itemScrollController.jumpTo(
        index: index,
        alignment: 0.3,
      );
    }
  }

  // ── Duration helpers ──────────────────────────────────────────────────────

  double _computeLineDurationMs(int index) {
    if (widget.lyrics.length < 2) return 3000.0;
    final lineStart = widget.lyrics[index].timestamp;
    if (index + 1 < widget.lyrics.length) {
      return (widget.lyrics[index + 1].timestamp - lineStart)
          .inMilliseconds
          .toDouble()
          .clamp(100.0, 30000.0);
    }
    // Last line: use the average of the preceding 5 gaps as an estimate.
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification && n.dragDetails != null) {
          _userIsManualScrolling = true;
          _scrollResumeTimer?.cancel();
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
          final double fs      = LyricsSettings.fontSize.value;
          final Color active   = LyricsSettings.resolvedActiveColor;
          final TextAlign align = LyricsSettings.resolvedTextAlign;
          final bool karaokeOn = LyricsSettings.karaokeMode.value;
          final Color dim      = Colors.white.withValues(alpha: 0.35);

          return ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            padding: widget.padding.resolve(TextDirection.ltr),
            itemCount: widget.lyrics.length,
            itemBuilder: (context, index) {
              final isActive = index == _currentIndex;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    AudioService.seek(widget.lyrics[index].timestamp),
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
                        ? AnimatedBuilder(
                            animation: _charCtrl,
                            builder: (_, _) {
                              // ELRC path: true word timestamps available.
                              if (_currentLineElrcWords.isNotEmpty) {
                                return _buildElrcText(
                                  _interpolatedPosition,
                                  _currentLineElrcWords,
                                  active,
                                  dim,
                                  fs,
                                  align,
                                );
                              }
                              // Standard path: character-fill interpolation.
                              return _buildKaraokeText(
                                _charCtrl.value,
                                active,
                                dim,
                                fs,
                                align,
                              );
                            },
                          )
                        : Text(
                            widget.lyrics[index].text,
                            textAlign: align,
                          ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ── ELRC word renderer ────────────────────────────────────────────────────

  /// Builds true karaoke word highlighting driven entirely by parsed
  /// word timestamps from Enhanced LRC.
  ///
  /// - Previous words: fully highlighted ([activeColor]).
  /// - Current word: fills smoothly from [dimColor] → [activeColor] based on
  ///   elapsed time within the word's own timestamp window.
  /// - Future words: [dimColor].
  ///
  /// No timing is estimated or interpolated — every boundary is from [words].
  Widget _buildElrcText(
    Duration position,
    List<ElrcWord> words,
    Color activeColor,
    Color dimColor,
    double fontSize,
    TextAlign textAlign,
  ) {
    // Binary search: last word with start <= position.
    int lo = 0, hi = words.length - 1, currentWordIdx = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (words[mid].start <= position) {
        currentWordIdx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    // Fill fraction for the current word based on its own timestamp window.
    double fillFraction = 1.0;
    if (currentWordIdx >= 0 && currentWordIdx < words.length - 1) {
      final wStartMs = words[currentWordIdx].start.inMilliseconds.toDouble();
      final wEndMs   = words[currentWordIdx + 1].start.inMilliseconds.toDouble();
      final dur = wEndMs - wStartMs;
      if (dur > 0) {
        fillFraction = ((position.inMilliseconds - wStartMs) / dur)
            .clamp(0.0, 1.0);
      }
    }

    // Build spans: one per word with single space between words.
    // Allocation is O(words.length) — same as the standard char-fill path.
    final spans = <InlineSpan>[];
    for (int i = 0; i < words.length; i++) {
      if (i > 0) {
        // Space inherits left neighbour's brightness — no visible gap.
        final spaceColor = i <= currentWordIdx ? activeColor : dimColor;
        spans.add(TextSpan(
          text: ' ',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: spaceColor,
            height: 1.4,
          ),
        ));
      }

      final Color wordColor;
      if (i < currentWordIdx) {
        wordColor = activeColor;
      } else if (i == currentWordIdx) {
        wordColor = Color.lerp(
          dimColor,
          activeColor,
          Curves.easeOut.transform(fillFraction),
        )!;
      } else {
        wordColor = dimColor;
      }

      spans.add(TextSpan(
        text: words[i].text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: wordColor,
          height: 1.4,
        ),
      ));
    }

    return RichText(
      textAlign: textAlign,
      text: TextSpan(children: spans),
    );
  }

  // ── Standard karaoke renderer (character-fill) ────────────────────────────

  /// Builds character-fill karaoke text using pre-computed state fields.
  ///
  /// Uses [_karaokeChars], [_karaokeNonSpaceCount], and
  /// [_karaokeLineDurationMs] — all set once in [_updateKaraokePrecompute].
  /// Only [progress] changes every frame, keeping per-frame allocations minimal.
  Widget _buildKaraokeText(
    double progress,
    Color activeColor,
    Color dimColor,
    double fontSize,
    TextAlign textAlign,
  ) {
    final List<String> chars = _karaokeChars;
    final int total = chars.length;
    if (total == 0) return const SizedBox.shrink();

    final int nonSpaceCount = _karaokeNonSpaceCount;
    if (nonSpaceCount == 0) {
      return Text(
        widget.lyrics[_currentIndex].text,
        textAlign: textAlign,
      );
    }

    final double eased =
        Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final double covered = eased * nonSpaceCount;

    // Gradient width adapts to reading speed.
    final double charsPerSec = nonSpaceCount /
        (_karaokeLineDurationMs / 1000.0).clamp(0.1, 30.0);
    final double gradientWidth =
        (4.0 / charsPerSec.clamp(1.8, 10.0)).clamp(0.8, 2.2);

    int nonSpaceIdx = 0;
    double lastCharProgress = 0.0;

    return RichText(
      textAlign: textAlign,
      text: TextSpan(
        children: List.generate(total, (i) {
          double charProgress;
          if (chars[i] == ' ') {
            charProgress = lastCharProgress;
          } else {
            charProgress =
                ((covered - nonSpaceIdx) / gradientWidth).clamp(0.0, 1.0);
            lastCharProgress = charProgress;
            nonSpaceIdx++;
          }
          return TextSpan(
            text: chars[i],
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: Color.lerp(dimColor, activeColor, charProgress),
              height: 1.4,
            ),
          );
        }),
      ),
    );
  }
}
