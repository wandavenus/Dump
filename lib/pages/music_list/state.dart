part of '../music_list.dart';

class _MusicListState extends State<MusicList> {
  late Future<List<LocalSong>> _songsFuture;
  final _scroll = ScrollController();
  final _offsetNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _songsFuture = MediaStoreService.getSongs();
    _scroll.addListener(_onScroll);
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  void _onRescan() {
    if (!mounted) return;
    setState(() {
      _songsFuture = MediaStoreService.getSongs();
    });
  }

  static const double _kAnimEnd = 140.0;

  void _onScroll() {
    final clamped = _scroll.offset.clamp(0.0, _kAnimEnd);
    if (clamped != _offsetNotifier.value) _offsetNotifier.value = clamped;
  }

  Future<void> _refreshSongs() async {
    setState(() {
      _songsFuture = MediaStoreService.getSongs();
    });
    await _songsFuture;
  }

  @override
  void dispose() {
    MediaStoreService.rescanNotifier.removeListener(_onRescan);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _offsetNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FadingTitleAppBar(
        title: 'Recently Played',
        scrollOffsetListenable: _offsetNotifier,
        actions: const [CommonActions()],
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
                  LargePageTitle(title: 'Recently Played'),
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

          final bottomClearance = MediaQuery.paddingOf(context).bottom + 64.5;
          return RefreshIndicator(
            onRefresh: _refreshSongs,
            child: ListView.separated(
              controller: _scroll,
              padding: EdgeInsets.only(bottom: bottomClearance),
              itemCount: songs.length + 1,
              separatorBuilder: (context, index) => index == 0
                  ? const SizedBox.shrink()
                  : const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0xFF48484A),
                      indent: 87,
                      endIndent: 16,
                    ),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LargePageTitle(title: 'Recently Played'),
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
                  },
                  onLongPress: () => showSongContextMenu(
                    context,
                    song: song,
                    playlist: songs,
                    index: index - 1,
                  ),
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
                    style: const TextStyle(color: Color(0xFF8E8E93)),
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
