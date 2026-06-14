part of '../artists_section.dart';

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
