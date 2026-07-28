part of '../../library_sections.dart';

/// Banner card used in the Daftar Putar (Frequently Played) tab.
///
/// Shows a full-width 16:9 artwork, song title, artist, and play count.
class _PlaylistBannerCard extends StatelessWidget {
  const _PlaylistBannerCard({
    required this.song,
    required this.playCount,
    required this.onTap,
    required this.onLongPress,
  });

  final LocalSong song;
  final int playCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork banner — full width, landscape rectangle
            AspectRatio(
              aspectRatio: 16 / 9,
              child: SongArtwork(
                songId: song.id,
                size: 600,
                borderRadius: BorderRadius.circular(10),
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            // Song title
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.of(context).primaryLabel,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),
            // Artist • play count
            Text(
              playCount > 0
                  ? '${song.artist} • Diputar ${playCount}x'
                  : song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.of(context).secondaryLabel,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
