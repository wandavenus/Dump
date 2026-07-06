import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/media_store_service.dart';
import '../song_artwork.dart';
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
          _MoreByArtist(currentAlbum: album),
          SizedBox(height: bottomClearance),
        ],
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

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
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
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

// ─── More by Artist ───────────────────────────────────────────────────────────

class _MoreByArtist extends StatefulWidget {
  const _MoreByArtist({required this.currentAlbum});

  final LocalSong currentAlbum;

  @override
  State<_MoreByArtist> createState() => _MoreByArtistState();
}

class _MoreByArtistState extends State<_MoreByArtist> {
  late Future<List<_AlbumGroup>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadOtherAlbums();
  }

  Future<List<_AlbumGroup>> _loadOtherAlbums() async {
    final allSongs = await MediaStoreService.getSongs();
    final artistName = widget.currentAlbum.albumArtist ?? widget.currentAlbum.artist;
    final currentAlbumName = widget.currentAlbum.album;

    // Filter songs: same artist, different album
    final artistSongs = allSongs.where((s) {
      final sArtist = s.albumArtist ?? s.artist;
      return (sArtist == artistName || s.artist == artistName) &&
          s.album != currentAlbumName;
    }).toList();

    // Group by album name
    final Map<String, List<LocalSong>> grouped = {};
    for (final s in artistSongs) {
      grouped.putIfAbsent(s.album, () => []).add(s);
    }

    return grouped.entries
        .map((e) => _AlbumGroup(name: e.key, songs: e.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final artistName =
        widget.currentAlbum.albumArtist ?? widget.currentAlbum.artist;

    return FutureBuilder<List<_AlbumGroup>>(
      future: _future,
      builder: (context, snapshot) {
        final albums = snapshot.data ?? [];
        if (albums.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: GestureDetector(
                onTap: () {
                  // Navigate to artist page
                  final artistSongs = albums
                      .expand((a) => a.songs)
                      .toList();
                  Navigator.pushNamed(
                    context,
                    '/artist',
                    arguments: artistSongs,
                  );
                },
                child: Row(
                  children: [
                    Text(
                      'More by $artistName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF8E8E93),
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),

            // Horizontal album cards
            SizedBox(
              height: 178,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16, right: 8),
                itemCount: albums.length,
                itemBuilder: (context, i) =>
                    _SmallAlbumCard(album: albums[i]),
              ),
            ),

            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ─── Compact album card ────────────────────────────────────────────────────────

class _AlbumGroup {
  final String name;
  final List<LocalSong> songs;
  const _AlbumGroup({required this.name, required this.songs});
}

class _SmallAlbumCard extends StatelessWidget {
  const _SmallAlbumCard({required this.album});

  final _AlbumGroup album;

  @override
  Widget build(BuildContext context) {
    const double cardWidth = 130;
    const double artworkSize = 130;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        '/album',
        arguments: {
          'album': album.songs.first,
          'songs': album.songs,
        },
      ),
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork square with rounded corners
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SongArtwork(
                songId: album.songs.first.id,
                size: artworkSize,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 6),

            // Album title
            Text(
              album.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),

            // Artist name
            Text(
              album.songs.first.albumArtist ?? album.songs.first.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
