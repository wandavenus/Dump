part of '../player_sheet.dart';

class _PlayerSheetState extends State<PlayerSheet> {
  double _dragDy = 0;
  bool _showLyrics = false;
  bool _showQueue = false;

  // ── Playback-derived state ─────────────────────────────────────────────────
  // Tracked via listener — only setState on song-identity changes, not on
  // position ticks. This decouples the sheet's translate / blur geometry from
  // 100 ms position updates.
  LocalSong? _currentSong;
  AudioPlaybackState? _currentPlaybackState;

  @override
  void initState() {
    super.initState();
    final state = AudioService.playbackState.value;
    _currentSong = state.currentSong;
    _currentPlaybackState = state;
    AudioService.playbackState.addListener(_onPlaybackStateChanged);
  }

  @override
  void dispose() {
    AudioService.playbackState.removeListener(_onPlaybackStateChanged);
    super.dispose();
  }

  void _onPlaybackStateChanged() {
    final state = AudioService.playbackState.value;
    final song = state.currentSong;

    // Only rebuild when song identity changes. Position ticks are ignored.
    final songChanged =
        (_currentSong == null) != (song == null) ||
        (_currentSong?.id != song?.id);
    if (songChanged && mounted) {
      setState(() {
        _currentSong = song;
        _currentPlaybackState = state;
      });
    } else {
      // Keep _currentPlaybackState in sync even without setState (for next
      // rebuild triggered by other causes such as drag or lyrics toggle).
      _currentPlaybackState = state;
    }
  }

  @override
  void didUpdateWidget(covariant PlayerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded && !oldWidget.expanded) {
      _dragDy = 0;
    }
    if (!widget.expanded && (_showLyrics || _showQueue)) {
      _showLyrics = false;
      _showQueue = false;
    }
  }

  String _formatTime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _close() {
    setState(() {
      _showLyrics = false;
      _showQueue = false;
      _dragDy = 0;
    });
    widget.onCollapse?.call();
    PlayerSheetController.close();
  }

  void _toggleLyrics() {
    setState(() {
      _showLyrics = !_showLyrics;
      if (_showLyrics) _showQueue = false;
    });
  }

  void _toggleQueue() {
    setState(() {
      _showQueue = !_showQueue;
      if (_showQueue) _showLyrics = false;
    });
  }

  double get _dragProgress {
    final h = MediaQuery.sizeOf(context).height;
    return (_dragDy / (h * 0.35)).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: PlayerSheetController.progress,
      builder: (context, sheetProgress, _) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        final hiddenOffset = screenHeight * (1 - sheetProgress);
        final dragProgress = _dragProgress;
        final blurSigma = sheetProgress * 22.0;

        return IgnorePointer(
          ignoring: sheetProgress <= 0.001,
          child: Transform.translate(
            offset: Offset(0, hiddenOffset),
            child: Opacity(
              opacity: sheetProgress.clamp(0.0, 1.0).toDouble(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (_showLyrics || _showQueue)
                    ? null
                    : (details) {
                        setState(() {
                          _dragDy += details.delta.dy;
                          if (_dragDy < 0) _dragDy = 0;
                        });
                      },
                onVerticalDragEnd: (_showLyrics || _showQueue)
                    ? null
                    : (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity > 600 || dragProgress > 0.25) {
                          _close();
                        } else {
                          setState(() => _dragDy = 0);
                        }
                      },
                // _SheetBody owns the content that depends on song/playbackState.
                // It rebuilds independently of the translate/blur geometry above,
                // so position ticks do not cause the outer VLB to rerun.
                child: _SheetBody(
                  blurSigma: blurSigma,
                  song: _currentSong,
                  playbackState: _currentPlaybackState,
                  showLyrics: _showLyrics,
                  showQueue: _showQueue,
                  onLyricsToggle: _toggleLyrics,
                  onQueueToggle: _toggleQueue,
                  formatTime: _formatTime,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── _SheetBody ────────────────────────────────────────────────────────────────
// Responsibility: render the background + PlayerContent given the current song
// and playback state. Receives blurSigma from the outer progress VLB so the
// background blur stays in sync with the sheet expand/collapse animation.
//
// This class is intentionally a StatelessWidget — the playback state is now
// tracked by _PlayerSheetState and passed in as props, which eliminates the
// inner ValueListenableBuilder<AudioPlaybackState> that previously lived here
// and caused position-tick rebuilds to cascade through the entire sheet tree.
class _SheetBody extends StatelessWidget {
  final double blurSigma;
  final LocalSong? song;
  final AudioPlaybackState? playbackState;
  final bool showLyrics;
  final bool showQueue;
  final VoidCallback onLyricsToggle;
  final VoidCallback onQueueToggle;
  final String Function(Duration) formatTime;

  const _SheetBody({
    required this.blurSigma,
    required this.song,
    required this.playbackState,
    required this.showLyrics,
    required this.showQueue,
    required this.onLyricsToggle,
    required this.onQueueToggle,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final currentSong = song;
    final currentState = playbackState;

    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (currentSong != null)
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                ),
                child: AnimatedBlurredPlayerBackground(
                  songId: currentSong.id,
                ),
              ),
            )
          else
            const PlayerFallbackBackground(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromARGB(0, 0, 0, 0),
                  Color.fromARGB(0, 0, 0, 0),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: currentSong == null || currentState == null
                  ? const Center(
                      child: Text(
                        'No song selected',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    )
                  : PlayerContent(
                      song: currentSong,
                      playbackState: currentState,
                      formatTime: formatTime,
                      showLyrics: showLyrics,
                      onLyricsToggle: onLyricsToggle,
                      showQueue: showQueue,
                      onQueueToggle: onQueueToggle,
                    ),
            ),
          ),
          // Extends the lyrics/queue swipe-to-scroll gesture
          // into the system gesture-nav inset below the
          // SafeArea, without moving any visible content
          // (which stays exactly where it was before this
          // gesture-extension feature was added).
          if (currentSong != null && (showLyrics || showQueue))
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.paddingOf(context).bottom,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: (_) {
                  PlayerContent.forwardExternalDragStart();
                },
                onVerticalDragUpdate: (d) {
                  PlayerContent.forwardExternalDrag(
                    d.delta.dy,
                  );
                },
                onVerticalDragEnd: (d) {
                  PlayerContent.forwardExternalDragEnd(
                    d.primaryVelocity ?? 0,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
