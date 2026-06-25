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
  final _queueScrollController  = ScrollController();

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

    return Padding(
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
  offset: Offset(
  0,
  20 * (1 - progress),
),
  child: Opacity(
    opacity: ((progress - 0.15) / 0.85)
    .clamp(0.0, 1.0),
    child: PlayerSongHeader(
  song: widget.song,
),
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
                            final ctrl = showLyrics
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
        stops: [
          0.0,
          0.20,
          0.88,
          1.0,
        ],
      ).createShader(rect);
    },
    blendMode: BlendMode.dstIn,
   child : AnimatedCrossFade(
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
    velocity: const Velocity(
      pixelsPerSecond: Offset(25, 0),
    ),
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
                      ),
                    ),

                    // ── Album cover — AnimatedPositioned + AnimatedContainer ───
                    AnimatedPositioned(
                      duration: _animDuration,
                      curve: _animCurve,
                      top: showOverlay
                      ? -0.5
                      : lerpDouble(
                      sh - 140,
                      coverTop,
                      progress,
                      )!,
                      left: showOverlay
                      ? 16
                      : lerpDouble(
                      22.0,
                      coverLeft,
                      progress,
                      )!,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: widget.hideArtwork ? 0.0 : 1.0,
                        child: AnimatedContainer(
                        duration: _animDuration,
                        curve: _animCurve,
                        width: showOverlay
    ? _smallCoverSize
    : lerpDouble(
        70,
        largeCoverSize,
        progress,
      )!,

height: showOverlay
    ? _smallCoverSize
    : lerpDouble(
        70,
        largeCoverSize,
        progress,
      )!,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
  borderRadius: BorderRadius.circular(
    showOverlay
        ? 3
        : lerpDouble(
            3,
            3,
            progress,
          )!,
  ),
  color: Colors.black,
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: 0.0 + (0.20 * progress),
      ),
      blurRadius: 0.0 + (10 * progress),
      spreadRadius: 0.0 + (0.2 * progress),
      offset: Offset(
        0,
        0 + (3 * progress),
      ),
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
          onVerticalDragUpdate: (showLyrics || showQueue)
              ? (d) {
                  final ctrl = showLyrics
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
                              opacity: ((progress - 0.2) / 0.8)
                                  .clamp(0.0, 1.0),
                              child: Transform.translate(
                                offset: const Offset(0, -15),
                                child: PlayerProgressSection(
                                  formatTime: widget.formatTime,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Opacity(
                              opacity: ((progress - 0.35) / 0.65)
                                  .clamp(0.0, 1.0),
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
                    PlayerUpNextCard(showOverlay: showOverlay),
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

// ─── Queue overlay body ───────────────────────────────────────────────────────

class _QueueOverlayBody extends StatefulWidget {
  final bool isVisible;
  final VoidCallback onClose;
  final ScrollController scrollController;

  const _QueueOverlayBody({
    required this.isVisible,
    required this.onClose,
    required this.scrollController,
  });

  @override
  State<_QueueOverlayBody> createState() => _QueueOverlayBodyState();
}

class _QueueOverlayBodyState extends State<_QueueOverlayBody> {
  bool _autoplayEnabled = false;
  
  @override
  void didUpdateWidget(_QueueOverlayBody old) {
    super.didUpdateWidget(old);
    // Auto-scroll to current track when the overlay becomes visible.
    if (widget.isVisible && !old.isVisible) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  void _scrollToCurrent() {
    if (!widget.scrollController.hasClients) return;
    final idx = AudioService.playbackState.value.currentIndex;
    if (idx <= 0) return;
    // Standard ListTile height (with subtitle) is ~72 px.
    // Scroll so the item above current is visible, centring the current row.
    const itemH = 72.0;
    final target = ((idx - 1) * itemH)
        .clamp(0.0, widget.scrollController.position.maxScrollExtent);
    widget.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, state, _) {
        if (state.currentPlaylist.isEmpty) {
          return Center(
            child: Text(
              'Antrian kosong',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 15,
              ),
            ),
          );
        }

        final playlist = state.currentPlaylist;
        final currentIdx = state.currentIndex;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

Padding(
  padding: const EdgeInsets.symmetric(
    horizontal: 16,
  ),
  child: Row(
    children: [
      Expanded(
        child: _QueueControlButton(
          icon: CupertinoIcons.shuffle,
          active: state.shuffleEnabled,
          onTap: AudioService.toggleShuffle,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _QueueControlButton(
          icon: state.loopMode == LoopMode.one
              ? CupertinoIcons.repeat_1
              : CupertinoIcons.repeat,
          active: state.loopMode != LoopMode.off,
          onTap: AudioService.cycleLoopMode,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _QueueControlButton(
          icon: CupertinoIcons.infinite,
          active: _autoplayEnabled,
          onTap: () => setState(() => _autoplayEnabled = !_autoplayEnabled),
        ),
      ),
    ],
  ),
),

const SizedBox(height: 17),
            
Padding(
  padding: const EdgeInsets.symmetric(
    horizontal: 16,
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Lanjutkan Memutar',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 0.5),
      Text(
        'Memutar otomatis musik serupa',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 14,
        ),
      ),
    ],
  ),
),

const SizedBox(height: 15),
                
            Expanded(
  child: ShaderMask(
    shaderCallback: (rect) {
      return const LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Colors.white,
    Colors.white,
    Colors.transparent,
  ],
  stops: [
    0.0,
    0.60,
    1.0,
  ],
).createShader(rect);
    },
    blendMode: BlendMode.dstIn,
    child: ReorderableListView.builder(
                scrollController: widget.scrollController,
                padding: const EdgeInsets.only(bottom: 16),
                dragStartBehavior: DragStartBehavior.down,
                itemCount: playlist.length,
                onReorder: AudioService.reorderQueue,
                itemBuilder: (context, index) {
                  final song = playlist[index];
                  final isCurrent = index == currentIdx;
                  return _QueueRow(
                    key: ValueKey('queue_${song.id}_$index'),
                    index: index,
                    song: song,
                    isCurrent: isCurrent,
                    onTap: () {
                      AudioService.playFromCurrentQueue(index);
                      widget.onClose();
                    },
                  );
                },
              ),  
             ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Single queue row ─────────────────────────────────────────────────────────

class _QueueRow extends StatelessWidget {
  final int index;
  final LocalSong song;
  final bool isCurrent;
  final VoidCallback onTap;

  const _QueueRow({
    super.key,
    required this.index,
    required this.song,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white10,
        highlightColor: Colors.white.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Leading: equalizer icon for current, artwork for others
              SizedBox(
                width: 44,
                height: 44,
                child: SongArtwork(
                        songId: song.id,
                        size: 44,
                        borderRadius: BorderRadius.circular(3),
                      ),
              ),
              const SizedBox(width: 12),
              // Title + artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent
                            ? const Color(0xFFFFFFFF)
                            : Colors.white,
                        fontSize: 14,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Drag handle
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    CupertinoIcons.line_horizontal_3,
                    color: Colors.white.withValues(alpha: 0.3),
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Lyrics body ─────────────────────────────────────────────────────────────

class _LyricsOverlayBody extends StatelessWidget {
  final LyricsResult result;
  final ScrollController scrollController;
  final ValueChanged<bool> onExpandChanged;

  const _LyricsOverlayBody({
    required this.result,
    required this.scrollController,
    required this.onExpandChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            final offset = notification.metrics.pixels;

            if (offset > 150) {
              onExpandChanged(true);
            } else if (offset < 50) {
              onExpandChanged(false);
            }

            return false;
          },
          child: ShaderMask(
            shaderCallback: (Rect rect) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [
                  0.0,
                  0.35,
                  0.65,
                  1.0,
                ],
              ).createShader(rect);
            },
            blendMode: BlendMode.dstIn,
            child: SyncedLyricsView(
              lyrics: result.lines,
              padding: const EdgeInsets.fromLTRB(24, 8, 48, 24),
              controller: scrollController,
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: LyricsSettings.showSource,
          builder: (_, show, _) {
            if (!show || result.source == LyricsSource.none) {
              return const SizedBox.shrink();
            }
            return Positioned(
              bottom: 8,
              left: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      result.source == LyricsSource.internet
                          ? CupertinoIcons.globe
                          : CupertinoIcons.doc_text,
                      color: Colors.white.withValues(alpha: 0.45),
                      size: 11,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      result.sourceLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─── Empty lyrics state ───────────────────────────────────────────────────────

class _EmptyLyricsOverlay extends StatelessWidget {
  final LocalSong song;
  const _EmptyLyricsOverlay({required this.song});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.music_note,
                size: 48, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'Lirik tidak ditemukan',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${song.title} · ${song.artist}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tambahkan file .lrc di folder yang sama\ndengan lagu, atau konfigurasikan folder\nlirik di Pengaturan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Appearance button (circle icon, top-right in lyrics mode) ───────────────

class _AppearanceButton extends StatelessWidget {
  const _AppearanceButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color.fromARGB(90, 100, 100, 100),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _LyricsAppearanceOverlay(),
    );
  }
}

// ─── Appearance settings sheet ────────────────────────────────────────────────

class _LyricsAppearanceOverlay extends StatelessWidget {
  const _LyricsAppearanceOverlay();

  @override
  Widget build(BuildContext context) {
    // BackdropFilter dihapus — container sudah 0.75 alpha hitam di atas
    // latar gelap full-player, blur di baliknya tidak terlihat secara visual.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
      child: ColoredBox(
        color: Colors.black,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tampilan Lirik',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  _label('Ukuran Teks'),
                  const SizedBox(height: 8),
                  const _FontSizePicker(),
                  const SizedBox(height: 16),
                  _label('Rata Teks'),
                  const SizedBox(height: 8),
                  const _AlignPicker(),
                  const SizedBox(height: 16),
                  _label('Warna Aktif'),
                  const SizedBox(height: 8),
                  const _ColorPicker(),
                  
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Tampilkan Sumber Lirik',
                            style:
                                TextStyle(color: Colors.white, fontSize: 15)),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: LyricsSettings.showSource,
                        builder: (_, v, _) => CupertinoSwitch(
                          value: v,
                          onChanged: LyricsSettings.setShowSource,
                          activeTrackColor: const Color(0xFFF92D48),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  static Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 12,
            fontWeight: FontWeight.w500),
      );
}

// ─── Font size picker ─────────────────────────────────────────────────────────

class _FontSizePicker extends StatelessWidget {
  const _FontSizePicker();

  static const _sizes = [
    (label: 'S', value: 23.0),
    (label: 'M', value: 34.0),
    (label: 'L', value: 48.0),
    (label: 'XL', value: 55.0),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.fontSize,
      builder: (_, cur, _) => Row(
        children: _sizes.map((s) {
          final active = cur == s.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setFontSize(s.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFF92D48)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  s.label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Text-align picker ────────────────────────────────────────────────────────

class _AlignPicker extends StatelessWidget {
  const _AlignPicker();

  static const _opts = [
    (label: 'Kiri', icon: Icons.format_align_left, value: 'left'),
    (label: 'Tengah', icon: Icons.format_align_center, value: 'center'),
    (label: 'Kanan', icon: Icons.format_align_right, value: 'right'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.textAlign,
      builder: (_, cur, _) => Row(
        children: _opts.map((o) {
          final active = cur == o.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setTextAlign(o.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFF92D48)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(o.icon,
                    color: active ? Colors.white : Colors.white54, size: 20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Active-colour picker ─────────────────────────────────────────────────────

class _ColorPicker extends StatelessWidget {
  const _ColorPicker();

  static const _opts = [
    (label: 'Putih', color: Colors.black, value: 'white'),
    (label: 'Merah', color: Color(0xFFF92D48), value: 'accent'),
    (label: 'Kuning', color: Color(0xFFFFD60A), value: 'yellow'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.activeColor,
      builder: (_, cur, _) => Row(
        children: _opts.map((o) {
          final active = cur == o.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setActiveColor(o.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active
                      ? o.color
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: active
                      ? null
                      : Border.all(
                          color: o.color.withValues(alpha: 0.4), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  o.label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Dim slider ───────────────────────────────────────────────────────────────

class _DimSlider extends StatelessWidget {
  const _DimSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.bgDim,
      builder: (_, v, _) => Row(
        children: [
          
          Expanded(
            child: Slider(
              value: v,
              min: 0.2,
              max: 0.95,
              
              activeColor: Colors.transparent,
              inactiveColor: Colors.transparent,
              onChanged: LyricsSettings.setBgDim,
            ),
          ),
          
        ],
      ),
    );
  }
}

// ─── Blur slider ──────────────────────────────────────────────────────────────

class _BlurSlider extends StatelessWidget {
  const _BlurSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.blurStrength,
      builder: (_, v, _) => Row(
        children: [
          
          Expanded(
            child: Slider(
              value: v,
              min: 0,
              max: 50,
              
              activeColor: Colors.transparent,
              inactiveColor: Colors.transparent,
              onChanged: LyricsSettings.setBlurStrength,
            ),
          ),
          
        ],
      ),
    );
  }
}

// ─── Queue control button (shuffle / loop / autoplay) ─────────────────────────

class _QueueControlButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _QueueControlButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  static const _activeColor   = Color(0xFF8E8E93);
  static const _inactiveColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 36,
        decoration: BoxDecoration(
          color: active
              ? _activeColor.withValues(alpha: 0.48)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 20,
            color: active ? _activeColor : _inactiveColor,
          ),
        ),
      ),
    );
  }
}
