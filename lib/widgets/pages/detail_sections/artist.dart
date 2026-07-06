part of '../detail_sections.dart';

class ArtistHero extends StatelessWidget {
  const ArtistHero({super.key, required this.songs});

  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    final artistName = songs.first.artist;

    // Hitung jumlah album unik
    final albumCount = songs.map((s) => s.album).toSet().length;
    final metaParts = <String>[
      '${songs.length} lagu',
      '$albumCount ${albumCount == 1 ? 'album' : 'album'}',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
      child: Column(
        children: [
          // Artwork centered — sama persis dengan AlbumHero
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SongArtwork(
              songId: songs.first.id,
              size: 220,
              borderRadius: BorderRadius.circular(12),
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
            metaParts.join(' • '),
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
