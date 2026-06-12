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

        return _MiniPlayerBody(
          song: song,
          playbackState: playbackState,
        );
      },
    );
  }
}

class _MiniPlayerBody extends StatelessWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;

  const _MiniPlayerBody({
    required this.song,
    required this.playbackState,
  });

  @override
  Widget build(BuildContext context) {
    final canGoNext =
        playbackState.currentIndex < playbackState.currentPlaylist.length - 1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,

      // TAP → open full player
      onTap: _openFullPlayer,

      // SWIPE UP → open full player (gesture trigger)
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -500) {
          PlayerSheetController.open();
        }
      },

      child: Material(
        color: const Color(0xFF1C1C1E),
        child: SizedBox(
          height: 55,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Hero(
                        tag: PlayerHeroTags.artwork(song),
                        child: SongArtwork(
                          songId: song.id,
                          size: 46,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
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
                    ],
                  ),
                ),

                IconButton(
                  onPressed: playbackState.isLoading
                      ? null
                      : () {
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
        ),
      ),
    );
  }

  void _openFullPlayer() {
    PlayerSheetController.open();
  }
}