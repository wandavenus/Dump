import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
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
            CupertinoIcons.backward_fill,
            size: 64,
            color: Colors.white,
          ),
          onPressed: hasPlaylist ? AudioService.skipPrevious : null,
        ),
        const SizedBox(width: 15),
        IconButton(
          icon: Icon(
            playbackState.isPlaying
                ? CupertinoIcons.pause_fill
                : CupertinoIcons.arrowtriangle_right_fill,
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
            CupertinoIcons.forward_fill,
            size: 64,
            color: Colors.white,
          ),
          onPressed: hasPlaylist ? AudioService.skipNext : null,
        ),
      ],
    );
  }
}
