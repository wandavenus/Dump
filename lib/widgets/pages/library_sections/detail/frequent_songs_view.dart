part of '../../library_sections.dart';

/// CustomScrollView for the Daftar Putar (Frequently Played) library tab.
///
/// Loads play-count data via [countsFuture] and sorts [songs] by play count
/// descending. Uses [_PlaylistBannerCard] for each item.
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
                delegate: SliverChildBuilderDelegate((context, index) {
                  final song = sorted[index];
                  final songIndex = songs.indexOf(song);
                  final count = (counts[song.id.toString()] ?? 0) as num;
                  return _PlaylistBannerCard(
                    song: song,
                    playCount: count.toInt(),
                    onTap: () => onPlay(songs, songIndex),
                    onLongPress: () =>
                        onLongPress(context, song, songs, songIndex),
                  );
                }, childCount: sorted.length),
              ),
            ),
          ],
        );
      },
    );
  }
}
