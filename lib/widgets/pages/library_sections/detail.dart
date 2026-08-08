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
  List<ArtistInfo> _cachedSortedArtists = [];
  List<List<LocalSong>> _cachedSortedAlbums = [];

  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _offsetNotifier = ValueNotifier<double>(0.0);
  String _filter = '';

  // ── Artwork prefetch state (viewport-aware) ───────────────────────────────
  // The Songs tab renders hundreds of rows; without prefetch every newly
  // scrolled-into-view song that has not been extracted yet triggers a native
  // MethodChannel extraction while the row is visible (placeholder flash).
  // We warm the disk path in batches ahead of the viewport instead.
  static const int _kArtworkPrefetchBatch = 15;
  static const double _kPrefetchTriggerExtent = 1200;
  List<LocalSong> _currentSongs = const [];
  int _prefetchedUpTo = 0;

  @override
  void initState() {
    super.initState();
    _songsFuture = MediaStoreService.getSongs();
    unawaited(_songsFuture.then(_updateSortedCaches));
    _countsFuture = HistoryService.getPlayCounts();
    _scroll.addListener(_onScroll);
    _searchController.addListener(_onSearch);
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  /// Recomputes sorted artists + albums caches after songs are loaded/rescanned.
  void _updateSortedCaches(List<LocalSong> songs) {
    // Remember the current song list for viewport-aware artwork prefetch.
    _currentSongs = songs;
    _prefetchedUpTo = 0;
    unawaited(_kickArtworkPrefetch());

    // Artists sorted A→Z.
    final artistMap = <String, List<LocalSong>>{};
    for (final song in songs) {
      artistMap.putIfAbsent(song.artist, () => []).add(song);
    }
    final artists =
        artistMap.entries
            .map((e) => ArtistInfo(name: e.key, songs: e.value))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    // Albums sorted A→Z by album title.
    final albumMap = <String, List<LocalSong>>{};
    for (final song in songs) {
      albumMap.putIfAbsent('${song.albumId}-${song.album}', () => []).add(song);
    }
    final albums = albumMap.values.toList()
      ..sort((a, b) => a.first.album.compareTo(b.first.album));

    if (mounted) {
      setState(() {
        _cachedSortedArtists = artists;
        _cachedSortedAlbums = albums;
      });
    }
  }

  void _onRescan() {
    if (!mounted) return;
    setState(() {
      _songsFuture = MediaStoreService.getSongs();
      _countsFuture = HistoryService.getPlayCounts();
    });
    unawaited(_songsFuture.then(_updateSortedCaches));
  }

  static const double _kAnimEnd = 140.0;

  void _onScroll() {
    final clamped = _scroll.offset.clamp(0.0, _kAnimEnd);
    if (clamped != _offsetNotifier.value) _offsetNotifier.value = clamped;

    // Near the bottom → warm the next batch of artwork paths before the user
    // reaches it. Cheap (disk probe / native extraction on background
    // executor); ArtworkRepository dedups in-flight batches and skips
    // already-cached IDs.
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels < _kPrefetchTriggerExtent) {
      unawaited(_kickArtworkPrefetch());
    }
  }

  /// Prefetches the next [_kArtworkPrefetchBatch] song artwork paths from
  /// [_currentSongs]. No-op once the whole list has been warmed or while a
  /// batch is already running (guarded here + inside
  /// [ArtworkRepository.prefetch]).
  Future<void> _kickArtworkPrefetch() async {
    final songs = _currentSongs;
    if (songs.isEmpty || _prefetchedUpTo >= songs.length) return;
    // A batch is already warming the disk — don't advance the cursor past it.
    // Each advance commits a range; a no-op prefetch here (in-flight guard)
    // would leave that range un-warmed. Retry on the next scroll tick.
    if (ArtworkRepository.instance.isPrefetching) return;
    final from = _prefetchedUpTo;
    final to = (from + _kArtworkPrefetchBatch).clamp(0, songs.length);
    _prefetchedUpTo = to;
    final ids = songs
        .sublist(from, to)
        .map((s) => s.id)
        .toList(growable: false);
    await ArtworkRepository.instance.prefetch(
      ids,
      limit: _kArtworkPrefetchBatch,
      concurrency: 2,
    );
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

  String _title(BuildContext context) => switch (widget.destination) {
    _LibraryDestination.playlist => context.l10n.playlists,
    _LibraryDestination.artists => context.l10n.artists,
    _LibraryDestination.albums => context.l10n.albums,
    _LibraryDestination.songs => context.l10n.songs,
  };

  String _hintText(BuildContext context) => switch (widget.destination) {
    _LibraryDestination.playlist => context.l10n.searchInPlaylists,
    _LibraryDestination.artists => context.l10n.searchArtists,
    _LibraryDestination.albums => context.l10n.searchAlbums,
    _LibraryDestination.songs => context.l10n.searchSongs,
  };

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = _title(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: title,
        scrollOffsetListenable: _offsetNotifier,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(
            CupertinoIcons.arrow_left,
            color: Color(0xFFF92D48),
            size: 28,
          ),
        ),
        actions: const [CommonActions()],
      ),
      body: FutureBuilder<List<LocalSong>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final songs = snapshot.data ?? const <LocalSong>[];
          if (songs.isEmpty) return _empty(context);

          final bottomClearance = MediaQuery.paddingOf(context).bottom + 64.5;

          return switch (widget.destination) {
            _LibraryDestination.playlist => _FrequentSongsView(
              songs: songs,
              countsFuture: _countsFuture!,
              scroll: _scroll,
              titleHeader: _titleHeader(context),
              bottomClearance: bottomClearance,
              onPlay: _playAt,
              onLongPress: (ctx, song, playlist, idx) => showSongContextMenu(
                ctx,
                song: song,
                playlist: playlist,
                index: idx,
              ),
            ),
            _LibraryDestination.artists => _ArtistsGridView(
              artists: _cachedSortedArtists,
              filter: _filter,
              scroll: _scroll,
              titleHeader: _titleHeader(context),
              stickyControls: _stickyControls(songs),
              bottomClearance: bottomClearance,
            ),
            _LibraryDestination.albums => _AlbumsListView(
              albums: _cachedSortedAlbums,
              filter: _filter,
              scroll: _scroll,
              titleHeader: _titleHeader(context),
              stickyControls: _stickyControls(songs),
              bottomClearance: bottomClearance,
            ),
            _LibraryDestination.songs => _SongsListView(
              songs: songs,
              filter: _filter,
              scroll: _scroll,
              titleHeader: _titleHeader(context),
              stickyControls: _stickyControls(songs),
              bottomClearance: bottomClearance,
              onPlay: _playAt,
              onLongPress: (ctx, song, playlist, idx) => showSongContextMenu(
                ctx,
                song: song,
                playlist: playlist,
                index: idx,
              ),
            ),
          };
        },
      ),
    );
  }

  // ── Shared chrome builders ─────────────────────────────────────────────────

  Widget _empty(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Text(
        context.l10n.noLocalSongs,
        style: TextStyle(color: c.primaryLabel.withValues(alpha: 0.70)),
      ),
    );
  }

  /// Judul + divider saja — scrolls with content, no pinning.
  Widget _titleHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LargePageTitle(title: _title(context)),
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
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: c.surface,
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
                style: TextStyle(color: c.primaryLabel, fontSize: 15),
                cursorColor: const Color(0xFFF92D48),
                decoration: InputDecoration(
                  hintText: _hintText(context),
                  hintStyle: TextStyle(color: c.secondaryLabel, fontSize: 15),
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
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.cancel, color: c.secondaryLabel, size: 18),
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
