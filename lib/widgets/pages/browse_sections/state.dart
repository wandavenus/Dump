part of '../browse_sections.dart';

class _BrowsePageContentState extends State<BrowsePageContent> {
  List<LocalSong> _bannerSongs = [];
  List<LocalSong> _recommend = [];
  List<LocalSong> _newMusic = [];
  List<LocalSong> _daily = [];

  @override
  void initState() {
    super.initState();
    _load();
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
          _recommend   = shuffled.take(third).toList();
          _newMusic    = shuffled.skip(third).take(third).toList();
          _daily       = shuffled.skip(third * 2).toList();
        });
      }
    } catch (_) {
      // Biarkan daftar tetap kosong; seksi akan tersembunyi otomatis
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const LargePageTitle(title: 'Baru'),
          const HeaderDivider(),
          const SizedBox(height: 12),
          BrowseBannerCarousel(songs: _bannerSongs),
          _BrowseSection(title: 'We Recommend', songs: _recommend),
          _BrowseSection(title: 'New Music', songs: _newMusic),
          const BrowseCategoryStrip(),
          _BrowseSection(title: 'Daily Top 100', songs: _daily),
        ],
      ),
    );
  }
}

// ─── Banner carousel (local assets — tidak berubah) ───────────────────────────
