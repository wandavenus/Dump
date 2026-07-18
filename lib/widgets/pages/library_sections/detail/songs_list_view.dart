part of '../../library_sections.dart';

/// CustomScrollView for the Songs (Lagu) library tab.
///
/// Receives pre-loaded [songs] and a [filter] string; derives the filtered
/// list internally so callers don't need to re-filter on every rebuild.
class _SongsListView extends StatelessWidget {
  const _SongsListView({
    required this.songs,
    required this.filter,
    required this.scroll,
    required this.titleHeader,
    required this.stickyControls,
    required this.bottomClearance,
    required this.onPlay,
    required this.onLongPress,
  });

  /// All songs (unfiltered) — used as the playback queue.
  final List<LocalSong> songs;
  final String          filter;
  final ScrollController scroll;

  /// Pre-built title + divider widget from the parent state.
  final Widget titleHeader;

  /// Pre-built [SliverPersistentHeader] with search + play/shuffle buttons.
  final Widget stickyControls;

  final double bottomClearance;

  /// Called with the full unfiltered queue and the tapped song's index.
  final void Function(List<LocalSong>, int) onPlay;

  /// Called with the song, the full queue, and the tapped song's index.
  final void Function(BuildContext, LocalSong, List<LocalSong>, int)
      onLongPress;

  @override
  Widget build(BuildContext context) {
    final filtered = filter.isEmpty
        ? songs
        : songs
            .where(
              (s) =>
                  s.title.toLowerCase().contains(filter) ||
                  s.artist.toLowerCase().contains(filter),
            )
            .toList();

    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverToBoxAdapter(child: titleHeader),
        stickyControls,
        SliverPadding(
          padding: EdgeInsets.only(bottom: bottomClearance),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song      = filtered[index];
                final songIndex = songs.indexOf(song);
                final tile = ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 2),
                  leading:  SongArtwork(songId: song.id, size: 55),
                  title:    Text(song.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF8E8E93), fontSize: 13)),
                  onTap:       () => onPlay(songs, songIndex),
                  onLongPress: () =>
                      onLongPress(context, song, songs, songIndex),
                );
                if (index == filtered.length - 1) return tile;
                return Column(
                  children: [
                    tile,
                    const Divider(
                      height:    1,
                      thickness: 0.5,
                      color:     Color(0xFF48484A),
                      indent:    87,
                      endIndent: 17,
                    ),
                  ],
                );
              },
              childCount: filtered.length,
            ),
          ),
        ),
      ],
    );
  }
}
