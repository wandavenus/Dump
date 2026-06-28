part of '../library_sections.dart';

class _LibraryDetailPage extends StatefulWidget {
  const _LibraryDetailPage({required this.destination});

  final _LibraryDestination destination;

  @override
  State<_LibraryDetailPage> createState() => _LibraryDetailPageState();
}

class _LibraryDetailPageState extends State<_LibraryDetailPage> {
  late Future<List<LocalSong>> _songsFuture;
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  double _offset = 0;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _songsFuture = MediaStoreService.getSongs();
    _scroll.addListener(_onScroll);
    _searchController.addListener(_onSearch);
  }

  void _onScroll() {
    final o = _scroll.offset;
    if ((o - _offset).abs() > 0.5) setState(() => _offset = o);
  }

  void _onSearch() {
    final q = _searchController.text.trim().toLowerCase();
    if (q != _filter) setState(() => _filter = q);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchController.removeListener(_onSearch);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _title => switch (widget.destination) {
    _LibraryDestination.playlist => 'Daftar Putar',
    _LibraryDestination.artists  => 'Artis',
    _LibraryDestination.albums   => 'Album',
    _LibraryDestination.songs    => 'Lagu',
  };

  String get _hintText => switch (widget.destination) {
    _LibraryDestination.playlist => 'Cari di Daftar Putar',
    _LibraryDestination.artists  => 'Cari Artis',
    _LibraryDestination.albums   => 'Cari Album',
    _LibraryDestination.songs    => 'Cari Lagu',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: _title,
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
          if (songs.isEmpty) return _empty();

          return switch (widget.destination) {
            _LibraryDestination.playlist => _frequentSongs(songs),
            _LibraryDestination.artists  => _artistSongs(songs),
            _LibraryDestination.albums   => _albumCards(songs),
            _LibraryDestination.songs    => _songsList(songs),
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

  // ─── Search bar ────────────────────────────────────────────────────────────

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.search, color: Color(0xFF8E8E93), size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: false,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: const Color(0xFFF92D48),
                decoration: InputDecoration(
                  hintText: _hintText,
                  hintStyle: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchFocus.unfocus(),
                onTapOutside: (_) => _searchFocus.unfocus(),
              ),
            ),
            if (_filter.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _searchFocus.unfocus();
                },
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.cancel, color: Color(0xFF8E8E93), size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Control buttons (Queue-sheet style) ───────────────────────────────────

  Widget _controlButtons(List<LocalSong> songs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 8),
      child: ValueListenableBuilder<AudioPlaybackState>(
        valueListenable: AudioService.playbackState,
        builder: (context, state, _) {
          return Row(
            children: [
              Expanded(
                child: _controlButton(
                  icon: CupertinoIcons.shuffle,
                  active: state.shuffleEnabled,
                  onTap: () => _playShuffled(songs),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _controlButton(
                  icon: state.loopMode == LoopMode.one
                      ? CupertinoIcons.repeat_1
                      : CupertinoIcons.repeat,
                  active: state.loopMode != LoopMode.off,
                  onTap: AudioService.cycleLoopMode,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    const activeColor = Color(0xFF8E8E93);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 37,
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.48)
              : Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 20,
            color: active ? activeColor : Colors.white,
          ),
        ),
      ),
    );
  }

  // ─── Shared list header (LargePageTitle + divider + search + controls) ─────

  Widget _listHeader(List<LocalSong> songs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LargePageTitle(title: _title),
        const HeaderDivider(),
        _searchBar(),
        _controlButtons(songs),
      ],
    );
  }

  // ─── Daftar Putar ──────────────────────────────────────────────────────────

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

  // ─── Artis ─────────────────────────────────────────────────────────────────

  Widget _artistSongs(List<LocalSong> songs) =>
      _songListView(songs, subtitleBuilder: (song) => song.artist);

  // ─── Album ─────────────────────────────────────────────────────────────────

  Widget _albumCards(List<LocalSong> songs) {
    final albums = <String, List<LocalSong>>{};
    for (final song in songs) {
      albums.putIfAbsent('${song.albumId}-${song.album}', () => []).add(song);
    }
    final entries = albums.values.toList()
      ..sort((a, b) => a.first.album.compareTo(b.first.album));

    final filtered = _filter.isEmpty
        ? entries
        : entries.where((albumSongs) {
            final album = albumSongs.first;
            return album.album.toLowerCase().contains(_filter) ||
                album.artist.toLowerCase().contains(_filter);
          }).toList();

    return ListView.builder(
      controller: _scroll,
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _listHeader(songs);
        final albumSongs = filtered[index - 1];
        final album = albumSongs.first;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          leading: SongArtwork(
            songId: album.id,
            size: 55,
            borderRadius: BorderRadius.circular(6),
          ),
          title: Text(
            album.album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${album.artist} • ${albumSongs.length} lagu',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.pushNamed(
            context,
            '/album',
            arguments: {'album': album, 'songs': albumSongs},
          ),
        );
      },
    );
  }

  // ─── Lagu ──────────────────────────────────────────────────────────────────

  Widget _songsList(List<LocalSong> songs) {
    final filtered = _filter.isEmpty
        ? songs
        : songs
            .where(
              (s) =>
                  s.title.toLowerCase().contains(_filter) ||
                  s.artist.toLowerCase().contains(_filter),
            )
            .toList();

    return ListView.builder(
      controller: _scroll,
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _listHeader(songs);
        final song = filtered[index - 1];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          leading: SongArtwork(songId: song.id, size: 55),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _playAt(songs, songs.indexOf(song)),
        );
      },
    );
  }

  // ─── Generic song list (Daftar Putar, Artis) ───────────────────────────────

  Widget _songListView(
    List<LocalSong> songs, {
    String Function(LocalSong song)? subtitleBuilder,
  }) {
    final filtered = _filter.isEmpty
        ? songs
        : songs
            .where(
              (s) =>
                  s.title.toLowerCase().contains(_filter) ||
                  s.artist.toLowerCase().contains(_filter),
            )
            .toList();

    return ListView.builder(
      controller: _scroll,
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _listHeader(songs);
        final song = filtered[index - 1];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          leading: SongArtwork(songId: song.id, size: 55),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            subtitleBuilder?.call(song) ?? song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _playAt(songs, songs.indexOf(song)),
        );
      },
    );
  }

  // ─── Playback helpers ──────────────────────────────────────────────────────

  Future<void> _playAt(List<LocalSong> songs, int index) async {
    await AudioService.playSongAt(playlist: songs, index: index);
    PlayerPanelController.instance.open();
  }

  Future<void> _playShuffled(List<LocalSong> songs) async {
    final shuffled = List<LocalSong>.from(songs)..shuffle();
    await _playAt(shuffled, 0);
  }
}
