part of '../../home_sections.dart';

class _ArtistCard extends StatelessWidget {
  final _ArtistGroup artist;
  const _ArtistCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          Navigator.pushNamed(context, '/artist', arguments: artist.songs),
      child: Container(
        margin: const EdgeInsets.only(left: 6, right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SongArtwork(
                songId: artist.coverSongId,
                size: 170,
                borderRadius: BorderRadius.zero,
              ),
            ),
            const SizedBox(height: 2.5),
            SizedBox(
              width: 170,
              child: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(
              width: 170,
              child: Text(
                '${artist.songs.length} lagu',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
