import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/audio_playback_state.dart';
import '../../services/audio_service.dart';
import '../../services/lyrics_service.dart';
import '../player/synced_lyrics_view.dart';
import 'player_bottom_sheet_scaffold.dart';

class PlayerSecondaryControls extends StatelessWidget {
  final LocalSong song;

  const PlayerSecondaryControls({
    super.key,
    required this.song,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => _showLyrics(context),
            icon: const Icon(CupertinoIcons.quote_bubble, size: 26),
          ),
          const SizedBox(width: 130),
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
          child: FutureBuilder(
            future: LyricsService.fetchLyrics(
              title: song.title,
              artist: song.artist,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final lyrics = snapshot.data ?? [];

              if (lyrics.isEmpty) {
                return const Center(
                  child: Text('Lyrics not found'),
                );
              }

              return SyncedLyricsView(
                lyrics: lyrics,
              );
            },
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
