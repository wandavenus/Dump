import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../services/audio_playback_state.dart';
import '../services/audio_service.dart';
import '../services/player_sheet_controller.dart';
import 'player/player_background.dart';
import 'player/player_progress_section.dart';
import 'player/player_secondary_controls.dart';
import 'player/player_transport_controls.dart';
import 'song_artwork.dart';

class NowPlayingLayout extends StatefulWidget {
  final bool embedded;

  const NowPlayingLayout({super.key, this.embedded = false});

  @override
  State<NowPlayingLayout> createState() => _NowPlayingLayoutState();
}

class _NowPlayingLayoutState extends State<NowPlayingLayout> {
  double _panDx = 0;
  double _panDy = 0;
  double _startProgress = 0;
  double _swipeOffset = 0;
  bool _isHorizontal = false;
  bool _directionLocked = false;
  bool _showLyrics = false;
  bool _showQueue = false;

  String _formatTime(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  void _onPanStart(DragStartDetails details) {
    _panDx = 0;
    _panDy = 0;
    _swipeOffset = 0;
    _startProgress = PlayerSheetController.progress.value;
    _isHorizontal = false;
    _directionLocked = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _panDx += details.delta.dx;
    _panDy += details.delta.dy;

    if (!_directionLocked && (_panDx.abs() > 8 || _panDy.abs() > 8)) {
      _isHorizontal = _panDx.abs() > _panDy.abs();
      _directionLocked = true;
    }
    if (!_directionLocked) return;

    if (_isHorizontal && PlayerSheetController.progress.value < 0.05) {
      setState(() => _swipeOffset = _panDx);
      return;
    }

    final height = MediaQuery.of(context).size.height;
    final next = _startProgress - (_panDy / (height - _miniHeight));
    PlayerSheetController.setProgress(next.clamp(0.0, 1.0).toDouble());
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isHorizontal && PlayerSheetController.progress.value < 0.05) {
      final vx = details.velocity.pixelsPerSecond.dx;
      if (_panDx < -80 || vx < -350) {
        AudioService.skipNext();
      } else if (_panDx > 80 || vx > 350) {
        AudioService.skipPrevious();
      }
      setState(() => _swipeOffset = 0);
    } else {
      final vy = details.velocity.pixelsPerSecond.dy;
      if (PlayerSheetController.progress.value > 0.45 || vy < -250) {
        PlayerSheetController.open();
      } else {
        _showLyrics = false;
        _showQueue = false;
        PlayerSheetController.close();
      }
    }
    _panDx = 0;
    _panDy = 0;
    _directionLocked = false;
  }

  void _toggleLyrics() => setState(() {
        _showLyrics = !_showLyrics;
        if (_showLyrics) _showQueue = false;
      });

  void _toggleQueue() => setState(() {
        _showQueue = !_showQueue;
        if (_showQueue) _showLyrics = false;
      });

  static const _miniHeight = 55.0;
  static const _miniArtwork = 46.0;

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
            final occupiesScreen = widget.embedded || progress > 0.001;
            return SizedBox(
              height: widget.embedded
                  ? double.infinity
                  : lerpDouble(_miniHeight, MediaQuery.of(context).size.height,
                      progress)!,
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (progress < 0.05) PlayerSheetController.open();
                  },
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: _NowPlayingSurface(
                    song: song,
                    playbackState: playbackState,
                    progress: widget.embedded ? 1 : progress,
                    swipeOffset: _swipeOffset,
                    showBackground: occupiesScreen,
                    showLyrics: _showLyrics,
                    showQueue: _showQueue,
                    formatTime: _formatTime,
                    onLyricsToggle: _toggleLyrics,
                    onQueueToggle: _toggleQueue,
                  ),
                ),
            );
          },
        );
      },
    );
  }
}

class _NowPlayingSurface extends StatelessWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final double progress;
  final double swipeOffset;
  final bool showBackground;
  final bool showLyrics;
  final bool showQueue;
  final String Function(Duration duration) formatTime;
  final VoidCallback onLyricsToggle;
  final VoidCallback onQueueToggle;

  const _NowPlayingSurface({
    required this.song,
    required this.playbackState,
    required this.progress,
    required this.swipeOffset,
    required this.showBackground,
    required this.showLyrics,
    required this.showQueue,
    required this.formatTime,
    required this.onLyricsToggle,
    required this.onQueueToggle,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final safeTop = media.padding.top;
    final fullArtwork = (width - 44).clamp(260.0, 390.0).toDouble();
    final miniY = 4.5;
    final fullY = safeTop + 74;
    final artSize = lerpDouble(_NowPlayingLayoutState._miniArtwork,
        fullArtwork, progress)!;
    final artLeft = lerpDouble(12, (width - fullArtwork) / 2, progress)!;
    final artTop = lerpDouble(miniY, fullY, progress)!;
    final titleLeft = lerpDouble(68, 32, progress)!;
    final titleTop = lerpDouble(8, fullY + fullArtwork + 34, progress)!;
    final miniControlsOpacity = (1 - (progress * 2)).clamp(0.0, 1.0);
    final fullOpacity = Curves.easeOut.transform(progress);

    return Material(
          color: showBackground ? Colors.black : const Color(0xFF1C1C1E),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showBackground) ...[
                Opacity(
                  opacity: progress,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: 22 * progress,
                      sigmaY: 22 * progress,
                    ),
                    child: AnimatedBlurredPlayerBackground(songId: song.id),
                  ),
                ),
                Opacity(
                  opacity: progress,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color.fromARGB(80, 0, 0, 0), Color.fromARGB(190, 0, 0, 0)],
                      ),
                    ),
                  ),
                ),
              ],
              Positioned(
                left: artLeft,
                top: artTop,
                child: Transform.translate(
                  offset: Offset(swipeOffset, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(lerpDouble(3, 14, progress)!),
                    child: SongArtwork(songId: song.id, size: artSize, borderRadius: BorderRadius.zero),
                  ),
                ),
              ),
              Positioned(
                left: titleLeft,
                right: lerpDouble(112, 32, progress)!,
                top: titleTop,
                child: Transform.scale(
                  scale: lerpDouble(1, 1.08, progress)!,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: lerpDouble(15, 22, progress), fontWeight: FontWeight.w700)),
                      Opacity(
                        opacity: progress,
                        child: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.58), fontSize: 15)),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 2,
                child: Opacity(
                  opacity: miniControlsOpacity,
                  child: Row(children: [
                    IconButton(onPressed: playbackState.isPlaying ? AudioService.pause : AudioService.play,
                        icon: Icon(playbackState.isPlaying ? Icons.pause : Icons.play_arrow, size: 34, color: Colors.white)),
                    IconButton(onPressed: AudioService.skipNext,
                        icon: const Icon(Icons.skip_next, size: 30, color: Colors.white)),
                  ]),
                ),
              ),
              Positioned(
                left: 32,
                right: 32,
                top: titleTop + 86,
                child: Opacity(
                  opacity: ((progress - .15) / .85).clamp(0.0, 1.0),
                  child: PlayerProgressSection(formatTime: formatTime),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: titleTop + 152,
                child: Opacity(
                  opacity: ((progress - .25) / .75).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: lerpDouble(.85, 1, progress)!,
                    child: PlayerTransportControls(playbackState: playbackState),
                  ),
                ),
              ),
              Positioned(
                left: 22,
                right: 22,
                bottom: lerpDouble(0, media.padding.bottom + 15, progress)!,
                child: Opacity(
                  opacity: fullOpacity,
                  child: PlayerSecondaryControls(
                    song: song,
                    showLyrics: showLyrics,
                    onLyricsToggle: onLyricsToggle,
                    showQueue: showQueue,
                    onQueueToggle: onQueueToggle,
                  ),
                ),
              ),
              if (showLyrics || showQueue)
                Positioned(
                  left: 24,
                  right: 24,
                  top: safeTop + 150,
                  bottom: 132,
                  child: Opacity(
                    opacity: progress,
                    child: Center(
                      child: Text(showLyrics ? 'Lyrics' : 'Queue', style: const TextStyle(color: Colors.white70, fontSize: 18)),
                    ),
                  ),
                ),
            ],
          ),
        );
  }
}
