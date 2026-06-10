import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/audio_playback_state.dart';
import '../../services/audio_service.dart';
import 'player_bottom_sheet_scaffold.dart';

class PlayerSecondaryControls extends StatelessWidget {
  final String lyrics;

  const PlayerSecondaryControls({super.key, required this.lyrics});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => _showLyrics(context),
            icon: const Icon(CupertinoIcons.quote_bubble, size: 26),
          ),
          IconButton(
            onPressed: () => _showQueue(context),
            icon: const Icon(CupertinoIcons.list_bullet, size: 26),
          ),
        ],
      ),
    );
  }

  void _showLyrics(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (context) {
        return PlayerBottomSheetScaffold(
          title: 'Lyrics',
          child: SingleChildScrollView(
            child: Text(
              lyrics,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, height: 2),
            ),
          ),
        );
      },
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (context) {
        return PlayerBottomSheetScaffold(
          title: 'Queue',
          child: ValueListenableBuilder<AudioPlaybackState>(
            valueListenable: AudioService.playbackState,
            builder: (context, state, _) {
              return ListView.builder(
                itemCount: state.currentPlaylist.length,
                itemBuilder: (context, index) {
                  final song = state.currentPlaylist[index];
                  final isCurrent = index == state.currentIndex;

                  return ListTile(
                    onTap: () => AudioService.playFromCurrentQueue(index),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.equalizer, color: Color(0xFFF92D48))
                        : null,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
