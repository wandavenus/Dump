part of '../artist_list_sections.dart';

class _ArtistListContentState extends State<ArtistListContent> {
  List<ArtistInfo> _artists = [];
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
      final artistMap = <String, List<LocalSong>>{};
      for (final song in songs) {
        artistMap.putIfAbsent(song.artist, () => []).add(song);
      }
      final artists = artistMap.entries
          .map((e) => ArtistInfo(name: e.key, songs: e.value))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (mounted) setState(() { _artists = artists; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_artists.isEmpty) {
      return Center(
        child: Text(context.l10n.noArtistsFound,
            style: TextStyle(color: c.secondaryLabel)),
      );
    }

    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        // Header — judul tidak diubah
        const SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LargePageTitle(title: context.l10n.favoriteArtists),
              HeaderDivider(),
            ],
          ),
        ),

        // Grid 2 kolom
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 16,
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => ArtistListRow(artist: _artists[index]),
              childCount: _artists.length,
            ),
          ),
        ),
      ],
    );
  }
}
