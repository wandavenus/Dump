part of '../../home_sections.dart';

class _LocalAlbumsSectionState extends State<_LocalAlbumsSection> {
  List<_AlbumGroup> _albums = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  void _onRescan() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    MediaStoreService.rescanNotifier.removeListener(_onRescan);
    super.dispose();
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

  // Caption di atas tiap kartu, meniru gaya "Listen Again" / "More from
  // [Artist]" pada referensi: kartu pertama = ajakan dengarkan lagi,
  // kartu selanjutnya = rekomendasi dari artis album tersebut.
  String _captionFor(int index) {
    if (index == 0) return 'Dengarkan Lagi';
    return 'Lainnya dari ${_albums[index].artist}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 368,
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
          height: 368,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            itemCount: _albums.length,
            itemBuilder: (context, index) => _AlbumCard(
              album: _albums[index],
              caption: _captionFor(index),
            ),
          ),
        ),
      ],
    );
  }
}
