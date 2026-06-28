part of '../library_sections.dart';

class _LibraryDetailPage extends StatefulWidget {
  const _LibraryDetailPage({required this.destination});

  final _LibraryDestination destination;

  @override
  State<_LibraryDetailPage> createState() => _LibraryDetailPageState();
}

class _LibraryDetailPageState extends State<_LibraryDetailPage> {
  late Future<List<LocalSong>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = MediaStoreService.getSongs();
  }

  String get _title => switch (widget.destination) {
    _LibraryDestination.playlist => 'Daftar Putar',
    _LibraryDestination.artists => 'Artis',
    _LibraryDestination.albums => 'Album',
    _LibraryDestination.songs => 'Lagu',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: _title,
        scrollOffset: 100,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: const [],
      ),
      body: FutureBuilder<List<LocalSong>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final songs = snapshot.data ?? const <LocalSong>[];
          if (songs.isEmpty) return _empty();

          return switch (widget.destination) {
            _LibraryDestination.playlist => _frequentSongs(songs),
            _LibraryDestination.artists => _artistSongs(songs),
            _LibraryDestination.albums => _albumCards(songs),
            _LibraryDestination.songs => _songsList(songs),
          };
        },
      ),
    );
  }

  Widget _empty() => const Center(
    child: Text(
      'Tidak ada lagu lokal ditemukan',
      style: TextStyle(color: Colors.white70),
    ),
  );

  FutureBuilder<Map<String, dynamic>> _frequentSongs(List<LocalSong> songs) {
    return FutureBuilder<Map<String, dynamic>>(
      future: HistoryService.getPlayCounts(),
      builder: (context, snapshot) {
        final counts = snapshot.data ?? const <String, dynamic>{};
        final sorted = List<LocalSong>.from(songs)..sort(
          (a, b) => ((counts[b.id.toString()] ?? 0) as num).compareTo(
            (counts[a.id.toString()] ?? 0) as num,
          ),
        );
        return _songListView(
          sorted,
          subtitleBuilder: (song) {
            final count = (counts[song.id.toString()] ?? 0) as num;
            return '${song.artist} • Diputar ${count.toInt()}x';
          },
        );
      },
    );
  }

  Widget _artistSongs(List<LocalSong> songs) =>
      _songListView(songs, subtitleBuilder: (song) => song.artist);

  Widget _albumCards(List<LocalSong> songs) {
    final albums = <String, List<LocalSong>>{};
    for (final song in songs) {
      albums.putIfAbsent('${song.albumId}-${song.album}', () => []).add(song);
    }
    final entries =
        albums.values.toList()
          ..sort((a, b) => a.first.album.compareTo(b.first.album));

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final albumSongs = entries[index];
        final album = albumSongs.first;
        return GestureDetector(
          onTap:
              () => Navigator.pushNamed(
                context,
                '/album',
                arguments: {'album': album, 'songs': albumSongs},
              ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SongArtwork(
                  songId: album.id,
                  size: 130,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 10),
                Text(
                  album.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${album.artist} • ${albumSongs.length} lagu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _songsList(List<LocalSong> songs) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: _actionCard(
                CupertinoIcons.shuffle,
                () => _playShuffled(songs),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionCard(
                CupertinoIcons.repeat,
                AudioService.cycleLoopMode,
              ),
            ),
          ],
        ),
      ),
      Expanded(child: _songListView(songs)),
    ],
  );

  Widget _actionCard(IconData icon, Future<void> Function() onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(child: Icon(icon, color: const Color(0xFFF92D48))),
      ),
    );
  }

  Widget _songListView(
    List<LocalSong> songs, {
    String Function(LocalSong song)? subtitleBuilder,
  }) {
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder:
          (context, index) => ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            leading: SongArtwork(songId: songs[index].id, size: 55),
            title: Text(
              songs[index].title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              subtitleBuilder?.call(songs[index]) ?? songs[index].artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _playAt(songs, index),
          ),
    );
  }

  Future<void> _playAt(List<LocalSong> songs, int index) async {
    await AudioService.playSongAt(playlist: songs, index: index);
    PlayerPanelController.instance.open();
  }

  Future<void> _playShuffled(List<LocalSong> songs) async {
    final shuffled = List<LocalSong>.from(songs)..shuffle();
    await _playAt(shuffled, 0);
  }
}
