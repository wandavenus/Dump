part of 'detail_sections.dart';

// ─── Daftar lagu ──────────────────────────────────────────────────────────

class SongListSection extends StatelessWidget {
  const SongListSection({
    super.key,
    required this.songs,
    this.showHeader = false,
  });

  final List<LocalSong> songs;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final displayCount = songs.length < 4 ? songs.length : 4;
    return Column(
      children: [
        if (showHeader)
          Container(
            margin: const EdgeInsets.only(left: 10, top: 20),
            child: const Row(
              children: [
                Text(
                  'Top Songs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey),
              ],
            ),
          ),
        ListView.builder(
          padding: const EdgeInsets.only(top: 0, left: 10, right: 10),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: displayCount,
          itemBuilder: (context, index) =>
              SongListRow(song: songs[index], index: index, playlist: songs),
        ),
      ],
    );
  }
}
