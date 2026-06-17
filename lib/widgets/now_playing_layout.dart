import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../services/audio_playback_state.dart';
import '../services/audio_service.dart';
import '../services/player_sheet_controller.dart';
import '../services/lyrics_service.dart';
import '../themes/theme_controller.dart';
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

  static const _miniHeight = 55.0;
  static const _bottomBarHeight = 70.0;

  String _formatTime(Duration duration) {
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    final minutes = safeDuration.inMinutes.remainder(60);
    final seconds = safeDuration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _onPanStart(DragStartDetails details) {
    _panDx = 0;
    _panDy = 0;
    _swipeOffset = 0;
    _startProgress = widget.embedded ? 1 : PlayerSheetController.progress.value;
    _isHorizontal = false;
    _directionLocked = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.embedded) return;

    _panDx += details.delta.dx;
    _panDy += details.delta.dy;

    if (!_directionLocked && (_panDx.abs() > 8 || _panDy.abs() > 8)) {
      _isHorizontal = _panDx.abs() > _panDy.abs();
      _directionLocked = true;
    }
    if (!_directionLocked) return;

    final progress = PlayerSheetController.progress.value;
    if (_isHorizontal && progress < 0.08) {
      setState(() => _swipeOffset = _panDx);
      return;
    }

    final travel = MediaQuery.of(context).size.height - _miniHeight;
    final next = _startProgress - (_panDy / travel);
    PlayerSheetController.setProgress(next);
  }

  void _onPanEnd(DragEndDetails details) {
    if (widget.embedded) return;

    final progress = PlayerSheetController.progress.value;
    if (_isHorizontal && progress < 0.08) {
      final velocity = details.velocity.pixelsPerSecond.dx;
      if (_panDx < -80 || velocity < -350) {
        AudioService.skipNext();
      } else if (_panDx > 80 || velocity > 350) {
        AudioService.skipPrevious();
      }
      setState(() => _swipeOffset = 0);
    } else {
      final velocity = details.velocity.pixelsPerSecond.dy;
      if (progress > 0.42 || velocity < -250) {
        PlayerSheetController.open();
      } else {
        setState(() {
          _showLyrics = false;
          _showQueue = false;
        });
        PlayerSheetController.close();
      }
    }

    _panDx = 0;
    _panDy = 0;
    _directionLocked = false;
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, playbackState, _) {
        final song = playbackState.currentSong;
        if (song == null) return const SizedBox.shrink();

        return ValueListenableBuilder<double>(
          valueListenable: PlayerSheetController.progress,
          builder: (context, rawProgress, _) {
            final progress = widget.embedded ? 1.0 : rawProgress;
            final screenHeight = MediaQuery.of(context).size.height;
            final height = widget.embedded
                ? screenHeight
                : lerpDouble(_miniHeight, screenHeight, progress)!;

            return SizedBox(
              height: height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!widget.embedded && progress < 0.08) {
                    PlayerSheetController.open();
                  }
                },
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: _NowPlayingSurface(
                  song: song,
                  playbackState: playbackState,
                  progress: progress,
                  swipeOffset: _swipeOffset,
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
    required this.showLyrics,
    required this.showQueue,
    required this.formatTime,
    required this.onLyricsToggle,
    required this.onQueueToggle,
  });

  double _interval(double start, double end) {
    return ((progress - start) / (end - start)).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final safeTop = media.padding.top;
    final fullArtworkSize = (width - 44).clamp(260.0, 390.0).toDouble();
    final eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0).toDouble());
    final controlsIn = Curves.easeOut.transform(_interval(0.28, 1));
    final secondaryIn = Curves.easeOut.transform(_interval(0.55, 1));
    final miniControlsOut = (1 - _interval(0, 0.28)).clamp(0.0, 1.0).toDouble();
    final overlayMode = showLyrics || showQueue;

    final artworkSize = overlayMode
        ? lerpDouble(46, 55, eased)!
        : lerpDouble(46, fullArtworkSize, eased)!;
    final artworkLeft = overlayMode
        ? lerpDouble(12, 22, eased)!
        : lerpDouble(12, (width - fullArtworkSize) / 2, eased)!;
    final artworkTop = overlayMode
        ? lerpDouble(4.5, safeTop + 20, eased)!
        : lerpDouble(4.5, safeTop + 76, eased)!;
    final artworkRadius = lerpDouble(3, overlayMode ? 8 : 12, eased)!;

    final titleLeft = overlayMode
        ? artworkLeft + artworkSize + 12
        : lerpDouble(68, 32, eased)!;
    final titleTop = overlayMode
        ? artworkTop + 6
        : lerpDouble(8, artworkTop + artworkSize + 34, eased)!;
    final titleRight = overlayMode ? 70.0 : lerpDouble(112, 32, eased)!;
    final titleScale = overlayMode ? 1.0 : lerpDouble(1, 1.06, eased)!;

    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassTheme,
      builder: (context, glassTheme, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: ThemeController.glassMiniPlayer,
          builder: (context, glassMini, _) {
            final isMiniGlass = glassTheme && glassMini && progress < 0.02;

            return Material(
              color: isMiniGlass ? Colors.transparent : Color.lerp(
                  const Color(0xFF1C1C1E),
                  Colors.black,
                  eased,
                ),
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  if (progress > 0.001) ...[
                    Opacity(
                      opacity: eased,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: 22 * eased,
                          sigmaY: 22 * eased,
                        ),
                        child: AnimatedBlurredPlayerBackground(songId: song.id),
                      ),
                    ),
                    Opacity(
                      opacity: eased,
                      child: const DecoratedBox(
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
                    ),
                  ],
                  _SwipeHint(swipeOffset: swipeOffset),
                  Positioned(
                    left: artworkLeft,
                    top: artworkTop,
                    child: Transform.translate(
                      offset: Offset(swipeOffset, 0),
                      child: SongArtwork(
                        songId: song.id,
                        size: artworkSize,
                        borderRadius: BorderRadius.circular(artworkRadius),
                      ),
                    ),
                  ),
                  Positioned(
                    left: titleLeft,
                    right: titleRight,
                    top: titleTop,
                    child: Transform.scale(
                      scale: titleScale,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: lerpDouble(15, 20, eased),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Opacity(
                            opacity: overlayMode ? 1 : _interval(0.18, 1),
                            child: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: lerpDouble(12, 15, eased),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 2,
                    child: Opacity(
                      opacity: miniControlsOut,
                      child: IgnorePointer(
                        ignoring: miniControlsOut < 0.05,
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: playbackState.isPlaying
                                  ? AudioService.pause
                                  : AudioService.play,
                              icon: Icon(
                                playbackState.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                size: 34,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              onPressed: playbackState.currentIndex <
                                      playbackState.currentPlaylist.length - 1
                                  ? AudioService.skipNext
                                  : null,
                              icon: Icon(
                                Icons.skip_next,
                                size: 30,
                                color: playbackState.currentIndex <
                                        playbackState.currentPlaylist.length - 1
                                    ? Colors.white
                                    : Colors.white24,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 32,
                    right: 32,
                    top: titleTop + (overlayMode ? 86 : 78),
                    child: Opacity(
                      opacity: overlayMode ? 0 : _interval(0.22, 1),
                      child: PlayerProgressSection(formatTime: formatTime),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    top: titleTop + (overlayMode ? 142 : 144),
                    child: Opacity(
                      opacity: overlayMode ? 0 : controlsIn,
                      child: Transform.scale(
                        scale: lerpDouble(0.85, 1, controlsIn)!,
                        child: PlayerTransportControls(
                          playbackState: playbackState,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 22,
                    right: 22,
                    bottom: media.padding.bottom + 15,
                    child: Opacity(
                      opacity: secondaryIn,
                      child: IgnorePointer(
                        ignoring: secondaryIn < 0.1,
                        child: PlayerSecondaryControls(
                          song: song,
                          showLyrics: showLyrics,
                          onLyricsToggle: onLyricsToggle,
                          showQueue: showQueue,
                          onQueueToggle: onQueueToggle,
                        ),
                      ),
                    ),
                  ),
                  if (overlayMode)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: safeTop + 88,
                      bottom: 80,
                      child: Opacity(
                        opacity: secondaryIn,
                        child: _NowPlayingOverlay(
                          showLyrics: showLyrics,
                          song: song,
                          playbackState: playbackState,
                          onQueueClose: onQueueToggle,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SwipeHint extends StatelessWidget {
  final double swipeOffset;

  const _SwipeHint({required this.swipeOffset});

  @override
  Widget build(BuildContext context) {
    final swipeFraction = (swipeOffset.abs() / 80).clamp(0.0, 1.0).toDouble();
    if (swipeFraction <= 0.05) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      bottom: 0,
      left: swipeOffset < 0 ? null : 14,
      right: swipeOffset < 0 ? 14 : null,
      child: Opacity(
        opacity: swipeFraction,
        child: Icon(
          swipeOffset < 0 ? Icons.skip_next : Icons.skip_previous,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

class _NowPlayingOverlay extends StatelessWidget {
  final bool showLyrics;
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final VoidCallback onQueueClose;

  const _NowPlayingOverlay({
    required this.showLyrics,
    required this.song,
    required this.playbackState,
    required this.onQueueClose,
  });

  @override
  Widget build(BuildContext context) {
    if (showLyrics) {
      return FutureBuilder<LyricsResult>(
        future: LyricsService.fetchLyrics(
          title: song.title,
          artist: song.artist,
          filePath: song.path.isNotEmpty ? song.path : null,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                color: Colors.white24,
                strokeWidth: 2,
              ),
            );
          }

          final result = snapshot.data ?? const LyricsResult([], LyricsSource.none);
          if (result.isEmpty) {
            return Center(
              child: Text(
                'Tidak ada lirik untuk lagu ini',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 15,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            itemCount: result.lines.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  result.lines[index].text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 18,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          );
        },
      );
    }

    final playlist = playbackState.currentPlaylist;
    if (playlist.isEmpty) {
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

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: playlist.length,
      onReorder: AudioService.reorderQueue,
      itemBuilder: (context, index) {
        final queueSong = playlist[index];
        final isCurrent = index == playbackState.currentIndex;
        return ListTile(
          key: ValueKey('queue_${queueSong.id}_$index'),
          leading: SongArtwork(
            songId: queueSong.id,
            size: 44,
            borderRadius: BorderRadius.circular(6),
          ),
          title: Text(
            queueSong.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrent ? const Color(0xFFF92D48) : Colors.white,
              fontSize: 14,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          subtitle: Text(
            queueSong.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
          ),
          onTap: () {
            AudioService.playFromCurrentQueue(index);
            onQueueClose();
          },
        );
      },
    );
  }
}
