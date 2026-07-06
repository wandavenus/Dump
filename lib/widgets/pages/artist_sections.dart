import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import 'detail_sections.dart';

class ArtistPageContent extends StatelessWidget {
  const ArtistPageContent({super.key, required this.songs});

  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    final bottomClearance = MediaQuery.of(context).padding.bottom + 64.5;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ArtistHero(songs: songs),
          PlayShuffleButtons(songs: songs),
          SongListSection(songs: songs),
          _ArtistFooter(songs: songs),
          SizedBox(height: bottomClearance),
        ],
      ),
    );
  }
}

class _ArtistFooter extends StatelessWidget {
  const _ArtistFooter({required this.songs});

  final List<LocalSong> songs;

  String _formatTotalDuration() {
    final total = songs.fold(Duration.zero, (sum, s) => sum + s.duration);
    final h = total.inHours;
    final m = total.inMinutes.remainder(60);
    if (h > 0) return '$h jam $m menit';
    return '$m menit';
  }

  @override
  Widget build(BuildContext context) {
    final artistName = songs.first.artist;
    final albumCount = songs.map((s) => s.album).toSet().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            artistName,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 2),
          Text(
            '${songs.length} lagu • $albumCount album',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 2),
          Text(
            _formatTotalDuration(),
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }
}
