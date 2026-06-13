import 'package:flutter/material.dart';

import '../models/local_song.dart';
import 'local_song_card.dart';

/// Carousel horizontal lagu-lagu lokal — pengganti SongCarousel berbasis Map + network image.
/// Tinggi tetap 250 agar layout halaman tidak berubah.
class LocalSongCarousel extends StatelessWidget {
  final List<LocalSong> songs;

  const LocalSongCarousel({
    super.key,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(10),
        itemCount: songs.length,
        itemBuilder: (context, index) => LocalSongCard(
          song: songs[index],
          playlist: songs,
          index: index,
        ),
      ),
    );
  }
}

/// Widget yang me-load lagu dari Future lalu menampilkan [LocalSongCarousel].
/// Menampilkan loading indicator saat memuat, SizedBox kosong jika kosong.
class FutureLocalSongCarousel extends StatelessWidget {
  final Future<List<LocalSong>> future;

  const FutureLocalSongCarousel({super.key, required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LocalSong>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 250,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return LocalSongCarousel(songs: snapshot.data ?? const []);
      },
    );
  }
}
