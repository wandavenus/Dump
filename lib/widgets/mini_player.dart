import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../pages/music_player.dart';
import '../services/audio_service.dart';
import '../themes/apple_music_blur.dart';
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: AppleMusicMaterial(
        style: AppleMusicMaterialStyle.regular,
        borderRadius: BorderRadius.circular(AppleMusicRadii.floating),
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppleMusicRadii.floating),
            onTap: () => _openFullPlayer(context),
            child: SizedBox(
              height: 56,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Hero(
                          tag: PlayerHeroTags.artwork(song),
                          child: SongArtwork(
                            songId: song.id,
                            size: 46,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Hero(
                            tag: PlayerHeroTags.title(song),
                            child: Material(
                              type: MaterialType.transparency,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppleMusicColors.label,
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppleMusicColors.secondaryLabel,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
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
                            playbackState.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 31,
                            color: AppleMusicColors.label,
                          ),
                        ),
                        IconButton(
                          onPressed:
                              canGoNext ? () => AudioService.skipNext() : null,
                          icon: Icon(
                            Icons.skip_next_rounded,
                            size: 28,
                            color: canGoNext
                                ? AppleMusicColors.label
                                : AppleMusicColors.tertiaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 1.4,
                      value: playbackState.duration.inMilliseconds == 0
                          ? 0.0
                          : (playbackState.position.inMilliseconds /
                                  playbackState.duration.inMilliseconds)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                      backgroundColor: Colors.white.withOpacity(0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppleMusicColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
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
