part of '../detail_sections.dart';

class AlbumHero extends StatelessWidget {
  const AlbumHero({super.key, required this.album});

  final LocalSong album;

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      if (album.genre != null && album.genre!.isNotEmpty) album.genre!,
      if (album.year != null) album.year.toString(),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
      child: Column(
        children: [
          // Artwork — centered, ~220px
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SongArtwork(
              songId: album.id,
              size: 220,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 16),

          // Album title
          Text(
            album.album,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),

          // Artist name
          Text(
            album.albumArtist ?? album.artist,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 4),

          // Meta: Genre • Year • 🔊 Lossless
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (metaParts.isNotEmpty) ...[
                Text(
                  metaParts.join(' • '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8E8E93),
                  ),
                ),
                const Text(
                  ' • ',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                ),
              ],
              const Icon(Icons.wifi, size: 13, color: Color(0xFF8E8E93)),
              const SizedBox(width: 3),
              const Text(
                'Lossless',
                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Artist hero — artwork lagu sebagai latar belakang ─────────────────────
