part of '../../home_sections.dart';

class _AlbumCard extends StatelessWidget {
  final _AlbumGroup album;
  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:
          () => Navigator.pushNamed(
            context,
            '/album',
            arguments: {'album': album.songs.first, 'songs': album.songs},
          ),
      child: Container(
        margin: const EdgeInsets.only(right: 10, left: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Album',
              style: TextStyle(
                color: Color.fromARGB(255, 153, 153, 153),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 7),
            ClipPath(
              clipper: const ShapeBorderClipper(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(15),
                    topRight: Radius.circular(15),
                  ),
                ),
              ),
              child: SongArtwork(
                songId: album.coverSongId,
                size: 250,
                borderRadius: BorderRadius.zero,
              ),
            ),
            ClipPath(
              clipper: const ShapeBorderClipper(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(15),
                    bottomRight: Radius.circular(15),
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                height: 70,
                width: 250,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 53, 53, 53),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Padding(padding: EdgeInsets.only(top: 1)),
                    Text(
                      album.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(album.artist, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
