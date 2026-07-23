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
              Icon(Icons.search_off, color: AppColors.of(context).tertiaryLabel, size: 48),
              const SizedBox(height: 12),
              Text(
                'Tidak ada hasil untuk "$query"',
                style: TextStyle(color: AppColors.of(context).secondaryLabel, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i.isOdd) {
            return Divider(
              height: 1,
              thickness: 0.5,
              color: AppColors.of(context).separator,
              indent: 76,
              endIndent: 16,
            );
          }
          final idx = i ~/ 2;
          final song = results[idx];
          final indexInAll = allSongs.indexOf(song);
          return _SearchResultTile(
            song: song,
            playlist: allSongs,
            index: indexInAll >= 0 ? indexInAll : 0,
          );
        },
        childCount: results.length * 2 - 1,
      ),
    );
  }
}
