part of '../artist_list_sections.dart';

class _ArtistListContentState extends State<ArtistListContent> {
  List<ArtistInfo> _artists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final songs = await MediaStoreService.getSongs();
      final artistMap = <String, List<LocalSong>>{};
      for (final song in songs) {
        artistMap.putIfAbsent(song.artist, () => []).add(song);
      }
      final artists =
          artistMap.entries
              .map((e) => ArtistInfo(name: e.key, songs: e.value))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (mounted) {
        setState(() {
          _artists = artists;
          _isLoading = false;
        });
      }
    } catch (_) {
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_artists.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada artis ditemukan',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      controller: widget.scrollController,
      itemCount: _artists.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LargePageTitle(title: 'Favourite Artists'),
              HeaderDivider(),
            ],
          );
        }
        return ArtistListRow(artist: _artists[index - 1]);
      },
    );
  }
}
