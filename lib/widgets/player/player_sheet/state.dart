part of '../player_sheet.dart';

class _PlayerSheetState extends State<PlayerSheet> {
  double _dragDy = 0;
  double _dragStartProgress = 0;
  bool _showLyrics = false;
  bool _showQueue = false;

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
    final h = MediaQuery.of(context).size.height;
    return (_dragDy / (h * 0.35)).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: PlayerSheetController.progress,
      builder: (context, sheetProgress, _) {
        final screenHeight = MediaQuery.of(context).size.height;
        final hiddenOffset = (screenHeight - 55) * (1 - sheetProgress);
        final dragProgress = _dragProgress;
        final easedProgress = Curves.easeOutCubic.transform(
          sheetProgress.clamp(0.0, 1.0).toDouble(),
        );
        final blurSigma = easedProgress * 22.0;

        return IgnorePointer(
          ignoring: sheetProgress <= 0.001,
          child: Transform.translate(
            offset: Offset(0, hiddenOffset),
            child: ValueListenableBuilder<AudioPlaybackState>(
              valueListenable: AudioService.playbackState,
              builder: (context, playbackState, _) {
                final song = playbackState.currentSong;

                return Opacity(
                  opacity: (easedProgress * 1.25).clamp(0.0, 1.0).toDouble(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_showLyrics || _showQueue)
                        ? null
                        : (_) {
                            _dragStartProgress = PlayerSheetController.progress.value;
                            _dragDy = 0;
                          },
                    onVerticalDragUpdate: (_showLyrics || _showQueue)
                        ? null
                        : (details) {
                            _dragDy += details.delta.dy;
                            final travel = screenHeight - 55;
                            final next = _dragStartProgress - (_dragDy / travel);
                            PlayerSheetController.setProgress(next);
                          },
                    onVerticalDragEnd: (_showLyrics || _showQueue)
                        ? null
                        : (details) {
                            final velocity = details.primaryVelocity ?? 0;
                            if (velocity > 600 || dragProgress > 0.25) {
                              _close();
                            } else {
                              setState(() => _dragDy = 0);
                              PlayerSheetController.open();
                            }
                          },
                    child: Material(
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (song != null)
                            ClipRect(
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: blurSigma,
                                  sigmaY: blurSigma,
                                ),
                                child: AnimatedBlurredPlayerBackground(
                                  songId: song.id,
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
                                  Color.fromARGB(80, 0, 0, 0),
                                  Color.fromARGB(180, 0, 0, 0),
                                ],
                              ),
                            ),
                          ),
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: song == null
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
                                      song: song,
                                      playbackState: playbackState,
                                      formatTime: _formatTime,
                                      showLyrics: _showLyrics,
                                      onLyricsToggle: _toggleLyrics,
                                      showQueue: _showQueue,
                                      onQueueToggle: _toggleQueue,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}