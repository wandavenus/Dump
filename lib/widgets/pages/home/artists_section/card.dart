part of '../../home_sections.dart';

class _ArtistCard extends StatelessWidget {
  final _ArtistGroup artist;
  const _ArtistCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () =>
          Navigator.pushNamed(context, '/artist', arguments: artist.songs),
      child: Container(
        margin: const EdgeInsets.only(top: 20, left: 15, bottom: 20),
        child: Column(
          children: [
            ClipPath(
              clipper: const ShapeBorderClipper(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
              child: SongArtwork(
                songId: artist.coverSongId,
                size: 150,
                borderRadius: BorderRadius.zero,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(artist.name, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 5),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
