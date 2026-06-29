part of '../music_list.dart';

class _MusicListState extends State<MusicList> {
  late Future<List<LocalSong>> _songsFuture;
  final _scroll = ScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _songsFuture = MediaStoreService.getSongs();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final o = _scroll.offset;
    if ((o - _offset).abs() > 0.5) setState(() => _offset = o);
  }

  Future<void> _refreshSongs() async {
    setState(() {
      _songsFuture = MediaStoreService.getSongs();
    });
    await _songsFuture;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FadingTitleAppBar(
        title: 'Unduhan',
        scrollOffset: _offset,
        actions: const [],
      ),
      body: FutureBuilder<List<LocalSong>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final songs = snapshot.data ?? const <LocalSong>[];
          if (songs.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshSongs,
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  LargePageTitle(title: 'Unduhan'),
                  HeaderDivider(),
                  SizedBox(height: 160),
                  Icon(Icons.music_note, size: 56, color: Colors.white38),
                  SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Tidak ada lagu lokal ditemukan',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshSongs,
            child: ListView.builder(
              controller: _scroll,
              itemCount: songs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LargePageTitle(title: 'Unduhan'),
                      HeaderDivider(),
                    ],
                  );
                }

                final song = songs[index - 1];

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  onTap: () async {
                    await AudioService.playSongAt(
                      playlist: songs,
                      index: index - 1,
                    );
                    PlayerPanelController.instance.open();
                  },
                  leading: Hero(
                    tag: PlayerHeroTags.artwork(song),
                    child: SongArtwork(songId: song.id, size: 55),
                  ),
                  title: Hero(
                    tag: PlayerHeroTags.title(song),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
