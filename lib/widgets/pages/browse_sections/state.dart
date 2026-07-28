part of '../browse_sections.dart';

class _BrowsePageContentState extends State<BrowsePageContent> {
  List<LocalSong> _bannerSongs = [];
  List<LocalSong> _recommend = [];
  List<LocalSong> _newMusic = [];
  List<LocalSong> _daily = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  void _onRescan() {
    if (mounted) unawaited(_load());
  }

  @override
  void dispose() {
    MediaStoreService.rescanNotifier.removeListener(_onRescan);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final songs = await MediaStoreService.getSongs();
      if (songs.isEmpty) return;

      // Seed harian — nilai berubah setiap hari, stabil dalam satu hari
      final today = DateTime.now();
      final seed = today.year * 10000 + today.month * 100 + today.day;
      final dailyRng = Random(seed);

      // Pilih 3 lagu acak harian untuk banner (tanpa duplikat)
      final pool = List<LocalSong>.from(songs)..shuffle(dailyRng);
      final banners = pool.take(3).toList();

      // Acak sisa untuk seksi bawah (acak baru setiap buka halaman)
      final shuffled = List<LocalSong>.from(songs)..shuffle();
      final third = (shuffled.length / 3).ceil();

      if (mounted) {
        setState(() {
          _bannerSongs = banners;
          _recommend = shuffled.take(third).toList();
          _newMusic = shuffled.skip(third).take(third).toList();
          _daily = shuffled.skip(third * 2).toList();
        });
      }
    } on Exception catch (_) {
      // Biarkan daftar tetap kosong; seksi akan tersembunyi otomatis
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 64.5;
    return SingleChildScrollView(
      child: Column(
        children: [
          LargePageTitle(title: context.l10n.browseTitle),
          const HeaderDivider(),
          const SizedBox(height: 12),
          BrowseBannerCarousel(songs: _bannerSongs),
          const _SmartPlaylistCardWidget(index: 0),
          const _SmartPlaylistCardWidget(index: 1),
          const _SmartPlaylistCardWidget(index: 2),
          const _UserPlaylistsSection(),
          const SizedBox(height: 8),
          _BrowseSection(title: context.l10n.weRecommend, songs: _recommend),
          _BrowseSection(title: context.l10n.newMusicSection, songs: _newMusic),
          _BrowseSection(title: context.l10n.dailyTop100, songs: _daily),
          SizedBox(height: bottomClearance),
        ],
      ),
    );
  }
}

// ─── Banner carousel (local assets — tidak berubah) ───────────────────────────
