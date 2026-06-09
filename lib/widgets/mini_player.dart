import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../pages/music_player.dart';
import '../services/audio_service.dart';
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

    return Material(
      color: const Color(0xFF1C1C1E),
      child: InkWell(
        onTap: () => _openFullPlayer(context),
        child: SizedBox(
          height: 55,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Hero(
                  tag: PlayerHeroTags.artwork(song),
                  child: SongArtwork(
                    albumId: song.albumId,
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
                IconButton(
                  onPressed: playbackState.isLoading
                      ? null
                      : () {
                          playbackState.isPlaying
                              ? AudioService.pause()
                              : AudioService.play();
                        },
                  icon: Icon(
                    playbackState.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 34,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: canGoNext ? () => AudioService.skipNext() : null,
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

  void _openFullPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const MusicPlayer();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
