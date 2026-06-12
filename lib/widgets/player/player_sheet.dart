import 'package:flutter/material.dart';
import '../../services/audio_service.dart';
import '../../services/audio_playback_state.dart';
import '../song_artwork.dart';
import 'player_transport_controls.dart';

class PlayerSheet extends StatelessWidget {
  final bool expanded;
  final VoidCallback? onCollapse;

  const PlayerSheet({
    super.key,
    required this.expanded,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.black,
      child: ValueListenableBuilder<AudioPlaybackState>(
        valueListenable: AudioService.playbackState,
        builder: (context, playbackState, _) {
          final song = playbackState.currentSong;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 50),
              child: Center(
                child: song == null
                    ? const Text(
                        'No song selected',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SongArtwork(
                            songId: song.id,
                            size: 300,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(12),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            song.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            song.artist,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 40),
                          PlayerTransportControls(
                            playbackState: playbackState,
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}