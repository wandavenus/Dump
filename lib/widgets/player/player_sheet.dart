import 'package:flutter/material.dart';
import '../../services/audio_service.dart';
import '../../services/audio_playback_state.dart';
import '../song_artwork.dart';
import 'player_background.dart';
import 'player_content.dart';

class PlayerSheet extends StatelessWidget {
  final bool expanded;
  final VoidCallback? onCollapse;

  const PlayerSheet({
    super.key,
    required this.expanded,
    this.onCollapse,
  });

  String _formatTime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, playbackState, _) {
        final song = playbackState.currentSong;

        return Material(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (song != null)
                AnimatedBlurredPlayerBackground(songId: song.id)
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
                      : PlayerContent(
                          song: song,
                          playbackState: playbackState,
                          formatTime: _formatTime,
                          lyrics: '',
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}