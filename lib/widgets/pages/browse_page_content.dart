part of 'browse_sections.dart';

class BrowsePageContent extends StatefulWidget {
  const BrowsePageContent({super.key});

  @override
  State<BrowsePageContent> createState() => _BrowsePageContentState();
}

class _BrowsePageContentState extends State<BrowsePageContent> {
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
      // Acak satu kali, lalu bagi menjadi 3 subset agar tiap seksi terasa berbeda
      final shuffled = List<LocalSong>.from(songs)..shuffle();
      final third = (shuffled.length / 3).ceil();
      if (mounted) {
        setState(() {
          _recommend = shuffled.take(third).toList();
          _newMusic = shuffled.skip(third).take(third).toList();
          _daily = shuffled.skip(third * 2).toList();
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
          const BrowseBannerCarousel(),
          _BrowseSection(title: 'We Recommend', songs: _recommend),
          _BrowseSection(title: 'New Music', songs: _newMusic),
          const BrowseCategoryStrip(),
          _BrowseSection(title: 'Daily Top 100', songs: _daily),
        ],
      ),
    );
  }
}
