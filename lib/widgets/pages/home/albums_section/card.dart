part of '../../home_sections.dart';

class _AlbumCard extends StatelessWidget {
  final _AlbumGroup album;
  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(
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

            // Full artwork + teks overlay gradient
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: SizedBox(
                width: 250,
                height: 250,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Artwork full
                    SongArtwork(
                      songId: album.coverSongId,
                      size: 250,
                      borderRadius: BorderRadius.zero,
                    ),

                    // Gradient gelap transparan di bagian bawah
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 90,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Color(0xCC000000),
                              Color(0x00000000),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Teks judul + artis di atas gradient
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            album.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            album.artist,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xCCFFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
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
