part of '../artist_list_sections.dart';

class ArtistListRow extends StatelessWidget {
  const ArtistListRow({super.key, required this.artist});

  final ArtistInfo artist;

  @override
  Widget build(BuildContext context) {
    final songCount = artist.songs.length;
    final subtitle = '$songCount ${songCount == 1 ? 'lagu' : 'lagu'}';

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/artist', arguments: artist.songs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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

          // Nama artis — putih, bold
          Text(
            artist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
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
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
