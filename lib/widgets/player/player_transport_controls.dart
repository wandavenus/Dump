import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../services/audio_playback_state.dart';
import '../../services/audio_service.dart';

class PlayerTransportControls extends StatelessWidget {
  final AudioPlaybackState playbackState;

  /// Faktor ukuran ikon untuk window pendek (tata letak dua kolom lanskap).
  /// 1.0 = ukuran asli yang dipakai di potret.
  final double scale;

  const PlayerTransportControls({
    super.key,
    required this.playbackState,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final hasPlaylist = playbackState.currentPlaylist.isNotEmpty;
    final iconScale = scale.clamp(0.5, 1.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            CupertinoIcons.backward_fill,
            size: 48 * iconScale,
            color: Colors.white,
          ),
          onPressed: hasPlaylist ? AudioService.skipPrevious : null,
        ),
        SizedBox(width: 35 * iconScale),
        IconButton(
          icon: Icon(
            playbackState.isPlaying
                ? CupertinoIcons.pause_fill
                : CupertinoIcons.play_fill,
            size: 58 * iconScale,
            color: Colors.white,
          ),
          onPressed: () {
            if (playbackState.isPlaying) {
              unawaited(AudioService.pause());
            } else {
              unawaited(AudioService.play());
            }
          },
        ),
        SizedBox(width: 35 * iconScale),
        IconButton(
          icon: Icon(
            CupertinoIcons.forward_fill,
            size: 48 * iconScale,
            color: Colors.white,
          ),
          onPressed: hasPlaylist ? AudioService.skipNext : null,
        ),
      ],
    );
  }
}
