import 'package:flutter/material.dart';
import '../services/audio_playback_state.dart';
import '../models/local_song.dart';
import '../services/audio_service.dart';
import '../services/player_sheet_controller.dart';
import '../themes/theme_controller.dart';
import 'player/player_hero_tags.dart';
import 'song_artwork.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

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
      setState(() => _swipeOffset = _panDx);
    } else {
      _dragUp -= d.delta.dy;
      PlayerSheetController.setProgress((_dragUp / 600).clamp(0.0, 1.0));
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

        return ValueListenableBuilder<bool>(
          valueListenable: PlayerSheetController.expanded,
          builder: (context, expanded, _) {
            final t = expanded ? 1.0 : 0.0;

            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: t),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, value, _) {
                return Opacity(
                  opacity: 1 - value,
                  child: Transform.translate(
                    offset: Offset(0, 18 * value),
                    child: Transform.scale(
                      scale: 1 - (0.12 * value),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: _onPanStart,
                        onPanUpdate: _onPanUpdate,
                        onPanEnd: _onPanEnd,
                        child: _MiniPlayerBody(
                          song: song,
                          playbackState: playbackState,
                          anim: value,
                          swipeOffset: _swipeOffset,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerBody extends StatelessWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final double anim;
  final double swipeOffset;

  const _MiniPlayerBody({
    required this.song,
    required this.playbackState,
    required this.anim,
    this.swipeOffset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final canGoNext =
        playbackState.currentIndex < playbackState.currentPlaylist.length - 1;
    final canGoPrev = playbackState.currentIndex > 0;
    final artworkSize = 46 - (6 * anim);
    final swipeFraction = (swipeOffset.abs() / 80).clamp(0.0, 1.0);

    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassMiniPlayer,
      builder: (context, glassComp, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: ThemeController.glassTheme,
          builder: (context, isGlassMaster, _) {
            final isGlass = isGlassMaster && glassComp;

            return Material(
              color: isGlass ? Colors.transparent : const Color(0xFF1C1C1E),
              child: SizedBox(
                height: 55,
                child: Stack(
                  children: [
                    // Swipe direction indicator
                    if (swipeFraction > 0.05)
                      Positioned.fill(
                        child: Opacity(
                          opacity: swipeFraction * 0.18,
                          child: Container(
                            color: swipeOffset < 0
                                ? Colors.blue
                                : Colors.blue,
                          ),
                        ),
                      ),
                    if (swipeFraction > 0.05)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: swipeOffset < 0 ? null : 14,
                        right: swipeOffset < 0 ? 14 : null,
                        child: Opacity(
                          opacity: swipeFraction,
                          child: Icon(
                            swipeOffset < 0
                                ? Icons.skip_next
                                : Icons.skip_previous,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    // Main content
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _openFullPlayer,
                              child: Row(
                                children: [
                                  Hero(
                                    tag: PlayerHeroTags.artwork(song),
                                    child: SongArtwork(
                                      songId: song.id,
                                      size: artworkSize,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Transform.translate(
                                      offset: Offset(6 * anim, 0),
                                      child: Hero(
                                        tag: PlayerHeroTags.title(song),
                                        child: Material(
                                          type: MaterialType.transparency,
                                          child: Text(
                                            song.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: 1 - anim,
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: canGoPrev
                                      ? () => AudioService.skipPrevious()
                                      : null,
                                  icon: Icon(
                                    Icons.skip_previous,
                                    size: 28,
                                    color: canGoPrev
                                        ? Colors.white
                                        : Colors.white24,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    playbackState.isPlaying
                                        ? AudioService.pause()
                                        : AudioService.play();
                                  },
                                  icon: Icon(
                                    playbackState.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    size: 34,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  onPressed: canGoNext
                                      ? () => AudioService.skipNext()
                                      : null,
                                  icon: Icon(
                                    Icons.skip_next,
                                    size: 30,
                                    color: canGoNext
                                        ? Colors.white
                                        : Colors.white24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openFullPlayer() {
    PlayerSheetController.open();
  }
}
