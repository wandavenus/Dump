import 'package:flutter/material.dart';
import 'package:musicplayer/services/audio_service.dart';
import 'package:musicplayer/services/audio_playback_state.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/services/up_next_settings.dart';
import '../song_artwork.dart';

class PlayerUpNextCard extends StatelessWidget {
  final bool showOverlay;

  const PlayerUpNextCard({super.key, required this.showOverlay});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: UpNextSettings.showUpNextCard,
      builder: (_, settingEnabled, _) {
        return ValueListenableBuilder<AudioPlaybackState>(
          valueListenable: AudioService.playbackState,
          builder: (_, state, _) {
            final nextIdx  = AudioService.nextIndex;
            final playlist = state.currentPlaylist;
            final hasNext  = nextIdx >= 0 && nextIdx < playlist.length;
            final visible  = settingEnabled && hasNext && !showOverlay;

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axis: Axis.vertical,
                  axisAlignment: -1,
                  child: child,
                ),
              ),
              child: visible
                  ? _UpNextCardContent(
                      key: const ValueKey('up_next'),
                      song: playlist[nextIdx],
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            );
          },
        );
      },
    );
  }
}

class _UpNextCardContent extends StatelessWidget {
  final LocalSong song;

  const _UpNextCardContent({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'UP NEXT',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SongArtwork(
                    songId: song.id,
                    size: 46,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
