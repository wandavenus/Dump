import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../utils/constants.dart';
import 'local_song_card.dart';

/// Carousel horizontal lagu-lagu lokal — pengganti SongCarousel berbasis Map + network image.
/// Tinggi tetap 250 agar layout halaman tidak berubah.
class LocalSongCarousel extends StatelessWidget {
  final List<LocalSong> songs;

  const LocalSongCarousel({super.key, required this.songs});

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(kListLeftPadding, 10, 10, 10),
        itemCount: _songs.length > 10 ? 10 : _songs.length,
        itemBuilder: (context, index) =>
            LocalSongCard(song: songs[index], playlist: songs, index: index),
      ),
    );
  }
}
