part of 'browse_sections.dart';

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
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
