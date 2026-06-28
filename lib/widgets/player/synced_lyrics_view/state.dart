part of '../synced_lyrics_view.dart';

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final ScrollController _scroll = ScrollController();
  ScrollController get _eff => widget.controller ?? _scroll;
  int _currentIndex = 0;

  // GlobalKey per item — used to query the actual rendered RenderObject so that
  // RenderAbstractViewport.getOffsetToReveal() can compute the exact scroll
  // offset that places the item's CENTER at the viewport's CENTER.
  // This replaces the old estimated-height formula which could be 40+ px off.
  final Map<int, GlobalKey> _itemKeys = {};

  // Guard: prevent stacking multiple post-frame callbacks on rapid position ticks.
  bool _scrollPending = false;

  @override
  void didUpdateWidget(SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics) {
      // New song loaded: discard cached render keys and reset active index.
      _itemKeys.clear();
      _currentIndex = 0;
      _scrollPending = false;
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.fontSize,
      builder:
          (_, fs, _) => ValueListenableBuilder<String>(
            valueListenable: LyricsSettings.textAlign,
            builder:
                (_, align, _) => ValueListenableBuilder<String>(
                  valueListenable: LyricsSettings.activeColor,
                  builder: (_, colorKey, _) {
                    final activeColor = LyricsSettings.resolvedActiveColor;
                    final textAlign = LyricsSettings.resolvedTextAlign;

                    return StreamBuilder<Duration>(
                      stream: AudioService.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? Duration.zero;
                        // Called inside build() — must NOT call setState directly here.
                        _maybeUpdateCurrentLine(position);

                        return ListView.builder(
                          controller: _eff,
                          padding: widget.padding,
                          dragStartBehavior: DragStartBehavior.down,
                          itemCount: widget.lyrics.length,
                          itemBuilder: (context, index) {
                            // putIfAbsent creates a key lazily on first build of each item.
                            final itemKey = _itemKeys.putIfAbsent(
                              index,
                              GlobalKey.new,
                            );
                            final active = index == _currentIndex;

                            final activeFontSize = fs;
                            // Inactive lines: 82% of active, clamped to readable minimum.
                            final inactiveFontSize = fs;

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap:
                                  () => AudioService.seek(
                                    widget.lyrics[index].timestamp,
                                  ),
                              child: Padding(
                                // GlobalKey doubles as widget tree key AND render-object handle.
                                key: itemKey,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: AnimatedDefaultTextStyle(
                                  // Duration matches scroll animation for visual synchrony.
                                  duration: const Duration(milliseconds: 380),
                                  curve: Curves.easeOutCubic,
                                  style: TextStyle(
                                    fontSize:
                                        active
                                            ? activeFontSize
                                            : inactiveFontSize,
                                    fontWeight:
                                        active
                                            ? FontWeight.bold
                                            : FontWeight.bold,
                                    color:
                                        active
                                            ? activeColor
                                            : Colors.white.withValues(
                                              alpha: 0.35,
                                            ),
                                    height: 1.4,
                                  ),
                                  child:
                                      active
                                          ? _ProgressiveLyricLine(
                                            text: widget.lyrics[index].text,
                                            textAlign: textAlign,
                                            baseColor: Colors.white.withValues(
                                              alpha: 0.35,
                                            ),
                                            highlightColor: activeColor,
                                            progress: _activeLineProgress(
                                              position,
                                              index,
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
                    );
                  },
                ),
          ),
    );
  }

  double _activeLineProgress(Duration position, int index) {
    if (widget.lyrics.isEmpty || index < 0 || index >= widget.lyrics.length) {
      return 0.0;
    }

    final start = widget.lyrics[index].timestamp;
    final end =
        index + 1 < widget.lyrics.length
            ? widget.lyrics[index + 1].timestamp
            : start + const Duration(seconds: 4);
    final duration = end - start;
    if (duration <= Duration.zero) return 1.0;

    final elapsed = position - start;
    return (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
  }

  // ── Position tracking ───────────────────────────────────────────────────────

  /// Called on every position tick from the StreamBuilder.
  /// Must not call setState directly (we're inside build).
  void _maybeUpdateCurrentLine(Duration position) {
    if (widget.lyrics.isEmpty) return;

    // Binary-search the last line whose timestamp ≤ position.
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
    if (_scrollPending) return; // already waiting for a frame

    _scrollPending = true;

    // Frame 1: schedule setState so the new active index is reflected in the build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _scrollPending = false;
        return;
      }
      setState(() => _currentIndex = activeIndex);

      // Frame 2: after the rebuild has been painted, query actual render positions
      // and scroll so the new active item's CENTER is at the viewport CENTER.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollPending = false;
        if (!mounted) return;
        _scrollToCenter(activeIndex);
      });
    });
  }

  // ── Centering ───────────────────────────────────────────────────────────────

  /// Scrolls so that item [index] is centered in the viewport.
  ///
  /// Uses [RenderAbstractViewport.getOffsetToReveal] with alignment=0.5 which
  /// returns the exact scroll offset that places the item's midpoint at the
  /// viewport's midpoint — regardless of varying item heights or multiline text.
  void _scrollToCenter(int index) {
    if (!_eff.hasClients) return;

    final key = _itemKeys[index];
    if (key == null || key.currentContext == null) {
      _scrollToCenterFallback(index);
      return;
    }

    final RenderObject? renderObj = key.currentContext!.findRenderObject();
    if (renderObj == null) {
      _scrollToCenterFallback(index);
      return;
    }

    // Find the nearest scrollable viewport in the ancestor tree.
    // ignore: unnecessary_nullable_for_final_variable_declarations
    final RenderAbstractViewport? viewport = RenderAbstractViewport.of(
      renderObj,
    );
    if (viewport == null) {
      _scrollToCenterFallback(index);
      return;
    }

    // alignment=0.5 → item-center aligned with viewport-center.
    final double rawOffset = viewport.getOffsetToReveal(renderObj, 0.5).offset;

    final double target = rawOffset.clamp(
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

  /// Fallback used when the render object is not yet available (very first build).
  /// Uses a simple linear estimate; accurate enough for the initial scroll-to-top.
  void _scrollToCenterFallback(int index) {
    if (!_eff.hasClients) return;
    final fs = LyricsSettings.fontSize.value;
    // Approximate item height: active font × line-height + vertical padding.
    final double approxHeight = fs * 1.4 + 12.0;
    final double topPad = widget.padding.resolve(TextDirection.ltr).top;
    final double vpHalf = _eff.position.viewportDimension / 2;
    final double target = (index * approxHeight +
            topPad -
            vpHalf +
            approxHeight / 2)
        .clamp(_eff.position.minScrollExtent, _eff.position.maxScrollExtent);

    if ((target - _eff.offset).abs() < 1.0) return;
    _eff.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }
}

class _ProgressiveLyricLine extends StatelessWidget {
  final String text;
  final TextAlign textAlign;
  final Color baseColor;
  final Color highlightColor;
  final double progress;

  const _ProgressiveLyricLine({
    required this.text,
    required this.textAlign,
    required this.baseColor,
    required this.highlightColor,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final baseStyle = defaultStyle.copyWith(color: baseColor);
    final highlightStyle = defaultStyle.copyWith(color: highlightColor);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        final textWidth = _measureText(
          text,
          defaultStyle,
          textAlign,
          textDirection,
          textScaler,
          constraints.maxWidth,
        );
        final fillWidth = _highlightWidth(
          text: text,
          style: defaultStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          textScaler: textScaler,
          maxWidth: constraints.maxWidth,
          progress: progress,
        );
        final fillStart = _lineStartOffset(
          constraints.maxWidth,
          textWidth,
          textAlign,
          textDirection,
        );

        return Stack(
          children: [
            Text(text, textAlign: textAlign, style: baseStyle),
            ClipRect(
              clipper: _LyricProgressClipper(
                start: fillStart,
                width: fillWidth,
              ),
              child: Text(text, textAlign: textAlign, style: highlightStyle),
            ),
          ],
        );
      },
    );
  }

  static double _highlightWidth({
    required String text,
    required TextStyle style,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required double maxWidth,
    required double progress,
  }) {
    if (text.isEmpty || progress <= 0) return 0;
    if (progress >= 1) return maxWidth;

    final nonSpaceCount =
        text.runes.where((rune) => !_isWhitespace(rune)).length;
    if (nonSpaceCount == 0) return maxWidth * progress;

    final target = progress * nonSpaceCount;
    var seen = 0;
    var prefixEnd = 0;
    var charStart = 0;
    var charEnd = 0;
    var charFraction = 0.0;

    for (final rune in text.runes) {
      final next = prefixEnd + String.fromCharCode(rune).length;
      if (!_isWhitespace(rune)) {
        final nextSeen = seen + 1;
        if (target <= nextSeen) {
          charStart = prefixEnd;
          charEnd = next;
          charFraction = (target - seen).clamp(0.0, 1.0);
          break;
        }
        seen = nextSeen;
      }
      prefixEnd = next;
    }

    if (charEnd == 0) return maxWidth;

    final before = _measureText(
      text.substring(0, charStart),
      style,
      textAlign,
      textDirection,
      textScaler,
      maxWidth,
    );
    final withChar = _measureText(
      text.substring(0, charEnd),
      style,
      textAlign,
      textDirection,
      textScaler,
      maxWidth,
    );

    return (before + (withChar - before) * charFraction).clamp(0.0, maxWidth);
  }

  static double _measureText(
    String value,
    TextStyle style,
    TextAlign textAlign,
    TextDirection textDirection,
    TextScaler textScaler,
    double maxWidth,
  ) {
    if (value.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    return painter.width;
  }

  static double _lineStartOffset(
    double fullWidth,
    double textWidth,
    TextAlign textAlign,
    TextDirection textDirection,
  ) {
    final clippedTextWidth = textWidth.clamp(0.0, fullWidth);
    if (textAlign == TextAlign.center) {
      return (fullWidth - clippedTextWidth) / 2;
    }
    if (textAlign == TextAlign.right ||
        (textAlign == TextAlign.end && textDirection == TextDirection.ltr) ||
        (textAlign == TextAlign.start && textDirection == TextDirection.rtl)) {
      return fullWidth - clippedTextWidth;
    }
    return 0;
  }

  static bool _isWhitespace(int rune) =>
      rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D;
}

class _LyricProgressClipper extends CustomClipper<Rect> {
  final double start;
  final double width;

  const _LyricProgressClipper({required this.start, required this.width});

  @override
  Rect getClip(Size size) {
    final clippedStart = start.clamp(0.0, size.width);
    final clippedWidth = width.clamp(0.0, size.width - clippedStart);
    return Rect.fromLTWH(clippedStart, 0, clippedWidth, size.height);
  }

  @override
  bool shouldReclip(_LyricProgressClipper oldClipper) =>
      oldClipper.start != start || oldClipper.width != width;
}
