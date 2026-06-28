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
      builder: (_, fs, _) =>
          ValueListenableBuilder<String>(
        valueListenable: LyricsSettings.textAlign,
        builder: (_, align, _) =>
            ValueListenableBuilder<String>(
          valueListenable: LyricsSettings.activeColor,
          builder: (_, colorKey, _) {
            final activeColor = LyricsSettings.resolvedActiveColor;
            final textAlign   = LyricsSettings.resolvedTextAlign;

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
                    final itemKey = _itemKeys.putIfAbsent(index, GlobalKey.new);
                    final active  = index == _currentIndex;

                    final activeFontSize   = fs;
                    // Inactive lines: 82% of active, clamped to readable minimum.
                    final inactiveFontSize = fs;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          AudioService.seek(widget.lyrics[index].timestamp),
                      child: Padding(
                        // GlobalKey doubles as widget tree key AND render-object handle.
                        key: itemKey,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: AnimatedDefaultTextStyle(
                          // Duration matches scroll animation for visual synchrony.
                          duration: const Duration(milliseconds: 380),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            fontSize:
                                active ? activeFontSize : inactiveFontSize,
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.bold,
                            color: active
                                ? activeColor
                                : Colors.white.withValues(alpha: 0.35),
                            height: 1.4,
                          ),
                          child: Text(
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
      if (!mounted) { _scrollPending = false; return; }
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
    if (renderObj == null) { _scrollToCenterFallback(index); return; }

    // Find the nearest scrollable viewport in the ancestor tree.
    // ignore: unnecessary_nullable_for_final_variable_declarations
    final RenderAbstractViewport? viewport = RenderAbstractViewport.of(renderObj);
    if (viewport == null) { _scrollToCenterFallback(index); return; }

    // alignment=0.5 → item-center aligned with viewport-center.
    final double rawOffset =
        viewport.getOffsetToReveal(renderObj, 0.5).offset;

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
    final double vpHalf  = _eff.position.viewportDimension / 2;
    final double target  = (index * approxHeight + topPad - vpHalf + approxHeight / 2)
        .clamp(_eff.position.minScrollExtent, _eff.position.maxScrollExtent);

    if ((target - _eff.offset).abs() < 1.0) return;
    _eff.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }
}
