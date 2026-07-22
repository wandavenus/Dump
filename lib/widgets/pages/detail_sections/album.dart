part of '../detail_sections.dart';

class AlbumHero extends StatelessWidget {
  const AlbumHero({super.key, required this.album});

  final LocalSong album;

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      if (album.genre != null && album.genre!.isNotEmpty) album.genre!,
      ?album.year?.toString(),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
      child: SizedBox(
        width: double.infinity,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
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
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.of(context).primaryLabel,
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
              color: Color(0xFFF92D48),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.of(context).secondaryLabel,
                  ),
                ),
                Text(
                  ' • ',
                  style: TextStyle(fontSize: 12, color: AppColors.of(context).secondaryLabel),
                ),
              ],
              const SizedBox(width: 3),
              Text(
                'Lossless',
                style: TextStyle(fontSize: 12, color: AppColors.of(context).secondaryLabel),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

// ─── Artist hero — artwork lagu sebagai latar belakang ─────────────────────
