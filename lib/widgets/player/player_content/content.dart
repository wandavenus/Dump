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

  Future<LyricsResult>? _lyricsFuture;
  int? _lastFetchedSongId;

  final _lyricsScrollController = ScrollController();
  final _queueScrollController = ScrollController();
  // Pixel-based relative scroller for the lyrics list. Unlike
  // [_lyricsScrollController] (which SyncedLyricsView's
  // ScrollablePositionedList never actually attaches to), this is the real
  // scroll mechanism exposed by scrollable_positioned_list.
  final _lyricsOffsetController = ScrollOffsetController();
  final _lyricsDragHandle = LyricsDragHandle();

  void _forwardVerticalDragStart({required bool showLyrics}) {
    if (showLyrics) _lyricsDragHandle.isExternalDragActive = true;
  }

  void _forwardVerticalDrag({
    required bool showLyrics,
    required bool showQueue,
    required double deltaY,
  }) {
    if (showLyrics) {
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

  void _forwardVerticalDragEnd({
    required bool showLyrics,
    required bool showQueue,
    required double velocity,
  }) {
    if (showLyrics) {
      _lyricsDragHandle.flingByVelocity(velocity);
      _lyricsDragHandle.isExternalDragActive = false;
      return;
    }
    if (!showQueue) return;
    final ctrl = _queueScrollController;
    if (!ctrl.hasClients) return;
    final position = ctrl.position;
    if (position is ScrollPositionWithSingleContext) {
      position.goBallistic(-velocity);
    }
  }

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
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final largeCoverSize = (width - 44).clamp(260.0, 390.0).toDouble();
    final showLyrics = widget.showLyrics;
    final showQueue = widget.showQueue;

    // Both overlay modes share the same artwork-shrink + song-info-fade behaviour.
    final showOverlay = showLyrics || showQueue;

    // Wide window (landscape phone, tablet, desktop, short split-screen pane):
    // artwork on the left, song info + controls on the right. The stacked
    // portrait layout below is untouched for every other window.
    if (useTwoColumnNowPlaying(media.size)) {
      return Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 25),
            child: _buildTwoColumn(
              context,
              media,
              progress,
              showLyrics,
              showQueue,
            ),
          ),
        ],
      );
    }

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

                    const controlsHeight = 2.0;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // ── Song info — fades out when any overlay is active ──────
                        Positioned(
                          key: const ValueKey('songInfo'),
                          bottom: 15,
                          left: _playerHorizontalPadding,
                          right: _playerHorizontalPadding,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: showOverlay ? 0.0 : 1.0),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOutCubic,
                            builder: (context, value, child) =>
                                Opacity(opacity: value, child: child),
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
                          bottom: _lyricsExpand > 0 ? -230.0 : 2.0,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: showLyrics ? 1.0 : 0.0),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOutCubic,
                            builder: (context, value, child) =>
                                Opacity(opacity: value, child: child),
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
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: showQueue ? 1.0 : 0.0),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOutCubic,
                            builder: (context, value, child) =>
                                Opacity(opacity: value, child: child),
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
                          child: _buildAppearanceButton(showLyrics: showLyrics),
                        ),

                        // ── Mini song header — shown next to small artwork ─────────
                        Positioned(
                          key: const ValueKey('miniSongHeader'),
                          top: 4,
                          left: 16 + _smallCoverSize + 25,
                          child: _buildMiniSongHeader(
                            context,
                            showOverlay: showOverlay,
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
                                        tag: PlayerHeroTags.artwork(
                                          widget.song,
                                        ),
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
                onVerticalDragStart: (showLyrics || showQueue)
                    ? (_) {
                        _forwardVerticalDragStart(showLyrics: showLyrics);
                      }
                    : null,
                onVerticalDragUpdate: (showLyrics || showQueue)
                    ? (d) {
                        _forwardVerticalDrag(
                          showLyrics: showLyrics,
                          showQueue: showQueue,
                          deltaY: d.delta.dy,
                        );
                      }
                    : null,
                onVerticalDragEnd: (showLyrics || showQueue)
                    ? (d) {
                        _forwardVerticalDragEnd(
                          showLyrics: showLyrics,
                          showQueue: showQueue,
                          velocity: d.primaryVelocity ?? 0,
                        );
                      }
                    : null,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: 1.0 - _lyricsExpand),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  builder: (context, value, child) =>
                      Opacity(opacity: value, child: child),
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
      ],
    );
  }

  // ─── Overlay chrome (dipakai kedua tata letak) ─────────────────────────────

  /// Tombol bulat "tampilan lirik" di kanan atas; hanya tampil di mode lirik.
  Widget _buildAppearanceButton({required bool showLyrics}) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: showLyrics ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: IgnorePointer(
        ignoring: !showLyrics,
        child: const _AppearanceButton(),
      ),
    );
  }

  /// Header mini (judul + artis) di samping thumbnail artwork saat overlay
  /// lirik/antrean aktif.
  Widget _buildMiniSongHeader(
    BuildContext context, {
    required bool showOverlay,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: showOverlay ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
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
                  duration: const Duration(milliseconds: 250),
                  crossFadeState: _showMarquee
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
                    velocity: const Velocity(pixelsPerSecond: Offset(25, 0)),
                    delayBefore: Duration.zero,
                    pauseBetween: const Duration(seconds: 2),
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
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tata letak dua kolom (lanskap / window lebar) ─────────────────────────

  /// Full player saat window cukup lebar: artwork di kolom kiri, judul lagu +
  /// kontrol pemutaran di kolom kanan.
  ///
  /// Slot artwork di sini hanya memegang Hero + artwork tersembunyi; artwork
  /// yang terlihat digambar oleh UnifiedMorphPlayer memakai geometri yang sama
  /// ([nowPlayingColumns]) sehingga posisi keduanya tidak pernah berbeda.
  Widget _buildTwoColumn(
    BuildContext context,
    MediaQueryData media,
    double progress,
    bool showLyrics,
    bool showQueue,
  ) {
    final showOverlay = showLyrics || showQueue;
    final contentTop = media.padding.top + kNowPlayingTopInset;
    final columns = nowPlayingColumns(
      size: media.size,
      safeTop: media.padding.top,
      safeBottom: media.padding.bottom,
    );
    // Koordinat lokal PlayerContent: tepi atasnya persis di [contentTop].
    final artwork = columns.artwork.shift(Offset(0, -contentTop));
    final panel = columns.panel.shift(Offset(0, -contentTop));
    final metrics = nowPlayingPanelMetrics(panel.height);

    // Overlay lirik/antrean memakai lebar penuh di bawah header mini agar baris
    // lirik tetap terbaca pada window lanskap yang pendek.
    final overlayTop = _smallCoverSize + 20.0;
    final overlayBottom = kNowPlayingSecondaryStrip + metrics.spacing;
    final overlayHeight = (panel.height - overlayTop - overlayBottom).clamp(
      0.0,
      double.infinity,
    );
    final lyricsPad = (overlayHeight * 0.25).clamp(24.0, 130.0);

    final headerOpacity = ((progress - 0.15) / 0.85).clamp(0.0, 1.0);
    final progressOpacity = ((progress - 0.2) / 0.8).clamp(0.0, 1.0);
    final transportOpacity = ((progress - 0.35) / 0.65).clamp(0.0, 1.0);
    final panelTopInset =
        ((panel.height - overlayBottom) - metrics.contentHeight).clamp(
          0.0,
          400.0,
        ) /
        2;

    return Stack(
      children: [
        // ── Slot artwork (Hero + animasi shrink) ──
        Positioned(
          key: const ValueKey('wideAlbumCover'),
          left: artwork.left,
          top: artwork.top,
          width: artwork.width,
          height: artwork.height,
          child: Opacity(
            opacity: widget.hideArtwork ? 0.0 : 1.0,
            child: Hero(
              tag: PlayerHeroTags.artwork(widget.song),
              child: SongArtwork(
                songId: widget.song.id,
                size: artwork.width,
                borderRadius: BorderRadius.zero,
                showBorder: false,
              ),
            ),
          ),
        ),

        // ── Panel kanan: judul, progress, transport, toggle lirik/antrean ──
        Positioned(
          key: const ValueKey('wideControlsPanel'),
          left: panel.left,
          top: panel.top,
          width: panel.width,
          height: panel.height,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: overlayBottom,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: showOverlay ? 0.0 : 1.0),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                  builder: (context, value, child) =>
                      Opacity(opacity: value, child: child),
                  child: IgnorePointer(
                    ignoring: showOverlay,
                    child: SingleChildScrollView(
                      // Tidak untuk di-scroll: hanya pengaman agar panel tidak
                      // pernah memunculkan RenderFlex overflow pada window yang
                      // sangat pendek. Physics-nya tidak pernah menerima drag,
                      // jadi tidak ada konflik gesture.
                      physics: const NeverScrollableScrollPhysics(),
                      child: Padding(
                        padding: EdgeInsets.only(top: panelTopInset),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Opacity(
                              opacity: headerOpacity,
                              child: PlayerSongHeader(song: widget.song),
                            ),
                            SizedBox(height: metrics.spacing),
                            Opacity(
                              opacity: progressOpacity,
                              child: PlayerProgressSection(
                                formatTime: widget.formatTime,
                              ),
                            ),
                            SizedBox(height: metrics.spacing),
                            Opacity(
                              opacity: transportOpacity,
                              child: PlayerTransportControls(
                                playbackState: widget.playbackState,
                                scale: metrics.transportScale,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Toggle lirik/antrean selalu terlihat — termasuk saat overlay
              // aktif — sehingga pengguna selalu punya jalan keluar.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: kNowPlayingSecondaryStrip,
                child: Opacity(
                  opacity: progress,
                  child: PlayerSecondaryControls(
                    song: widget.song,
                    showLyrics: showLyrics,
                    onLyricsToggle: widget.onLyricsToggle,
                    showQueue: showQueue,
                    onQueueToggle: widget.onQueueToggle,
                    spacing: (panel.width - 100).clamp(40.0, 160.0),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Overlay lirik — lebar penuh, di bawah header mini ──
        Positioned(
          key: const ValueKey('wideLyricsArea'),
          left: 16,
          right: 16,
          top: overlayTop,
          bottom: overlayBottom,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: showLyrics ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            builder: (context, value, child) =>
                Opacity(opacity: value, child: child),
            child: IgnorePointer(
              ignoring: !showLyrics,
              child: _buildLyricsContent(verticalPadding: lyricsPad),
            ),
          ),
        ),

        // ── Overlay antrean — lebar penuh, di bawah header mini ──
        Positioned(
          key: const ValueKey('wideQueueArea'),
          left: 16,
          right: 16,
          top: overlayTop,
          bottom: overlayBottom,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: showQueue ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            builder: (context, value, child) =>
                Opacity(opacity: value, child: child),
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

        // ── Tombol tampilan lirik (kanan atas) ──
        Positioned(
          key: const ValueKey('wideAppearanceButton'),
          top: 10,
          right: 27,
          child: _buildAppearanceButton(showLyrics: showLyrics),
        ),

        // ── Header mini di samping thumbnail artwork ──
        Positioned(
          key: const ValueKey('wideMiniSongHeader'),
          top: 4,
          left: 16 + _smallCoverSize + 25,
          child: _buildMiniSongHeader(context, showOverlay: showOverlay),
        ),
      ],
    );
  }

  Widget _buildLyricsContent({double? verticalPadding}) {
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
          verticalPadding: verticalPadding,
          onExpandChanged: (expanded) {
            if (_lyricsExpand == (expanded ? 1.0 : 0.0)) return;
            _lyricsDragHandle.preservePositionForViewportResize();
            setState(() {
              _lyricsExpand = expanded ? 1.0 : 0.0;
            });
          },
        );
      },
    );
  }
}
