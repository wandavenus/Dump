part of '../library_sections.dart';

// Sub-widgets extracted to library_sections/detail/:
//   detail/playlist_banner_card.dart   — _PlaylistBannerCard
//   detail/sticky_controls_delegate.dart — _StickyLibraryControlsDelegate,
//                                          _kLibraryControlsHeight
//   detail/songs_list_view.dart        — _SongsListView
//   detail/albums_list_view.dart       — _AlbumsListView
//   detail/artists_grid_view.dart      — _ArtistsGridView
//   detail/frequent_songs_view.dart    — _FrequentSongsView

class _LibraryDetailPage extends StatefulWidget {
  const _LibraryDetailPage({required this.destination});

  final _LibraryDestination destination;

  @override
  State<_LibraryDetailPage> createState() => _LibraryDetailPageState();
}

class _LibraryDetailPageState extends State<_LibraryDetailPage> {
  late Future<List<LocalSong>> _songsFuture;
  // Cached once per songs-load; prevents FutureBuilder from re-subscribing on
  // every scroll-induced rebuild (which would cause a waiting→data flicker).
  Future<Map<String, dynamic>>? _countsFuture;
  // Pre-sorted caches; recomputed only when songs change, not on every scroll.
  List<ArtistInfo>       _cachedSortedArtists = [];
  List<List<LocalSong>>  _cachedSortedAlbums  = [];

  final _scroll            = ScrollController();
  final _searchController  = TextEditingController();
  final _searchFocus       = FocusNode();
  final _offsetNotifier    = ValueNotifier<double>(0.0);
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _songsFuture = MediaStoreService.getSongs();
    _songsFuture.then(_updateSortedCaches);
    _countsFuture = HistoryService.getPlayCounts();
    _scroll.addListener(_onScroll);
    _searchController.addListener(_onSearch);
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  /// Recomputes sorted artists + albums caches after songs are loaded/rescanned.
  void _updateSortedCaches(List<LocalSong> songs) {
    // Artists sorted A→Z.
    final artistMap = <String, List<LocalSong>>{};
    for (final song in songs) {
      artistMap.putIfAbsent(song.artist, () => []).add(song);
    }
    final artists = artistMap.entries
        .map((e) => ArtistInfo(name: e.key, songs: e.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    // Albums sorted A→Z by album title.
    final albumMap = <String, List<LocalSong>>{};
    for (final song in songs) {
      albumMap.putIfAbsent(
          '${song.albumId}-${song.album}', () => []).add(song);
    }
    final albums = albumMap.values.toList()
      ..sort((a, b) => a.first.album.compareTo(b.first.album));

    if (mounted) {
      setState(() {
        _cachedSortedArtists = artists;
        _cachedSortedAlbums  = albums;
      });
    }
  }

  void _onRescan() {
    if (!mounted) return;
    setState(() {
      _songsFuture  = MediaStoreService.getSongs();
      _countsFuture = HistoryService.getPlayCounts();
    });
    _songsFuture.then(_updateSortedCaches);
  }

  static const double _kAnimEnd = 140.0;

  void _onScroll() {
    final clamped = _scroll.offset.clamp(0.0, _kAnimEnd);
    if (clamped != _offsetNotifier.value) _offsetNotifier.value = clamped;
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
    _offsetNotifier.dispose();
    super.dispose();
  }

  // ── Labels ─────────────────────────────────────────────────────────────────

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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title:                  _title,
        scrollOffsetListenable: _offsetNotifier,
        actions:                const [CommonActions()],
      ),
      body: FutureBuilder<List<LocalSong>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final songs = snapshot.data ?? const <LocalSong>[];
          if (songs.isEmpty) return _empty();

          final bottomClearance =
              MediaQuery.paddingOf(context).bottom + 64.5;

          return switch (widget.destination) {
            _LibraryDestination.playlist => _FrequentSongsView(
              songs:          songs,
              countsFuture:   _countsFuture!,
              scroll:         _scroll,
              titleHeader:    _titleHeader(),
              bottomClearance: bottomClearance,
              onPlay:         _playAt,
              onLongPress:    (ctx, song, playlist, idx) =>
                  showSongContextMenu(ctx,
                      song: song, playlist: playlist, index: idx),
            ),
            _LibraryDestination.artists => _ArtistsGridView(
              artists:         _cachedSortedArtists,
              filter:          _filter,
              scroll:          _scroll,
              titleHeader:     _titleHeader(),
              stickyControls:  _stickyControls(songs),
              bottomClearance: bottomClearance,
            ),
            _LibraryDestination.albums => _AlbumsListView(
              albums:          _cachedSortedAlbums,
              filter:          _filter,
              scroll:          _scroll,
              titleHeader:     _titleHeader(),
              stickyControls:  _stickyControls(songs),
              bottomClearance: bottomClearance,
            ),
            _LibraryDestination.songs => _SongsListView(
              songs:           songs,
              filter:          _filter,
              scroll:          _scroll,
              titleHeader:     _titleHeader(),
              stickyControls:  _stickyControls(songs),
              bottomClearance: bottomClearance,
              onPlay:          _playAt,
              onLongPress:     (ctx, song, playlist, idx) =>
                  showSongContextMenu(ctx,
                      song: song, playlist: playlist, index: idx),
            ),
          };
        },
      ),
    );
  }

  // ── Shared chrome builders ─────────────────────────────────────────────────

  Widget _empty() => const Center(
        child: Text(
          'Tidak ada lagu lokal ditemukan',
          style: TextStyle(color: Colors.white70),
        ),
      );

  /// Judul + divider saja — scrolls with content, no pinning.
  Widget _titleHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize:       MainAxisSize.min,
      children: [
        LargePageTitle(title: _title),
        const HeaderDivider(),
      ],
    );
  }

  /// Search bar + play/shuffle buttons — pinned below the scrolling title.
  Widget _stickyControls(List<LocalSong> songs) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyLibraryControlsDelegate(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _searchBar(),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PlayShuffleButtons(songs: songs, topPadding: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Search bar ────────────────────────────────────────────────────────────

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color:        const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller:  _searchController,
                focusNode:   _searchFocus,
                autofocus:   false,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: const Color(0xFFF92D48),
                decoration: InputDecoration(
                  hintText:  _hintText,
                  hintStyle: const TextStyle(
                      color: Color(0xFF8E8E93), fontSize: 15),
                  border:         InputBorder.none,
                  isDense:        true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted:   (_) => _searchFocus.unfocus(),
                onTapOutside:  (_) => _searchFocus.unfocus(),
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
                  child: Icon(Icons.cancel,
                      color: Color(0xFF8E8E93), size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  Future<void> _playAt(List<LocalSong> songs, int index) async {
    await AudioService.playSongAt(playlist: songs, index: index);
  }
}
