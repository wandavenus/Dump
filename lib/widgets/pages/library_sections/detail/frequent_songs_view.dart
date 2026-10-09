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
    // Lebar tile dijaga mendekati ukuran potret: 2 kolom di potret, lebih
    // banyak kolom di window lebar.
    final columns = responsiveColumns(context, targetTileWidth: 190);
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
                  final rowStart = rowIndex * columns;

                  Widget tile(LocalSong song, int column) {
                    final songIndex = songs.indexOf(song);
                    final count = (counts[song.id.toString()] ?? 0) as num;
                    return _PlaylistBannerCard(
                      song: song,
                      playCount: count.toInt(),
                      height: _tileHeight(rowIndex, column),
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
                        for (var column = 0; column < columns; column++) ...[
                          if (column > 0) const SizedBox(width: 12),
                          if (rowStart + column < sorted.length)
                            Expanded(
                              child: tile(sorted[rowStart + column], column),
                            )
                          else
                            const Expanded(child: SizedBox()),
                        ],
                      ],
                    ),
                  );
                }, childCount: (sorted.length + columns - 1) ~/ columns),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Fixed pattern keeps the "random" tile sizes stable during rebuilds.
  /// [column] bergantian antara pola tinggi pertama dan kedua sehingga kolom
  /// genap selalu lebih tinggi dari kolom ganjil pada baris yang sama.
  double _tileHeight(int row, int column) {
    const patterns = <List<double>>[
      [196, 148],
      [148, 196],
      [176, 176],
      [212, 156],
      [156, 212],
    ];
    return patterns[row % patterns.length][column % 2];
  }
}
