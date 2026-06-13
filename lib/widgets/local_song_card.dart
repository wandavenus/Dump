import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../services/audio_service.dart';
import 'player/player_panel_controller.dart';
import 'song_artwork.dart';

/// Card lagu lokal berukuran 170×170 — pengganti SongCard berbasis Map + network image.
/// Desain visual identik dengan card lama (artwork bulat, judul, artis).
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
  }
}
