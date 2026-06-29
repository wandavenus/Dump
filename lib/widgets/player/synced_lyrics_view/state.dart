part of '../synced_lyrics_view.dart';

class _SyncedLyricsViewState extends State<SyncedLyricsView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  ScrollController get _eff => widget.controller ?? _scroll;
  int _currentIndex = 0;

  final Map<int, GlobalKey> _itemKeys = {};
  bool _scrollPending = false;

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
        // Bekukan posisi & HENTIKAN ticker agar _interpolatedPosition tidak
        // melonjak ketika app resume (wall-clock jalan, ticker tidak).
        _anchorPos = _interpolatedPosition;
        _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
        if (_frameTicker.isActive) _frameTicker.stop();

      case AppLifecycleState.resumed:
        final s = AudioService.playbackState.value;
        // Re-anchor to the real position first, then restart the ticker so the
        // first tick already uses the correct anchor.
        _anchorPos = s.position;
        _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
        _syncFromPlaybackState(s);

        // Always update _currentIndex and rebuild so the highlight is correct.
        // We do NOT guard on (newIdx != _currentIndex): even when the index is
        // unchanged we still need the setState→PostFrameCallback path below to
        // run, because that is the only moment hasContentDimensions is
        // guaranteed true (it may still be false during the first post-resume
        // frames, which is why the previous double-PostFrameCallback approach
        // silently failed).
        _currentIndex = _computeLineIndex(s.position);
        _charCtrl.value = 0.0;
        if (mounted) setState(() {});

        if (_isPlaying && !_frameTicker.isActive) _frameTicker.start();

        // Mirror path B exactly: one PostFrameCallback after setState's frame,
        // guarded by _scrollPending so it cannot race with a concurrent
        // _maybeUpdateCurrentLine callback.
        if (!_scrollPending) {
          _scrollPending = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollPending = false;
            if (!mounted) return;
            _scrollToCenter(_currentIndex);
          });
        }

      default:
    }
  }

  @override
  void didUpdateWidget(SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics) {
      _itemKeys.clear();
      _currentIndex = 0;
      _scrollPending = false;
      _charCtrl.value = 0.0;
      _anchorPos = Duration.zero;
      _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Hapus observer
    _posSub?.cancel();
    AudioService.playbackState.removeListener(_onPlaybackState);
    _frameTicker.dispose();
    _charCtrl.dispose();
    if (widget.controller == null) _scroll.dispose();
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

    if (!_scrollPending) {
      _scrollPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollPending = false;
        if (!mounted) return;
        _scrollToCenter(_currentIndex);
      });
    }
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

            return ListView.builder(
              controller: _eff,
              padding: widget.padding,
              dragStartBehavior: DragStartBehavior.down,
              itemCount: widget.lyrics.length,
              itemBuilder: (context, index) {
                final itemKey = _itemKeys.putIfAbsent(index, GlobalKey.new);
                final active = index == _currentIndex;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => AudioService.seek(widget.lyrics[index].timestamp),
                  child: Padding(
                    key: itemKey,
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

  Widget _buildKaraokeText(
    String text,
    double progress,
    Color activeColor,
    Color dimColor,
    double fontSize,
    TextAlign textAlign,
  ) {
    final chars = text.characters.toList();
    final int total = chars.length;
    if (total == 0) return const SizedBox.shrink();

    final double covered = progress * total;

    return RichText(
      textAlign: textAlign,
      text: TextSpan(
        children: List.generate(total, (i) {
          final double charProgress = (covered - i).clamp(0.0, 1.0);
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

  void _scrollToCenter(int index, {bool animate = true, bool isRetry = false}) {
    if (!_eff.hasClients) {
  if (!isRetry) {
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (mounted) {
        _scrollToCenter(index, animate: animate, isRetry: true);
      }
    });
  }
  return;
}
    if (!_eff.position.hasContentDimensions ||
        !_eff.position.hasViewportDimension) {
      return;
    }

    final key = _itemKeys[index];
    final ctx = key?.currentContext;

    if (ctx == null) {
      _scrollToCenterFallback(index, animate: animate, isRetry: isRetry);
      return;
    }

    final renderObj = ctx.findRenderObject();
    if (renderObj == null || !renderObj.attached) {
      _scrollToCenterFallback(index, animate: animate, isRetry: isRetry);
      return;
    }

    // getOffsetToReveal(obj, 0.5) menghitung offset scroll agar CENTER item
    // sejajar dengan CENTER viewport — ini cara internal Scrollable.ensureVisible,
    // benar di semua layout (Stack, Positioned, nested widget, dll).
    final viewport = RenderAbstractViewport.of(renderObj);
    final double target = viewport
        .getOffsetToReveal(renderObj, 0.5)
        .offset
        .clamp(
          _eff.position.minScrollExtent,
          _eff.position.maxScrollExtent,
        );

    if ((target - _eff.offset).abs() < 1.0 && isRetry) {
  return;
}

    if (animate) {
      _eff.animateTo(
        target,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _eff.jumpTo(target);
      WidgetsBinding.instance.endOfFrame.then((_) {
  if (!mounted || isRetry) return;
  _scrollToCenter(index, animate: false, isRetry: true);
});
    }
  }

  // PERBAIKAN: Strategi Two-Pass Fallback
  void _scrollToCenterFallback(int index, {bool animate = true, bool isRetry = false}) {
    if (!_eff.hasClients) return;
    
    // Guard: Mencegah error jika dipanggil saat app baru resume & layout belum siap
    if (!_eff.position.hasContentDimensions || !_eff.position.hasViewportDimension || _eff.position.viewportDimension <= 0) {
      if (!isRetry) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToCenter(index, animate: animate, isRetry: true);
        });
      }
      return;
    }

    final fs = LyricsSettings.fontSize.value;
    final double approxHeight = fs * 1.4 + 20.0; 
    final double topPad = widget.padding.resolve(TextDirection.ltr).top;
    final double vpHalf = _eff.position.viewportDimension / 2;
    
    final double target =
        (index * approxHeight + topPad - vpHalf + approxHeight / 2).clamp(
      _eff.position.minScrollExtent,
      _eff.position.maxScrollExtent,
    );

    if ((target - _eff.offset).abs() < 1.0) return;
    
    if (animate) {
      _eff.animateTo(
        target,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      ).then((_) {
        // Setelah animasi kasar selesai, layout item harusnya sudah terender, 
        // kalkulasi ulang secara presisi (Second Pass)
        if (!isRetry && mounted) {
          _scrollToCenter(index, animate: true, isRetry: true);
        }
      });
    } else {
      _eff.jumpTo(target);
      // Kalkulasi presisi di frame berikutnya
      if (!isRetry) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToCenter(index, animate: false, isRetry: true);
        });
      }
    }
  }
}
