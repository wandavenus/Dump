part of '../../home_sections.dart';

class _LocalArtistsSectionState extends State<_LocalArtistsSection> {
  List<_ArtistGroup> _artists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Synchronous first-frame init: build the artist list immediately from
    // the warm-up caches (songs + artist play counts) so the first build()
    // renders content instead of a spinner.
    final cachedSongs = MediaStoreService.cachedSongs;
    final cachedCounts = HistoryService.cachedArtistCounts;
    if (cachedSongs != null) {
      _artists = _buildArtists(cachedSongs, cachedCounts ?? {});
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

  List<_ArtistGroup> _buildArtists(
    List<LocalSong> songs,
    Map<String, dynamic> playCounts,
  ) {
    final artistMap = <String, List<LocalSong>>{};
    for (final song in songs) {
      artistMap.putIfAbsent(song.artist, () => []).add(song);
    }
    return artistMap.entries
        .map((e) => _ArtistGroup(name: e.key, songs: e.value))
        .toList()
      ..sort((a, b) {
        final ca = (playCounts[a.name] as num?)?.toInt() ?? 0;
        final cb = (playCounts[b.name] as num?)?.toInt() ?? 0;
        return cb != ca ? cb.compareTo(ca) : a.name.compareTo(b.name);
      });
  }

  Future<void> _load() async {
    try {
      final songs = await MediaStoreService.getSongs();
      final playCounts = await HistoryService.getArtistPlayCounts();
      final artists = _buildArtists(songs, playCounts);
      if (mounted) {
        setState(() {
          _artists = artists;
          _isLoading = false;
        });
      }
    } on Exception catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
        padding: const EdgeInsets.all(10),
        itemCount: _artists.length,
        itemBuilder: (context, index) => _ArtistCard(artist: _artists[index]),
      ),
    );
  }
}
