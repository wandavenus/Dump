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
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  void _onRescan() {
    if (!mounted) return;
    setState(() {
      _songsFuture = MediaStoreService.getSongs();
    });
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
    MediaStoreService.rescanNotifier.removeListener(_onRescan);
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
        actions: const [CommonActions()],
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

  // ─── Control buttons (shared Putar/Acak — same as Album/Artist Detail) ─────

  Widget _controlButtons(List<LocalSong> songs) {
    return PlayShuffleButtons(songs: songs);
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

  /// Judul + divider saja — scroll normal, tidak menumpuk.
  Widget _titleHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LargePageTitle(title: _title),
        const HeaderDivider(),
      ],
    );
  }

  /// Search bar + tombol Putar/Acak — dibungkus agar bisa menumpuk (pinned)
  /// di bawah header, sama seperti perilaku search bar di halaman Cari.
  Widget _stickyControls(List<LocalSong> songs) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyLibraryControlsDelegate(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _searchBar(),
            _controlButtons(songs),
          ],
        ),
      ),
    );
  }

  // ─── Daftar Putar ──────────────────────────────────────────────────────────

  Widget _frequentSongs(List<LocalSong> songs) {
    return FutureBuilder<Map<String, dynamic>>(
      future: HistoryService.getPlayCounts(),
      builder: (context, snapshot) {
        final counts = snapshot.data ?? const <String, dynamic>{};
        final sorted = List<LocalSong>.from(songs)
          ..sort(
            (a, b) => ((counts[b.id.toString()] ?? 0) as num).compareTo(
              (counts[a.id.toString()] ?? 0) as num,
            ),
          );

        final bottomClearance = MediaQuery.paddingOf(context).bottom + 64.5;

        return CustomScrollView(
          controller: _scroll,
          slivers: [
            // Header — judul + divider saja, tanpa search & kontrol
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LargePageTitle(title: _title),
                  const HeaderDivider(),
                ],
              ),
            ),

            // Banner list
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomClearance),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = sorted[index];
                    final songIndex = songs.indexOf(song);
                    final count =
                        (counts[song.id.toString()] ?? 0) as num;
                    return _PlaylistBannerCard(
                      song: song,
                      playCount: count.toInt(),
                      onTap: () => _playAt(songs, songIndex),
                      onLongPress: () => showSongContextMenu(
                        context,
                        song: song,
                        playlist: songs,
                        index: songIndex,
                      ),
                    );
                  },
                  childCount: sorted.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Artis ─────────────────────────────────────────────────────────────────

  Widget _artistSongs(List<LocalSong> songs) {
    // Kelompokkan lagu per artis
    final artistMap = <String, List<LocalSong>>{};
    for (final song in songs) {
      artistMap.putIfAbsent(song.artist, () => []).add(song);
    }
    final artists = artistMap.entries
        .map((e) => ArtistInfo(name: e.key, songs: e.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    // Filter berdasarkan pencarian
    final filtered = _filter.isEmpty
        ? artists
        : artists
            .where((a) => a.name.toLowerCase().contains(_filter))
            .toList();

    final bottomClearance = MediaQuery.of(context).padding.bottom + 64.5;

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        // Header — judul + divider, scroll normal
        SliverToBoxAdapter(child: _titleHeader()),
        // Search bar + tombol Putar/Acak — menumpuk (pinned) di bawah header
        _stickyControls(songs),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, bottomClearance),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 16,
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => ArtistListRow(artist: filtered[index]),
              childCount: filtered.length,
            ),
          ),
        ),
      ],
    );
  }

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

    final bottomClearance = MediaQuery.of(context).padding.bottom + 64.5;
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        // Header — judul + divider, scroll normal
        SliverToBoxAdapter(child: _titleHeader()),
        // Search bar + tombol Putar/Acak — menumpuk (pinned) di bawah header
        _stickyControls(songs),
        SliverPadding(
          padding: EdgeInsets.only(bottom: bottomClearance),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final albumSongs = filtered[index];
                final album = albumSongs.first;
                final tile = ListTile(
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
                    style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 13,
                      ), 
                  ),
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/album',
                    arguments: {'album': album, 'songs': albumSongs},
                  ),
                );
                if (index == filtered.length - 1) return tile;
                return Column(
                  children: [
                    tile,
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0xFF48484A),
                      indent: 87,
                      endIndent: 16,
                    ),
                  ],
                );
              },
              childCount: filtered.length,
            ),
          ),
        ),
      ],
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

    final bottomClearance = MediaQuery.of(context).padding.bottom + 64.5;
    return ListView.separated(
      controller: _scroll,
      padding: EdgeInsets.only(bottom: bottomClearance),
      itemCount: filtered.length + 1,
      separatorBuilder: (context, index) => index == 0
          ? const SizedBox.shrink()
          : const Divider(
              height: 1,
              thickness: 0.5,
              color: Color(0xFF48484A),
              indent: 87,
              endIndent: 17,
            ),
      itemBuilder: (context, index) {
        if (index == 0) return _listHeader(songs);
        final song = filtered[index - 1];
        final songIndex = songs.indexOf(song);
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
            style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 13,
              ), 
          ),
          onTap: () => _playAt(songs, songIndex),
          onLongPress: () => showSongContextMenu(
            context,
            song: song,
            playlist: songs,
            index: songIndex,
          ),
        );
      },
    );
  }


  // ─── Playback helpers ──────────────────────────────────────────────────────

  Future<void> _playAt(List<LocalSong> songs, int index) async {
    await AudioService.playSongAt(playlist: songs, index: index);
  }
}

// ─── Banner card untuk Daftar Putar ────────────────────────────────────────

class _PlaylistBannerCard extends StatelessWidget {
  const _PlaylistBannerCard({
    required this.song,
    required this.playCount,
    required this.onTap,
    required this.onLongPress,
  });

  final LocalSong song;
  final int playCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork banner — full width, persegi panjang landscape
            AspectRatio(
              aspectRatio: 16 / 9,
              child: SongArtwork(
                songId: song.id,
                size: 600,
                borderRadius: BorderRadius.circular(10),
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),

            // Judul lagu
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),

            // Artis • jumlah putar
            Text(
              playCount > 0
                  ? '${song.artist} • Diputar ${playCount}x'
                  : song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sticky header untuk search bar + tombol Putar/Acak ────────────────────
// Sama seperti perilaku menumpuk di halaman Cari (_StickySearchBarDelegate).

const double _kLibraryControlsHeight = 120;

class _StickyLibraryControlsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyLibraryControlsDelegate({required this.child});

  @override
  double get minExtent => _kLibraryControlsHeight;

  @override
  double get maxExtent => _kLibraryControlsHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(color: Colors.black, child: child);
  }

  @override
  bool shouldRebuild(covariant _StickyLibraryControlsDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
