part of '../player_sheet.dart';

class _PlayerSheetState extends State<PlayerSheet> {
  double _dragDy = 0;

  @override
  void didUpdateWidget(covariant PlayerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.expanded && !oldWidget.expanded) {
      _dragDy = 0;
    }
  }

  String _formatTime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _close() {
    widget.onCollapse?.call();
    PlayerSheetController.close();
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
        final hiddenOffset = screenHeight * (1 - sheetProgress);
        final dragProgress = _dragProgress;
        final blurSigma = dragProgress * 22.0;

        return IgnorePointer(
          ignoring: sheetProgress <= 0.001,
          child: Transform.translate(
            offset: Offset(0, hiddenOffset + (_dragDy * 0.5)),
            child: ValueListenableBuilder<AudioPlaybackState>(
              valueListenable: AudioService.playbackState,
              builder: (context, playbackState, _) {
                final song = playbackState.currentSong;

                return Opacity(
                  opacity: sheetProgress.clamp(0.0, 1.0).toDouble(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      setState(() {
                        _dragDy += details.delta.dy;
                        if (_dragDy < 0) _dragDy = 0;
                      });
                    },
                    onVerticalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;

                      if (velocity > 600 || dragProgress > 0.25) {
                        _close();
                      } else {
                        setState(() => _dragDy = 0);
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
                                child: AnimatedBlurredPlayerBackground(songId: song.id),
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
                                  : Transform.translate(
                                      offset: Offset(0, -dragProgress * 18),
                                      child: Transform.scale(
                                        scale: 1 - (dragProgress * 0.05),
                                        child: PlayerContent(
                                          song: song,
                                          playbackState: playbackState,
                                          formatTime: _formatTime,
                                        ),
                                      ),
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
