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
        margin: const EdgeInsets.only(left: kCardMarginLeft, right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            // SongArtwork owns its own clip + hairline border directly —
            // no outer ClipRRect needed (avoids a radius mismatch that
            // would otherwise clip the border's rounded corners).
            SongArtwork(
              songId: artist.coverSongId,
              size: 170,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 2.5),
            SizedBox(
              width: 165,
              child: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ),
            Text(
              '${artist.songs.length} lagu',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
