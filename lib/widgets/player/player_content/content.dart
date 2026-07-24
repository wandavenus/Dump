part of '../player_content.dart';

const double _playerHorizontalPadding = 32.0;

class PlayerContent extends StatefulWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final String Function(Duration duration) formatTime;
  final bool showLyrics;
  final VoidCallback onLyricsToggle;
  final bool showQueue;
  final VoidCallback onQueueToggle;
  final bool hideArtwork;

  const PlayerContent({
    super.key,
    required this.song,
    required this.playbackState,
    required this.formatTime,
    required this.showLyrics,
    required this.onLyricsToggle,
    required this.showQueue,
    required this.onQueueToggle,
    this.hideArtwork = false,
  });

  @override
  State<PlayerContent> createState() => _PlayerContentState();

  /// Forwards a vertical drag delta into whichever overlay (lyrics/queue) is
  /// currently active, from outside PlayerContent's own widget tree — used by
  /// the extra gesture-inset hit area in player_sheet/state.dart.
  static void forwardExternalDrag(double deltaY) =>
      _PlayerContentState.forwardExternalDrag(deltaY);

  /// Forwards the drag-release velocity for the same external gesture-inset
  /// hit area, so it can hand off into a natural fling too.
  static void forwardExternalDragEnd(double velocity) =>
      _PlayerContentState.forwardExternalDragEnd(velocity);

  /// Marks the start of a drag forwarded from the same external gesture-inset
  /// hit area, so the expand/collapse gating in lyrics_overlay.dart treats it
  /// as a genuine user gesture — see [LyricsDragHandle.isExternalDragActive].
  static void forwardExternalDragStart() =>
      _PlayerContentState.forwardExternalDragStart();
}

class _PlayerContentState extends State<PlayerContent> {
  static const _smallCoverSize = 55.0;

  bool _showMarquee = false;
  Timer? _marqueeTimer;

  double _lyricsExpand = 0.0;

  Future<LyricsResult>? _lyricsFuture;
  int? _lastFetchedSongId;

  final _lyricsScrollController = ScrollController();
  final _queueScrollController = ScrollController();
  // Pixel-based relative scroller for the lyrics list. Unlike
  // [_lyricsScrollController] (which SyncedLyricsView's
  // ScrollablePositionedList never actually attaches to), this is the real
  // scroll mechanism exposed by scrollable_positioned_list, so it's what
  // must be used to forward external drags into the lyrics list.
  final _lyricsOffsetController = ScrollOffsetController();
  // Forwards raw drag deltas directly into the lyrics list's live
  // ScrollPosition via jumpTo — see LyricsDragHandle for why this replaces
  // _lyricsOffsetController.animateScroll for external drag forwarding.
  final _lyricsDragHandle = LyricsDragHandle();

  // Bridges drags started outside this widget's own bounds (e.g. the extra
  // hit area covering the system gesture inset in player_sheet/state.dart,
  // which sits outside the SafeArea and therefore can't reach this State
  // directly) into the same forwarding logic used internally.
  static _PlayerContentState? _current;

  static void forwardExternalDragStart() {
    final cur = _current;
    cur?._forwardVerticalDragStart(showLyrics: cur.widget.showLyrics);
  }

  static void forwardExternalDrag(double deltaY) {
    final cur = _current;
    cur?._forwardVerticalDrag(
      showLyrics: cur.widget.showLyrics,
      showQueue: cur.widget.showQueue,
      deltaY: deltaY,
    );
  }

  static void forwardExternalDragEnd(double velocity) {
    final cur = _current;
    cur?._forwardVerticalDragEnd(
      showLyrics: cur.widget.showLyrics,
      showQueue: cur.widget.showQueue,
      velocity: velocity,
    );
  }

  // Marks a forwarded drag as "genuinely user-initiated" for as long as it
  // lasts, so lyrics_overlay.dart's expand/collapse gating (which otherwise
  // only trusts ScrollUpdateNotification.dragDetails != null, true only for
  // drags directly on the Scrollable) also reacts when the user drags from
  // one of the bottom hit-box areas instead of the list itself.
  void _forwardVerticalDragStart({required bool showLyrics}) {
    if (showLyrics) _lyricsDragHandle.isExternalDragActive = true;
  }

  void _forwardVerticalDrag({
    required bool showLyrics,
    required bool showQueue,
    required double deltaY,
  }) {
    if (showLyrics) {
      // Forwarded directly to the live ScrollPosition via jumpTo — see
      // LyricsDragHandle for why this replaces
      // _lyricsOffsetController.animateScroll (which always drives an
      // animation, even with Duration.zero, producing a jerky/rigid feel).
      _lyricsDragHandle.scrollByDelta(deltaY);
      return;
    }
    if (!showQueue) return;
    final ctrl = _queueScrollController;
    if (!ctrl.hasClients) return;
    ctrl.jumpTo(
      (ctrl.offset - deltaY).clamp(0.0, ctrl.position.maxScrollExtent),
    );
  }

  // Releases the active list (lyrics or queue) into a natural ballistic
  // fling once a drag forwarded from one of the bottom hit-box areas ends —
  // otherwise a forwarded drag (driven by jumpTo, which has no built-in
  // momentum) stops dead the instant the finger lifts, unlike scrolling the
  // list directly.
  void _forwardVerticalDragEnd({
    required bool showLyrics,
    required bool showQueue,
    required double velocity,
  }) {
    if (showLyrics) {
      // Swipe-down on the controls area while in full-view collapses back to
      // half-view immediately, without waiting for the list offset to drop
      // below 50. Threshold 200 filters out tiny accidental movements.
      if (_lyricsExpand > 0 && velocity > 200) {
        setState(() => _lyricsExpand = 0.0);
        _lyricsDragHandle.isExternalDragActive = false;
        return;
      }
      _lyricsDragHandle.flingByVelocity(velocity);
      _lyricsDragHandle.isExternalDragActive = false;
      return;
    }
    if (!showQueue) return;
    final ctrl = _queueScrollController;
    if (!ctrl.hasClients) return;
    final position = ctrl.position;
    if (position is ScrollPositionWithSingleContext) {
      // Same sign convention as _jumpByDelta/_forwardVerticalDrag: the
      // forwarded velocity is in on-screen finger space, goBallistic wants
      // scroll-offset space, hence the negation.
      position.goBallistic(-velocity);
    }
  }

  @override
  void initState() {
    super.initState();
    _current = this;
    _fetchLyricsIfNeeded();
    _restartMarquee();
  }

  @override
  void dispose() {
    if (_current == this) _current = null;
    _marqueeTimer?.cancel();
    _lyricsScrollController.dispose();
    _queueScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PlayerContent old) {
    super.didUpdateWidget(old);
    if (old.song.id != widget.song.id) {
      _fetchLyricsIfNeeded();
      _restartMarquee();
    }
    // Reset lyricsExpand when lyrics mode is turned off so bottom controls
    // are not left hidden when switching to queue or normal mode.
    if (old.showLyrics && !widget.showLyrics && _lyricsExpand > 0) {
      setState(() => _lyricsExpand = 0.0);
    }
  }

  void _fetchLyricsIfNeeded() {
    if (widget.song.id == _lastFetchedSongId) return;
    _lastFetchedSongId = widget.song.id;
    setState(() {
      _lyricsFuture = LyricsService.fetchLyrics(
        title: widget.song.title,
        artist: widget.song.artist,
        filePath: widget.song.path.isNotEmpty ? widget.song.path : null,
      );
    });
  }

  void _restartMarquee() {
    _marqueeTimer?.cancel();

    setState(() => _showMarquee = false);

    _marqueeTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showMarquee = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = PlayerSheetController.progress.value;
    final width = MediaQuery.sizeOf(context).width;
    final largeCoverSize = (width - 44).clamp(260.0, 390.0).toDouble();
    final showLyrics = widget.showLyrics;
    final showQueue = widget.showQueue;

    // Both overlay modes share the same artwork-shrink + song-info-fade behaviour.
    final showOverlay = showLyrics || showQueue;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 25),
          child: Column(
            children: [
              // ─── Flexible top area ────────────────────────────────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final sw = constraints.maxWidth;
                    final sh = constraints.maxHeight;

                    // Normal-mode cover: centred, leaving ~80 px for the song header.
                    final coverLeft = (sw - largeCoverSize) / 2;
                    final rawTop = (sh - largeCoverSize - 80) / 2 - 20;
                    final coverTop = rawTop.clamp(8.0, 60.0);

                    // Overlay content starts just below the small thumbnail.
                    const overlayTop = _smallCoverSize + 20.0;

                    const controlsHeight = 35.0;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // ── Song info — fades out when any overlay is active ──────
                        Positioned(
                          key: const ValueKey('songInfo'),
                          bottom: 15,
                          left: _playerHorizontalPadding,
                          right: _playerHorizontalPadding,
                          child: Opacity(
                            opacity: showOverlay ? 0.0 : 1.0,
                            child: IgnorePointer(
                              ignoring: showOverlay,
                              child: Opacity(
                                opacity: ((progress - 0.15) / 0.85).clamp(
                                  0.0,
                                  1.0,
                                ),
                                child: PlayerSongHeader(song: widget.song),
                              ),
                            ),
                          ),
                        ),

                        // ── Lyrics area — fades in in lyrics mode ─────────────────
                        Positioned(
                          key: const ValueKey('lyricsArea'),
                          top: overlayTop,
                          left: 7,
                          right: 7,
                          bottom: _lyricsExpand > 0 ? -200.0 : 30.0,
                          child: Opacity(
                            opacity: showLyrics ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !showLyrics,
                              child: _buildLyricsContent(),
                            ),
                          ),
                        ),

                        // ── Queue area — fades in in queue mode ───────────────────
                        Positioned(
                          key: const ValueKey('queueArea'),
                          top: overlayTop,
                          left: 15.7,
                          right: 15.7,
                          bottom: controlsHeight,
                          child: Opacity(
                            opacity: showQueue ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !showQueue,
                              child: _QueueOverlayBody(
                                isVisible: showQueue,
                                onClose: widget.onQueueToggle,
                                scrollController: _queueScrollController,
                              ),
                            ),
                          ),
                        ),

                        // ── Bottom-zone scroll relay ───────────────────────────────
                        // Transparent overlay covering gap between list bottom and
                        // stack bottom. Forwards vertical drags to the active list.
                        if (showLyrics || showQueue)
                          Positioned(
                            key: const ValueKey('scrollRelay'),
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: controlsHeight + 10,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onVerticalDragStart: (_) {
                                _forwardVerticalDragStart(
                                  showLyrics: showLyrics,
                                );
                              },
                              onVerticalDragUpdate: (d) {
                                _forwardVerticalDrag(
                                  showLyrics: showLyrics,
                                  showQueue: showQueue,
                                  deltaY: d.delta.dy,
                                );
                              },
                              onVerticalDragEnd: (d) {
                                _forwardVerticalDragEnd(
                                  showLyrics: showLyrics,
                                  showQueue: showQueue,
                                  velocity: d.primaryVelocity ?? 0,
                                );
                              },
                            ),
                          ),

                        // ── Appearance button — visible only in lyrics mode ───────
                        Positioned(
                          key: const ValueKey('appearanceButton'),
                          top: 10,
                          right: 27,
                          child: Opacity(
                            opacity: showLyrics ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !showLyrics,
                              child: const _AppearanceButton(),
                            ),
                          ),
                        ),

                        // ── Mini song header — shown next to small artwork ─────────
                        Positioned(
                          key: const ValueKey('miniSongHeader'),
                          top: 4,
                          left: 16 + _smallCoverSize + 25,

                          child: Opacity(
                            opacity: showOverlay ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !showOverlay,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 200,
                                    child: ShaderMask(
                                      shaderCallback: (rect) {
                                        return const LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            Colors.white,
                                            Colors.white,
                                            Colors.white,
                                            Colors.transparent,
                                          ],
                                          stops: [0.0, 0.30, 0.88, 1.0],
                                        ).createShader(rect);
                                      },
                                      blendMode: BlendMode.dstIn,
                                      child: AnimatedCrossFade(
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        crossFadeState:
                                            _showMarquee
                                                ? CrossFadeState.showSecond
                                                : CrossFadeState.showFirst,
                                        firstChild: Text(
                                          widget.song.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        secondChild: TextScroll(
                                          widget.song.title,
                                          mode: TextScrollMode.endless,
                                          velocity: const Velocity(
                                            pixelsPerSecond: Offset(25, 0),
                                          ),
                                          delayBefore: Duration.zero,
                                          pauseBetween: const Duration(
                                            seconds: 2,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    widget.song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.55,
                                      ),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // ── Album cover — Positioned + Transform (no relayout per frame) ───
                        // Layout is always fixed at the full-player position
                        // (coverTop, coverLeft) with the full large size.
                        // Transform.translate + Transform.scale handle the
                        // visual repositioning every frame without a layout pass,
                        // keeping frame time within the 16 ms budget during drag.
                        // The artwork child is always decoded at largeCoverSize so
                        // there is no re-decode during the transition.
                        Positioned(
                          key: const ValueKey('albumCover'),
                          top: coverTop,
                          left: coverLeft,
                          child: Opacity(
                            opacity: widget.hideArtwork ? 0.0 : 1.0,
                            child: Transform.translate(
                              offset: Offset(
                                showOverlay
                                    ? (16.0 - coverLeft)
                                    : lerpDouble(
                                      22.0 - coverLeft,
                                      0.0,
                                      progress,
                                    )!,
                                showOverlay
                                    ? (-0.5 - coverTop)
                                    : lerpDouble(
                                      sh - 140 - coverTop,
                                      0.0,
                                      progress,
                                    )!,
                              ),
                              child: Transform.scale(
                                scale: showOverlay
                                    ? (_smallCoverSize / largeCoverSize)
                                    : lerpDouble(
                                      70.0 / largeCoverSize,
                                      1.0,
                                      progress,
                                    )!,
                                alignment: Alignment.topLeft,
                                child: Container(
                                  width: largeCoverSize,
                                  height: largeCoverSize,
                                  clipBehavior: Clip.hardEdge,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    color: Colors.black,
                                    // Hairline stroke on the visible bounding
                                    // box — must live here (not inside
                                    // SongArtwork) since the inner image is
                                    // cropped by FittedBox/cover and would
                                    // clip a border drawn on its own edge.
                                    border: Border.all(
                                      color: kArtworkHairlineColor,
                                      width: kArtworkHairlineWidth,
                                      // Inset alignment — stays crisp as
                                      // the Transform scales it.
                                      strokeAlign: BorderSide.strokeAlignInside,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.0 + (0.10 * progress),
                                        ),
                                        blurRadius: 0.0 + (1 * progress),
                                        spreadRadius: 0.0 + (0.1 * progress),
                                        offset: Offset(0, 0 + (1 * progress)),
                                      ),
                                    ],
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: largeCoverSize,
                                      height: largeCoverSize,
                                      child: Hero(
                                        tag: PlayerHeroTags.artwork(widget.song),
                                        child: SongArtwork(
                                          songId: widget.song.id,
                                          size: largeCoverSize,
                                          borderRadius: BorderRadius.zero,
                                          // Hairline already drawn on the
                                          // outer Container above — avoids
                                          // a doubled/mismatched stroke here.
                                          showBorder: false,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // ─── Fixed bottom controls ────────────────────────────────────────────
              // GestureDetector forwards vertical drags from controls area to list.
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart:
                    (showLyrics || showQueue)
                        ? (_) {
                          _forwardVerticalDragStart(showLyrics: showLyrics);
                        }
                        : null,
                onVerticalDragUpdate:
                    (showLyrics || showQueue)
                        ? (d) {
                          _forwardVerticalDrag(
                            showLyrics: showLyrics,
                            showQueue: showQueue,
                            deltaY: d.delta.dy,
                          );
                        }
                        : null,
                onVerticalDragEnd:
                    (showLyrics || showQueue)
                        ? (d) {
                          _forwardVerticalDragEnd(
                            showLyrics: showLyrics,
                            showQueue: showQueue,
                            velocity: d.primaryVelocity ?? 0,
                          );
                        }
                        : null,
                child: Opacity(
                  opacity: 1.0 - _lyricsExpand,
                  child: IgnorePointer(
                    ignoring: _lyricsExpand > 0.0,
                    child: Opacity(
                      opacity: Curves.easeOut.transform(progress),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: _playerHorizontalPadding,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Opacity(
                                  opacity: ((progress - 0.2) / 0.8).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  child: PlayerProgressSection(
                                    formatTime: widget.formatTime,
                                  ),
                                ),
                                const SizedBox(height: 33),
                                Opacity(
                                  opacity: ((progress - 0.35) / 0.65).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  child: PlayerTransportControls(
                                    playbackState: widget.playbackState,
                                  ),
                                ),
                                const SizedBox(height: 37),
                                Opacity(
                                  opacity: progress,
                                  child: PlayerSecondaryControls(
                                    song: widget.song,
                                    showLyrics: showLyrics,
                                    onLyricsToggle: widget.onLyricsToggle,
                                    showQueue: showQueue,
                                    onQueueToggle: widget.onQueueToggle,
                                  ),
                                ),
                                const SizedBox(height: 25),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 15),
                            child: Container(
                              width: double.infinity,
                              height: 0.73,
                              color: Colors.white.withValues(alpha: 0.13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: PlayerUpNextCard(showOverlay: showOverlay),
        ),
      ],
    );
  }

  Widget _buildLyricsContent() {
    return FutureBuilder<LyricsResult>(
      future: _lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(
              color: Colors.white24,
              strokeWidth: 2,
            ),
          );
        }
        final result =
            snapshot.data ?? const LyricsResult([], LyricsSource.none);
        if (result.isEmpty) {
          return _EmptyLyricsOverlay(song: widget.song);
        }
        return _LyricsOverlayBody(
          result: result,
          scrollController: _lyricsScrollController,
          offsetController: _lyricsOffsetController,
          dragHandle: _lyricsDragHandle,
          isVisible: widget.showLyrics,
          onExpandChanged: (expanded) {
            if (_lyricsExpand == (expanded ? 1.0 : 0.0)) return;
            setState(() {
              _lyricsExpand = expanded ? 1.0 : 0.0;
            });
          },
        );
      },
    );
  }
}
