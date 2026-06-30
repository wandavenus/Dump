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
}

class _PlayerContentState extends State<PlayerContent> {
  static const _smallCoverSize = 55.0;

  bool _showMarquee = false;
  Timer? _marqueeTimer;

  double _lyricsExpand = 0.0;
  static const _animDuration = Duration(milliseconds: 400);
  static const _animCurve = Curves.easeInOutCubic;

  Future<LyricsResult>? _lyricsFuture;
  int? _lastFetchedSongId;

  final _lyricsScrollController = ScrollController();
  final _queueScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchLyricsIfNeeded();
    _restartMarquee();
  }

  @override
  void dispose() {
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
    final width = MediaQuery.of(context).size.width;
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
                          bottom: 59,
                          left: _playerHorizontalPadding,
                          right: _playerHorizontalPadding,
                          child: AnimatedOpacity(
                            duration: _animDuration,
                            curve: _animCurve,
                            opacity: showOverlay ? 0.0 : 1.0,
                            child: IgnorePointer(
                              ignoring: showOverlay,
                              child: Transform.translate(
                                offset: Offset(0, 20 * (1 - progress)),
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
                        ),

                        // ── Lyrics area — fades in in lyrics mode ─────────────────
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          top: overlayTop,
                          left: 7,
                          right: 7,
                          bottom: _lyricsExpand > 0 ? -200 : 30,
                          child: AnimatedOpacity(
                            duration: _animDuration,
                            curve: _animCurve,
                            opacity: showLyrics ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !showLyrics,
                              child: _buildLyricsContent(),
                            ),
                          ),
                        ),

                        // ── Queue area — fades in in queue mode ───────────────────
                        Positioned(
                          top: overlayTop,
                          left: 15.7,
                          right: 15.7,
                          bottom: controlsHeight,
                          child: AnimatedOpacity(
                            duration: _animDuration,
                            curve: _animCurve,
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
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: controlsHeight + 10,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onVerticalDragUpdate: (d) {
                                final ctrl =
                                    showLyrics
                                        ? _lyricsScrollController
                                        : _queueScrollController;
                                if (!ctrl.hasClients) return;
                                ctrl.jumpTo(
                                  (ctrl.offset - d.delta.dy).clamp(
                                    0.0,
                                    ctrl.position.maxScrollExtent,
                                  ),
                                );
                              },
                            ),
                          ),

                        // ── Appearance button — visible only in lyrics mode ───────
                        Positioned(
                          top: 10,
                          right: 27,
                          child: AnimatedOpacity(
                            duration: _animDuration,
                            curve: _animCurve,
                            opacity: showLyrics ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !showLyrics,
                              child: const _AppearanceButton(),
                            ),
                          ),
                        ),

                        // ── Mini song header — shown next to small artwork ─────────
                        Positioned(
                          top: 4,
                          left: 16 + _smallCoverSize + 25,

                          child: AnimatedOpacity(
                            duration: _animDuration,
                            curve: _animCurve,
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
                                          stops: [0.0, 0.20, 0.88, 1.0],
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

                        // ── Album cover — AnimatedPositioned + AnimatedContainer ───
                        AnimatedPositioned(
                          duration: _animDuration,
                          curve: _animCurve,
                          top:
                              showOverlay
                                  ? -0.5
                                  : lerpDouble(sh - 140, coverTop, progress)!,
                          left:
                              showOverlay
                                  ? 16
                                  : lerpDouble(22.0, coverLeft, progress)!,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 220),
                            opacity: widget.hideArtwork ? 0.0 : 1.0,
                            child: AnimatedContainer(
                              duration: _animDuration,
                              curve: _animCurve,
                              width:
                                  showOverlay
                                      ? _smallCoverSize
                                      : lerpDouble(
                                        70,
                                        largeCoverSize,
                                        progress,
                                      )!,

                              height:
                                  showOverlay
                                      ? _smallCoverSize
                                      : lerpDouble(
                                        70,
                                        largeCoverSize,
                                        progress,
                                      )!,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  showOverlay ? 3 : lerpDouble(3, 3, progress)!,
                                ),
                                color: Colors.black,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: 0.0 + (0.20 * progress),
                                    ),
                                    blurRadius: 0.0 + (10 * progress),
                                    spreadRadius: 0.0 + (0.2 * progress),
                                    offset: Offset(0, 0 + (3 * progress)),
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
                onVerticalDragUpdate:
                    (showLyrics || showQueue)
                        ? (d) {
                          final ctrl =
                              showLyrics
                                  ? _lyricsScrollController
                                  : _queueScrollController;
                          if (!ctrl.hasClients) return;
                          ctrl.jumpTo(
                            (ctrl.offset - d.delta.dy).clamp(
                              0.0,
                              ctrl.position.maxScrollExtent,
                            ),
                          );
                        }
                        : null,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: 1.0 - _lyricsExpand,
                  child: IgnorePointer(
                    ignoring: _lyricsExpand > 0.0,
                    child: Opacity(
                      opacity: Curves.easeOut.transform(progress),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.translate(
                            offset: Offset(0, 40 * (1 - progress) - 20),
                            child: Padding(
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
                                    child: Transform.translate(
                                      offset: const Offset(0, -15),
                                      child: PlayerProgressSection(
                                        formatTime: widget.formatTime,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Opacity(
                                    opacity: ((progress - 0.35) / 0.65).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    child: Transform.scale(
                                      scale: 0.85 + (0.15 * progress),
                                      child: PlayerTransportControls(
                                        playbackState: widget.playbackState,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
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
                                  const SizedBox(height: 15),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Container(
                              width: double.infinity,
                              height: 0.8,
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
