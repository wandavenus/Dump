part of '../home_sections.dart';

class _LocalAlbumsSection extends StatefulWidget {
  const _LocalAlbumsSection();

  @override
  State<_LocalAlbumsSection> createState() => _LocalAlbumsSectionState();
}

class _LocalAlbumsSectionState extends State<_LocalAlbumsSection> {
  List<_AlbumGroup> _albums = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final songs = await MediaStoreService.getSongs();
      final map = <int, List<LocalSong>>{};
      for (final song in songs) {
        map.putIfAbsent(song.albumId, () => []).add(song);
      }
      final albums = map.entries
          .map((e) => _AlbumGroup(albumId: e.key, songs: e.value))
          .toList();
      if (mounted) setState(() { _albums = albums; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 371,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_albums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, top: 9),
          child: Text(
            'Top Picks For You',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 371,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            itemCount: _albums.length,
            itemBuilder: (context, index) =>
                _AlbumCard(album: _albums[index]),
          ),
        ),
      ],
    );
  }
}

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
                  gradient: LinearGradient(
                    colors: [
                      Color.fromARGB(255, 83, 83, 83),
                      Color.fromARGB(255, 36, 36, 36),
                    ],
                    stops: [0, 1],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
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
