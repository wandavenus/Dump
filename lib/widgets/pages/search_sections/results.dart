part of '../search_sections.dart';

class _SearchResultsSliver extends StatelessWidget {
  final List<LocalSong> results;
  final List<LocalSong> allSongs;
  final String query;

  const _SearchResultsSliver({
    required this.results,
    required this.allSongs,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, color: Color(0xFF48484A), size: 48),
              const SizedBox(height: 12),
              Text(
                'Tidak ada hasil untuk "$query"',
                style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, i) {
        final song = results[i];
        final indexInAll = allSongs.indexOf(song);
        return _SearchResultTile(
          song: song,
          playlist: allSongs,
          index: indexInAll >= 0 ? indexInAll : 0,
        );
      }, childCount: results.length),
    );
  }
}
