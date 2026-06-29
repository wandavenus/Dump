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

        if (!_scrollPending) {
          _scrollPending = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollPending = false;
            if (!mounted) return;
            _scrollToCenter(_currentIndex, animate: true);
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
    // Re-center setiap kali lyrics menjadi visible kembali, tanpa peduli
    // apakah index berubah atau tidak — ini menangani kasus di mana user
    // sempat scroll manual atau lyrics tersembunyi saat lagu berjalan.
    if (!old.isVisible && widget.isVisible) {
      if (!_scrollPending) {
        _scrollPending = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollPending = false;
          if (!mounted) return;
          _scrollToCenter(_currentIndex, animate: false);
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
              // cacheExtent besar memastikan SEMUA item selalu di-build
              // (pre-rendered), sehingga ctx tidak pernah null saat
              // _scrollToCenter dipanggil — menghilangkan kebutuhan
              // fallback approximasi. Lyric text ringan sehingga memory
              // impact tidak signifikan.
              cacheExtent: 99999,
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

  // Scroll agar item [index] tepat di tengah viewport.
  // Menggunakan retry counter — lebih robust dari isRetry boolean.
  // Dengan cacheExtent: 99999, ctx hampir selalu non-null sehingga
  // getOffsetToReveal langsung dapat dipakai tanpa fallback.
  void _scrollToCenter(int index, {bool animate = true, int retries = 0}) {
    if (!_eff.hasClients) {
      if (retries < 4) {
        WidgetsBinding.instance.endOfFrame.then((_) {
          if (mounted) {
            _scrollToCenter(index, animate: animate, retries: retries + 1);
          }
        });
      }
      return;
    }
    if (!_eff.position.hasContentDimensions ||
        !_eff.position.hasViewportDimension ||
        _eff.position.viewportDimension <= 0) {
      if (retries < 4) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToCenter(index, animate: animate, retries: retries + 1);
          }
        });
      }
      return;
    }

    final key = _itemKeys[index];
    final ctx = key?.currentContext;

    if (ctx == null) {
      // Item belum di-build — lakukan approximate jump lalu retry.
      // Dengan cacheExtent: 99999 ini sangat jarang terjadi.
      if (retries < 5) {
        _scrollToCenterApprox(index);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToCenter(index, animate: animate, retries: retries + 1);
          }
        });
      }
      return;
    }

    final renderObj = ctx.findRenderObject();
    if (renderObj == null || !renderObj.attached) {
      if (retries < 5) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToCenter(index, animate: animate, retries: retries + 1);
          }
        });
      }
      return;
    }

    final viewport = RenderAbstractViewport.of(renderObj);
    final double target = viewport
        .getOffsetToReveal(renderObj, 0.5)
        .offset
        .clamp(
          _eff.position.minScrollExtent,
          _eff.position.maxScrollExtent,
        );

    if (animate) {
      _eff.animateTo(
        target,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _eff.jumpTo(target);
    }
  }

  // Approximate scroll untuk membawa item ke dalam viewport agar
  // getOffsetToReveal dapat dipanggil di retry berikutnya.
  void _scrollToCenterApprox(int index) {
    if (!_eff.hasClients) return;
    if (!_eff.position.hasContentDimensions ||
        !_eff.position.hasViewportDimension ||
        _eff.position.viewportDimension <= 0) {
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
    _eff.jumpTo(target);
  }
}
