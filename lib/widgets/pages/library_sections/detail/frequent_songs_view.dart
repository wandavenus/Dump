part of '../../library_sections.dart';

/// CustomScrollView for the Daftar Putar (Frequently Played) library tab.
///
/// Loads play-count data via [countsFuture] and sorts [songs] by play count
/// descending. Displays the results as a Windows-style tile grid.
class _FrequentSongsView extends StatelessWidget {
  const _FrequentSongsView({
    required this.songs,
    required this.countsFuture,
    required this.scroll,
    required this.titleHeader,
    required this.bottomClearance,
    required this.onPlay,
    required this.onLongPress,
  });

  final List<LocalSong> songs;
  final Future<Map<String, dynamic>> countsFuture;
  final ScrollController scroll;

  /// Pre-built title + divider widget (no search bar for this tab).
  final Widget titleHeader;
  final double bottomClearance;

  final void Function(List<LocalSong>, int) onPlay;
  final void Function(BuildContext, LocalSong, List<LocalSong>, int)
  onLongPress;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: countsFuture,
      builder: (context, snapshot) {
        final counts = snapshot.data ?? const <String, dynamic>{};
        final sorted = List<LocalSong>.from(songs)
          ..sort(
            (a, b) => ((counts[b.id.toString()] ?? 0) as num).compareTo(
              (counts[a.id.toString()] ?? 0) as num,
            ),
          );

        return CustomScrollView(
          controller: scroll,
          slivers: [
            SliverToBoxAdapter(child: titleHeader),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomClearance),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, rowIndex) {
                  final firstIndex = rowIndex * 2;
                  final first = sorted[firstIndex];
                  final firstSongIndex = songs.indexOf(first);
                  final firstCount = (counts[first.id.toString()] ?? 0) as num;
                  final secondIndex = firstIndex + 1;

                  Widget tile(LocalSong song, num count, int songIndex) {
                    return _PlaylistBannerCard(
                      song: song,
                      playCount: count.toInt(),
                      height: _tileHeight(rowIndex, songIndex == secondIndex),
                      onTap: () => onPlay(songs, songIndex),
                      onLongPress: () =>
                          onLongPress(context, song, songs, songIndex),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: tile(first, firstCount, firstSongIndex),
                        ),
                        const SizedBox(width: 12),
                        if (secondIndex < sorted.length)
                          Expanded(
                            child: tile(
                              sorted[secondIndex],
                              (counts[sorted[secondIndex].id.toString()] ?? 0)
                                  as num,
                              songs.indexOf(sorted[secondIndex]),
                            ),
                          )
                        else
                          const Expanded(child: SizedBox()),
                      ],
                    ),
                  );
                }, childCount: (sorted.length + 1) ~/ 2),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Fixed pattern keeps the "random" tile sizes stable during rebuilds.
  double _tileHeight(int row, bool secondTile) {
    const patterns = <List<double>>[
      [196, 148],
      [148, 196],
      [176, 176],
      [212, 156],
      [156, 212],
    ];
    return patterns[row % patterns.length][secondTile ? 1 : 0];
  }
}
