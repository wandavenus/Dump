part of '../detail_sections.dart';

class ArtistHero extends StatelessWidget {
  const ArtistHero({super.key, required this.songs});

  final List<LocalSong> songs;

  /// Guard against empty list
  bool get _isEmpty => songs.isEmpty;

  /// Hitung jumlah album unik
  int get _albumCount => songs.map((s) => s.album).toSet().length;

  /// Build metadata string: "X lagu • X album"
  String _buildMetadata() {
    final songCount = songs.length;
    final albumCount = _albumCount;
    return '$songCount lagu • $albumCount album';
  }

  @override
  Widget build(BuildContext context) {
    if (_isEmpty) {
      return const SizedBox.shrink();
    }

    final artistName = songs.first.artist;

    return Padding(
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Artwork centered — sama persis dengan AlbumHero
          Hero(
            tag: 'artist-artwork-${songs.first.artist}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SongArtwork(
                songId: songs.first.id,
                size: 220,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Nama artis
          Text(
            artistName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),

          // Meta: X lagu • X album
          Text(
            _buildMetadata(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8E8E93),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tombol play/shuffle ───────────────────────────────────────────────────
