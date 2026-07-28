part of '../../home_sections.dart';

class _LocalAlbumsSectionState extends State<_LocalAlbumsSection> {
  List<_AlbumGroup> _albums = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Synchronous first-frame init: if MediaStoreService.warmUp() already
    // populated the song cache, build the album list right now so the very
    // first build() call renders content instead of a spinner.
    final cached = MediaStoreService.cachedSongs;
    if (cached != null) {
      _albums = _buildAlbums(cached);
      _isLoading = false;
    }
    unawaited(_load());
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  void _onRescan() {
    if (mounted) unawaited(_load());
  }

  @override
  void dispose() {
    MediaStoreService.rescanNotifier.removeListener(_onRescan);
    super.dispose();
  }

  List<_AlbumGroup> _buildAlbums(List<LocalSong> songs) {
    final map = <int, List<LocalSong>>{};
    for (final song in songs) {
      map.putIfAbsent(song.albumId, () => []).add(song);
    }
    return map.entries
        .map((e) => _AlbumGroup(albumId: e.key, songs: e.value))
        .toList();
  }

  Future<void> _load() async {
    try {
      final songs = await MediaStoreService.getSongs();
      final albums = _buildAlbums(songs);
      if (mounted)
        setState(() {
          _albums = albums;
          _isLoading = false;
        });
    } on Exception catch (e) {
      LogService.warn('AlbumsSection', 'Failed to load albums: $e');
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  // Caption di atas tiap kartu, meniru gaya "Listen Again" / "More from
  // [Artist]" pada referensi: kartu pertama = ajakan dengarkan lagi,
  // kartu selanjutnya = rekomendasi dari artis album tersebut.
  String _captionFor(BuildContext context, int index) {
    if (index == 0) return context.l10n.listenAgain;
    return context.l10n.moreFromArtist(_albums[index].artist);
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
        Padding(
          padding: EdgeInsets.only(left: kPageLeftPadding, top: 13),
          child: Text(
            context.l10n.topPicks,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 368,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(kListLeftPadding, 2, 10, 10),
            itemCount: _albums.length > 5 ? 5 : _albums.length,
            itemBuilder: (context, index) => _AlbumCard(
              album: _albums[index],
              caption: _captionFor(context, index),
            ),
          ),
        ),
      ],
    );
  }
}
