import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import 'detail_sections.dart';

class AlbumPageContent extends StatelessWidget {
  const AlbumPageContent({
    super.key,
    required this.album,
    required this.songs,
  });

  final LocalSong album;
  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    final bottomClearance = MediaQuery.of(context).padding.bottom + 64.5;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AlbumHero(album: album),
          PlayShuffleButtons(songs: songs),
          SongListSection(songs: songs),
          _AlbumFooter(album: album, songs: songs),
          SizedBox(height: bottomClearance),
        ],
      ),
    );
  }
}

class _AlbumFooter extends StatelessWidget {
  const _AlbumFooter({required this.album, required this.songs});

  final LocalSong album;
  final List<LocalSong> songs;

  String _formatTotalDuration() {
    final total = songs.fold(Duration.zero, (sum, s) => sum + s.duration);
    final h = total.inHours;
    final m = total.inMinutes.remainder(60);
    if (h > 0) return '$h jam $m menit';
    return '$m menit';
  }

  String _formatDate() {
    final now = DateTime.now();
    final months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final year = album.year?.toString() ?? DateTime.now().year.toString();
    final artistName = album.albumArtist ?? album.artist;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDate(),
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 2),
          Text(
            '${songs.length} lagu, ${_formatTotalDuration()}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 2),
          Text(
            '℗ $year $artistName',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }
}
