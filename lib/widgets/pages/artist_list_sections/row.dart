part of '../artist_list_sections.dart';

class ArtistListRow extends StatelessWidget {
  const ArtistListRow({super.key, required this.artist});

  final ArtistInfo artist;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final songCount = artist.songs.length;
    final subtitle = '$songCount ${songCount == 1 ? 'lagu' : 'lagu'}';

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/artist', arguments: artist.songs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Artwork kotak penuh lebar, rounded corners
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SongArtwork(
                songId: artist.coverSongId,
                size: 300,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Nama artis
          Text(
            artist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,  
            style: TextStyle(
              color: c.primaryLabel,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 1),

          // Subtitle — abu-abu
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,  
            style: TextStyle(
              color: c.secondaryLabel,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
