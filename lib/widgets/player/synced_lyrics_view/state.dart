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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _charCtrl = AnimationController(vsync: this);
    _frameTicker = createTicker(_onFrameTick);

    final s = AudioService.playbackState.value;
    _syncFromPlaybackState(s);
    _anchorPos = s.position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    _currentIndex = _computeLineIndex(s.position);

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
        if (mounted) setState(() {});

        if (_isPlaying && !_frameTicker.isActive) _frameTicker.start();
        
        // Langsung scroll aja, gak perlu flag pending ribet
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
    if (old.lyrics != widget.lyrics) {
      _currentIndex = 0;
      _charCtrl.value = 0.0;
      _anchorPos = Duration.zero;
      _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
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
    super.dispose();
  }

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

    if (mounted) setState(() {});
    
    // Panggil scroll center yang simpel
    _scrollToCenter(_currentIndex);
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

    final double threshold = 0.5 / totalMs;
    if ((_charCtrl.value - progress).abs() > threshold) {
      _charCtrl.value = progress;
    }
  }

  // Fungsi scroll yang jauh lebih elegan dan gak pake ribet
  void _scrollToCenter(int index, {bool animate = true}) {
    _itemScrollController.scrollTo(
      index: index,
      duration: animate ? const Duration(milliseconds: 380) : Duration.zero,
      curve: Curves.easeOutCubic,
      alignment: 0.5, // Ini kunci rahasia centering-nya, bby!
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.fontSize,
      builder: (_, fs, _) => ValueListenableBuilder<String>(
        valueListenable: LyricsSettings.textAlign,
        builder: (_, _, _) => ValueListenableBuilder<String>(
          valueListenable: LyricsSettings.activeColor,
          builder: (_, _, _) {
            final activeColor = LyricsSettings.resolvedActiveColor;
            final textAlign = LyricsSettings.resolvedTextAlign;
            final dimColor = Colors.white.withValues(alpha: 0.35);

            return ScrollablePositionedList.builder(
              itemScrollController: _itemScrollController,
              padding: widget.padding,
              itemCount: widget.lyrics.length,
              itemBuilder: (context, index) {
                final active = index == _currentIndex;
                final double lineDurationMs = active ? _computeLineDurationMs(index) : 0.0;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => AudioService.seek(widget.lyrics[index].timestamp),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        fontSize: fs,
                        fontWeight: FontWeight.bold,
                        color: active ? activeColor : dimColor,
                        height: 1.4,
                      ),
                      child: active
                          ? AnimatedBuilder(
                              animation: _charCtrl,
                              builder: (_, _) => _buildKaraokeText(
                                widget.lyrics[index].text,
                                _charCtrl.value,
                                activeColor,
                                dimColor,
                                fs,
                                textAlign,
                                lineDurationMs,
                              ),
                            )
                          : Text(
                              widget.lyrics[index].text,
                              textAlign: textAlign,
                            ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  double _computeLineDurationMs(int index) {
    if (widget.lyrics.length < 2) return 3000.0;
    final lineStart = widget.lyrics[index].timestamp;
    if (index + 1 < widget.lyrics.length) {
      return (widget.lyrics[index + 1].timestamp - lineStart)
          .inMilliseconds
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

  Widget _buildKaraokeText(
    String text,
    double progress,
    Color activeColor,
    Color dimColor,
    double fontSize,
    TextAlign textAlign,
    double lineDurationMs,
  ) {
    final chars = text.characters.toList();
    final int total = chars.length;
    if (total == 0) return const SizedBox.shrink();

    final int nonSpaceCount = chars.where((c) => c != ' ').length;
    if (nonSpaceCount == 0) return Text(text, textAlign: textAlign);

    final double easedProgress = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final double covered = easedProgress * nonSpaceCount;
    final double charsPerSec = nonSpaceCount / ((lineDurationMs / 1000.0).clamp(0.1, 30.0));
    final double gradientWidth = (4.0 / charsPerSec.clamp(1.8, 10.0)).clamp(0.8, 2.2);

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
            charProgress = ((covered - nonSpaceIdx) / gradientWidth).clamp(0.0, 1.0);
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
