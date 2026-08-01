part of '../../library_sections.dart';

/// Banner card used in the Daftar Putar (Frequently Played) tab.
///
/// Shows a variable-size tile with artwork, song title, artist, and play count.
class _PlaylistBannerCard extends StatelessWidget {
  const _PlaylistBannerCard({
    required this.song,
    required this.playCount,
    required this.height,
    required this.onTap,
    required this.onLongPress,
  });

  final LocalSong song;
  final int playCount;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: height,
              child: SongArtwork(
                songId: song.id,
                size: 600,
                borderRadius: BorderRadius.circular(12),
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.of(context).primaryLabel,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              playCount > 0
                  ? '${song.artist} • Diputar ${playCount}x'
                  : song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.of(context).secondaryLabel,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
