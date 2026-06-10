import 'package:flutter/material.dart';

import '../../services/audio_playback_state.dart';
import '../../services/audio_service.dart';

class PlayerTransportControls extends StatelessWidget {
  final AudioPlaybackState playbackState;

  const PlayerTransportControls({super.key, required this.playbackState});

  @override
  Widget build(BuildContext context) {
    final canGoPrevious = playbackState.currentIndex > 0;
    final canGoNext =
        playbackState.currentIndex < playbackState.currentPlaylist.length - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            Icons.fast_rewind_rounded,
            size: 64,
            color: canGoPrevious ? Colors.white : Colors.white24,
          ),
          onPressed: canGoPrevious ? () => AudioService.skipPrevious() : null,
        ),
        const SizedBox(width: 10),
        IconButton(
          icon: Icon(
            playbackState.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: 76,
            color: Colors.white,
          ),
          onPressed: () {
            playbackState.isPlaying
                ? AudioService.pause()
                : AudioService.play();
          },
        ),
        const SizedBox(width: 10),
        IconButton(
          icon: Icon(
            Icons.fast_forward_rounded,
            size: 64,
            color: canGoNext ? Colors.white : Colors.white24,
          ),
          onPressed: canGoNext ? () => AudioService.skipNext() : null,
        ),
      ],
    );
  }
}
