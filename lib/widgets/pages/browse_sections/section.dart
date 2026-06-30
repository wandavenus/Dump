part of '../browse_sections.dart';

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
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
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
