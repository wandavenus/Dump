import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../services/audio_service.dart';

class PlayerTransportControls extends StatefulWidget {
  /// Faktor ukuran ikon untuk window pendek (tata letak dua kolom lanskap).
  /// 1.0 = ukuran asli yang dipakai di potret.
  final double scale;

  const PlayerTransportControls({super.key, this.scale = 1.0});

  @override
  State<PlayerTransportControls> createState() =>
      _PlayerTransportControlsState();
}

class _PlayerTransportControlsState extends State<PlayerTransportControls> {
  late bool _isPlaying;
  late bool _hasPlaylist;

  @override
  void initState() {
    super.initState();
    final state = AudioService.playbackState.value;
    _isPlaying = state.isPlaying;
    _hasPlaylist = state.currentPlaylist.isNotEmpty;
    AudioService.playbackState.addListener(_onPlaybackStateChanged);
  }

  void _onPlaybackStateChanged() {
    final state = AudioService.playbackState.value;
    final isPlaying = state.isPlaying;
    final hasPlaylist = state.currentPlaylist.isNotEmpty;

    // Position ticks and unrelated metadata updates must not rebuild the
    // transport row. Only the two derived values used by this widget matter.
    if (isPlaying == _isPlaying && hasPlaylist == _hasPlaylist) return;

    setState(() {
      _isPlaying = isPlaying;
      _hasPlaylist = hasPlaylist;
    });
  }

  @override
  void dispose() {
    AudioService.playbackState.removeListener(_onPlaybackStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconScale = widget.scale.clamp(0.5, 1.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            CupertinoIcons.backward_fill,
            size: 48 * iconScale,
            color: Colors.white,
          ),
          onPressed: _hasPlaylist ? AudioService.skipPrevious : null,
        ),
        SizedBox(width: 35 * iconScale),
        IconButton(
          icon: Icon(
            _isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
            size: 58 * iconScale,
            color: Colors.white,
          ),
          onPressed: () {
            if (_isPlaying) {
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
          onPressed: _hasPlaylist ? AudioService.skipNext : null,
        ),
      ],
    );
  }
}
