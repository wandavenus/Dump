import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../services/audio_service.dart';
import '../themes/liquid_glass.dart';
import '../themes/theme_controller.dart';
import 'player/player_panel_controller.dart';
import 'song_artwork.dart';

/// Card lagu lokal berukuran 170×170 — glass-aware.
class LocalSongCard extends StatelessWidget {
  final LocalSong song;
  final List<LocalSong> playlist;
  final int index;

  const LocalSongCard({
    super.key,
    required this.song,
    required this.playlist,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.allGlass,
      builder: (ctx, _) {
        final isGlass = ThemeController.isCardsGlass;

        if (isGlass) {
          return LiquidGlass(
            borderRadius: BorderRadius.circular(14),
            margin: const EdgeInsets.only(right: 10, left: 6, top: 8),
            blur: 16,
            addShadow: true,
            padding: const EdgeInsets.all(8),
            child: InkWell(
              onTap: () async {
                await AudioService.playSongAt(
                    playlist: playlist, index: index);
                PlayerPanelController.instance.open();
              },
              borderRadius: BorderRadius.circular(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SongArtwork(
                    songId: song.id,
                    size: 154,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 154,
                    child: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.normal,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return InkWell(
          onTap: () async {
            await AudioService.playSongAt(playlist: playlist, index: index);
            PlayerPanelController.instance.open();
          },
          child: Container(
            margin: const EdgeInsets.only(right: 10, left: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                SongArtwork(
                  songId: song.id,
                  size: 170,
                  borderRadius: BorderRadius.circular(10),
                ),
                const SizedBox(height: 2.5),
                SizedBox(
                  width: 165,
                  child: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
