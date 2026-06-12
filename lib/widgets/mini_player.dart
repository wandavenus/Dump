import 'package:flutter/material.dart';
import '../services/audio_playback_state.dart';
import '../models/local_song.dart';
import '../services/audio_service.dart';
import '../services/player_sheet_controller.dart';
import 'player/player_hero_tags.dart';
import 'song_artwork.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

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
                      child: _MiniPlayerBody(
                        song: song,
                        playbackState: playbackState,
                        anim: value,
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

  const _MiniPlayerBody({
    required this.song,
    required this.playbackState,
    required this.anim,
  });

  @override
  Widget build(BuildContext context) {
    final canGoNext =
        playbackState.currentIndex < playbackState.currentPlaylist.length - 1;

    final artworkSize = 46 - (6 * anim);

    return Material(
      color: const Color(0xFF1C1C1E),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -250) {
            PlayerSheetController.open();
          }
        },
        child: SizedBox(
          height: 55,
          child: Padding(
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
                          color: canGoNext ? Colors.white : Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openFullPlayer() {
    PlayerSheetController.open();
  }
}