part of '../synced_lyrics_view.dart';

class _SyncedLyricsViewState extends State<SyncedLyricsView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  ScrollController get _eff => widget.controller ?? _scroll;
  int _currentIndex = 0;

  // GlobalKey per item for render-object-based centering.
  final Map<int, GlobalKey> _itemKeys = {};

  // Guard: prevents stacking multiple post-frame scroll callbacks.
  bool _scrollPending = false;

  // ── Per-character karaoke animation ──────────────────────────────────────
  // Single AnimationController drives the 0→1 sweep across the active line's
  // characters. It ticks at 60 fps (vsync-bound); position-stream updates
  // recalibrate it every ~100-200 ms so it stays in sync with the audio.
  late final AnimationController _charCtrl;
  StreamSubscription<Duration>? _posSub;
  Duration _lastPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _charCtrl = AnimationController(vsync: this);
    // Use stream subscription instead of StreamBuilder so position updates
    // don't force a rebuild of the entire widget tree.
    _posSub = AudioService.positionStream.listen(_onPosition);
  }

  @override
  void didUpdateWidget(SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics) {
      _itemKeys.clear();
      _currentIndex = 0;
      _scrollPending = false;
      _charCtrl.stop();
      _charCtrl.value = 0.0;
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _charCtrl.dispose();
    if (widget.controller == null) _scroll.dispose();
    super.dispose();
  }

  // ── Position handling ─────────────────────────────────────────────────────

  void _onPosition(Duration position) {
    _lastPosition = position;
    _maybeUpdateCurrentLine(position);
    // Recalibrate animation so it stays in sync with real audio time.
    // _currentIndex may have just been updated above.
    _recalibrateCharAnim(position);
  }

  /// Binary-search for the active lyric line; triggers setState + scroll when
  /// the line changes. Now called from a stream subscription (not from build),
  /// so setState can be called directly.
  void _maybeUpdateCurrentLine(Duration position) {
    if (widget.lyrics.isEmpty) return;

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

    if (activeIndex == _currentIndex) return;
    if (_scrollPending) return;

    _scrollPending = true;
    setState(() => _currentIndex = activeIndex);

    // Immediately prime the char animation for the new line so the first
    // AnimatedBuilder frame shows the correct start position.
    _recalibrateCharAnim(position);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollPending = false;
      if (!mounted) return;
      _scrollToCenter(activeIndex);
    });
  }

  /// Snaps _charCtrl to the real audio progress within the active line, then
  /// lets it free-run to 1.0 at 60 fps until the next recalibration.
  ///
  /// Called every ~100-200 ms from the position stream. The AnimationController
  /// fills in the remaining frames independently between calls.
  void _recalibrateCharAnim(Duration position) {
    if (!mounted || widget.lyrics.isEmpty) return;
    final idx = _currentIndex;
    if (idx >= widget.lyrics.length) return;

    final lineStart = widget.lyrics[idx].timestamp;
    final lineEnd = (idx + 1 < widget.lyrics.length)
        ? widget.lyrics[idx + 1].timestamp
        : lineStart + const Duration(seconds: 5);

    final double totalMs =
        (lineEnd - lineStart).inMilliseconds.toDouble();
    if (totalMs <= 0) {
      _charCtrl.value = 1.0;
      return;
    }

    final double elapsedMs =
        (position - lineStart).inMilliseconds.toDouble().clamp(0.0, totalMs);
    final double targetProgress = elapsedMs / totalMs;
    final double remainingMs = totalMs - elapsedMs;

    // Only hard-snap when the drift is large (e.g. after a seek).
    // Small diffs are left to animate naturally — avoids micro-jitter.
    final bool needsSnap = (_charCtrl.value - targetProgress).abs() > 0.06;

    _charCtrl.stop();
    if (needsSnap) _charCtrl.value = targetProgress;

    if (remainingMs > 16) {
      _charCtrl.animateTo(
        1.0,
        duration: Duration(milliseconds: remainingMs.toInt()),
        curve: Curves.linear, // linear = constant sweep speed across chars
      );
    } else {
      _charCtrl.value = 1.0;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.fontSize,
      builder: (_, fs, _) => ValueListenableBuilder<String>(
        valueListenable: LyricsSettings.textAlign,
        builder: (_, __, _) => ValueListenableBuilder<String>(
          valueListenable: LyricsSettings.activeColor,
          builder: (_, ___, _) {
            final activeColor = LyricsSettings.resolvedActiveColor;
            final textAlign   = LyricsSettings.resolvedTextAlign;
            final dimColor    = Colors.white.withValues(alpha: 0.35);

            return ListView.builder(
              controller: _eff,
              padding: widget.padding,
              dragStartBehavior: DragStartBehavior.down,
              itemCount: widget.lyrics.length,
              itemBuilder: (context, index) {
                final itemKey = _itemKeys.putIfAbsent(index, GlobalKey.new);
                final active  = index == _currentIndex;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      AudioService.seek(widget.lyrics[index].timestamp),
                  child: Padding(
                    key: itemKey,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    // AnimatedDefaultTextStyle wraps every line so that the
                    // dim-out transition (active→inactive) animates smoothly via
                    // DefaultTextStyle inheritance on the Text widget below.
                    // The active line's RichText bypasses DefaultTextStyle
                    // (uses explicit per-char spans), so the ADTS animation
                    // has no visual effect while the karaoke sweep runs.
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
                          // ── Active line: per-character karaoke sweep ───────
                          // AnimatedBuilder only rebuilds THIS widget at 60 fps.
                          // All other lines are untouched by _charCtrl ticks.
                          ? AnimatedBuilder(
                              animation: _charCtrl,
                              builder: (_, __) => _buildKaraokeText(
                                widget.lyrics[index].text,
                                _charCtrl.value,
                                activeColor,
                                dimColor,
                                fs,
                                textAlign,
                              ),
                            )
                          // ── Inactive line: plain text ──────────────────────
                          // Color is supplied by AnimatedDefaultTextStyle above.
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

  // ── Karaoke text renderer ─────────────────────────────────────────────────

  /// Returns a [RichText] where characters illuminate left-to-right as
  /// [progress] goes 0 → 1. The boundary between lit and dim chars moves
  /// sub-character: the char at the boundary gets an interpolated colour so
  /// the sweep looks smooth at any frame rate.
  Widget _buildKaraokeText(
    String text,
    double progress,
    Color activeColor,
    Color dimColor,
    double fontSize,
    TextAlign textAlign,
  ) {
    final chars = text.characters.toList(); // Unicode-safe split
    final int total = chars.length;
    if (total == 0) return const SizedBox.shrink();

    // How many characters are "covered" by the sweep (fractional).
    final double covered = progress * total;

    return RichText(
      textAlign: textAlign,
      text: TextSpan(
        children: List.generate(total, (i) {
          // charProgress: 0 = fully dim, 1 = fully active.
          // At the boundary character this is fractional → smooth edge.
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

  // ── Centering ─────────────────────────────────────────────────────────────

  /// Scrolls so the active line is centred in the *visible* portion of the
  /// viewport. Uses screen-coordinate arithmetic to correctly handle viewports
  /// that overflow below the screen (e.g. bottom: -200 in the player overlay).
  void _scrollToCenter(int index) {
    if (!_eff.hasClients) return;

    final key = _itemKeys[index];
    if (key == null || key.currentContext == null) {
      _scrollToCenterFallback(index);
      return;
    }

    final RenderObject? renderObj = key.currentContext!.findRenderObject();
    if (renderObj == null || renderObj is! RenderBox) {
      _scrollToCenterFallback(index);
      return;
    }

    final RenderAbstractViewport? viewport =
        RenderAbstractViewport.of(renderObj);
    if (viewport == null || viewport is! RenderBox) {
      _scrollToCenterFallback(index);
      return;
    }
    final RenderBox viewportBox = viewport as RenderBox;

    final double itemMidY =
        renderObj.localToGlobal(Offset(0, renderObj.size.height / 2)).dy;

    final double screenH  = MediaQuery.of(context).size.height;
    final double vpTop    = viewportBox.localToGlobal(Offset.zero).dy;
    final double vpBottom = vpTop + viewportBox.size.height;
    final double visTop    = vpTop.clamp(0.0, screenH);
    final double visBottom = vpBottom.clamp(0.0, screenH);
    final double visCenter = (visTop + visBottom) / 2;

    final double delta  = itemMidY - visCenter;
    final double target = (_eff.offset + delta).clamp(
      _eff.position.minScrollExtent,
      _eff.position.maxScrollExtent,
    );

    if ((target - _eff.offset).abs() < 1.0) return;

    _eff.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToCenterFallback(int index) {
    if (!_eff.hasClients) return;
    final fs = LyricsSettings.fontSize.value;
    final double approxHeight = fs * 1.4 + 12.0;
    final double topPad = widget.padding.resolve(TextDirection.ltr).top;
    final double vpHalf = _eff.position.viewportDimension / 2;
    final double target =
        (index * approxHeight + topPad - vpHalf + approxHeight / 2).clamp(
      _eff.position.minScrollExtent,
      _eff.position.maxScrollExtent,
    );

    if ((target - _eff.offset).abs() < 1.0) return;
    _eff.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }
}
