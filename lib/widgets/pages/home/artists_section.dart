part of '../home_sections.dart';

class _LocalArtistsSection extends StatefulWidget {
  const _LocalArtistsSection();

  @override
  State<_LocalArtistsSection> createState() => _LocalArtistsSectionState();
}

class _LocalArtistsSectionState extends State<_LocalArtistsSection> {
  List<_ArtistGroup> _artists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final songs = await MediaStoreService.getSongs();
      final playCounts = await HistoryService.getArtistPlayCounts();

      final artistMap = <String, List<LocalSong>>{};
      for (final song in songs) {
        artistMap.putIfAbsent(song.artist, () => []).add(song);
      }

      final artists = artistMap.entries
          .map((e) => _ArtistGroup(name: e.key, songs: e.value))
          .toList()
        ..sort((a, b) {
          final ca = (playCounts[a.name] as num?)?.toInt() ?? 0;
          final cb = (playCounts[b.name] as num?)?.toInt() ?? 0;
          return cb != ca ? cb.compareTo(ca) : a.name.compareTo(b.name);
        });

      if (mounted) setState(() { _artists = artists; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_artists.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _artists.length,
        itemBuilder: (context, index) =>
            _ArtistCard(artist: _artists[index]),
      ),
    );
  }
}

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
                  borderRadius: BorderRadius.all(Radius.circular(200)),
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
                const Icon(Icons.star,
                    color: Color.fromARGB(255, 255, 0, 0)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
