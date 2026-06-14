part of '../albums_section.dart';

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
