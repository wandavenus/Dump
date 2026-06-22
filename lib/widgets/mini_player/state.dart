part of '../mini_player.dart';

class _MiniPlayerState extends State<MiniPlayer> {
  double _dragUp = 0;
  double _panDx = 0;
  double _panDy = 0;
  bool _isHorizontal = false;
  bool _directionLocked = false;
  double _swipeOffset = 0;

  void _onPanStart(DragStartDetails d) {
    _panDx = 0;
    _panDy = 0;
    _isHorizontal = false;
    _directionLocked = false;
    _dragUp = 0;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _panDx += d.delta.dx;
    _panDy += d.delta.dy;

    if (!_directionLocked && (_panDx.abs() > 8 || _panDy.abs() > 8)) {
      _isHorizontal = _panDx.abs() > _panDy.abs();
      _directionLocked = true;
    }

    if (!_directionLocked) return;

    if (_isHorizontal) {
      final nextOffset = _panDx;

      if ((nextOffset - _swipeOffset).abs() > 2) {
        setState(() => _swipeOffset = nextOffset);
      }
    } else {
      _dragUp -= d.delta.dy;
      PlayerSheetController.setProgress((_dragUp / 600).clamp(0.0, 1.0).toDouble());
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_isHorizontal) {
      final vx = d.velocity.pixelsPerSecond.dx;
      if (_panDx < -80 || vx < -350) {
        AudioService.skipNext();
      } else if (_panDx > 80 || vx > 350) {
        AudioService.skipPrevious();
      }
      setState(() => _swipeOffset = 0);
    } else {
      final vy = d.velocity.pixelsPerSecond.dy;
      if (PlayerSheetController.progress.value > 0.35 || vy < -150) {
        PlayerSheetController.open();
      } else {
        PlayerSheetController.close();
      }
    }
    _dragUp = 0;
    _panDx = 0;
    _panDy = 0;
    _directionLocked = false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, playbackState, _) {
        final song = playbackState.currentSong;
        if (song == null) return const SizedBox.shrink();

        return ValueListenableBuilder<double>(
          valueListenable: PlayerSheetController.progress,
          builder: (context, progress, _) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: _MiniPlayerBody(
                song: song,
                playbackState: playbackState,
                anim: progress,
                swipeOffset: _swipeOffset,
              ),
            );
          },
        );
      },
    );
  }
}