import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/media_store_service.dart';
import '../../utils/data/browse_banners.dart';
import '../common/scrolling_page_chrome.dart';
import '../local_song_carousel.dart';

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

// ─── Banner carousel (local assets — tidak berubah) ───────────────────────────

class BrowseBannerCarousel extends StatelessWidget {
  const BrowseBannerCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 350,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: browseBanners.length,
        itemBuilder: (context, index) {
          final banner = browseBanners[index];
          return Container(
            width: 370,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    banner['t1'],
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    banner['t2'],
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.normal,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    banner['t3'],
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.normal,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 5),
                  ClipPath(
                    clipper: ShapeBorderClipper(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Image.asset(
                      banner['img'],
                      height: 720 / 3,
                      width: 1080 / 3,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Browse section dengan local songs ────────────────────────────────────────

class _BrowseSection extends StatelessWidget {
  const _BrowseSection({required this.title, required this.songs});

  final String title;
  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 15, top: 10),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color.fromARGB(255, 186, 186, 186),
              ),
            ],
          ),
        ),
        LocalSongCarousel(songs: songs),
      ],
    );
  }
}

// ─── Category strip (statis — tidak berubah) ──────────────────────────────────

class BrowseCategoryStrip extends StatelessWidget {
  const BrowseCategoryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 145,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: const [
          _GradientCategory(title: 'Music', subtitle: 'Start Singing'),
          _GradientCategory(title: 'Hits', subtitle: 'Listen Now'),
          _GradientCategory(title: 'Pop', subtitle: 'Explore More'),
        ],
      ),
    );
  }
}

class _GradientCategory extends StatelessWidget {
  const _GradientCategory({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              colors: [
                Color.fromARGB(255, 251, 47, 88),
                Color.fromARGB(255, 255, 174, 174),
              ],
              stops: [0.4, 1],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          margin: const EdgeInsets.only(top: 10, left: 10),
          height: 100,
          width: 200,
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.white, offset: Offset(0, 0), blurRadius: 15),
                ],
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 5, left: 10),
          child: Text(subtitle, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
