import 'package:flutter/material.dart';

import '../../services/audio_playback_state.dart';
import '../../services/audio_service.dart';

class PlayerTransportControls extends StatelessWidget {
  final AudioPlaybackState playbackState;

  const PlayerTransportControls({super.key, required this.playbackState});

  @override
  Widget build(BuildContext context) {
    final hasPlaylist = playbackState.currentPlaylist.isNotEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(
            Icons.fast_rewind_rounded,
            size: 64,
            color: Colors.white,
          ),
          onPressed: hasPlaylist ? AudioService.skipPrevious : null,
        ),
        const SizedBox(width: 15),
        IconButton(
          icon: Icon(
            playbackState.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: 75,
            color: Colors.white,
          ),
          onPressed: () {
            playbackState.isPlaying
                ? AudioService.pause()
                : AudioService.play();
          },
        ),
        const SizedBox(width: 15),
        IconButton(
          icon: const Icon(
            Icons.fast_forward_rounded,
            size: 64,
            color: Colors.white,
          ),
          onPressed: hasPlaylist ? AudioService.skipNext : null,
        ),
      ],
    );
  }
}
