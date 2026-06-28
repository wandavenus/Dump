part of '../music_list.dart';

class _MusicListState extends State<MusicList> {
  late Future<List<LocalSong>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = MediaStoreService.getSongs();
  }

  Future<void> _refreshSongs() async {
    setState(() {
      _songsFuture = MediaStoreService.getSongs();
    });
    await _songsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const FadingTitleAppBar(title: 'Unduhan', scrollOffset: 100),
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
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
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
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  onTap: () async {
                    await AudioService.playSongAt(
                      playlist: songs,
                      index: index,
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
