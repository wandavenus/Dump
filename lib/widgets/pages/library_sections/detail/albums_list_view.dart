part of '../../library_sections.dart';

/// CustomScrollView for the Albums library tab.
///
/// Uses the pre-sorted [albums] cache from the parent state so sorting is
/// not re-computed on every scroll-induced rebuild.
class _AlbumsListView extends StatelessWidget {
  const _AlbumsListView({
    required this.albums,
    required this.filter,
    required this.scroll,
    required this.titleHeader,
    required this.stickyControls,
    required this.bottomClearance,
  });

  /// Pre-sorted album groups (each group = all songs from one album).
  final List<List<LocalSong>> albums;
  final String                filter;
  final ScrollController      scroll;
  final Widget                titleHeader;
  final Widget                stickyControls;
  final double                bottomClearance;

  @override
  Widget build(BuildContext context) {
    final filtered = filter.isEmpty
        ? albums
        : albums.where((albumSongs) {
            final album = albumSongs.first;
            return album.album.toLowerCase().contains(filter) ||
                album.artist.toLowerCase().contains(filter);
          }).toList();

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
                final albumSongs = filtered[index];
                final album      = albumSongs.first;
                final tile = ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 2),
                  leading: SongArtwork(
                    songId:       album.id,
                    size:         55,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  title: Text(album.album,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${album.artist} • ${context.l10n.songsCount(albumSongs.length)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.of(context).secondaryLabel, fontSize: 13),
                  ),
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/album',
                    arguments: {'album': album, 'songs': albumSongs},
                  ),
                );
                if (index == filtered.length - 1) return tile;
                return Column(
                  children: [
                    tile,
                    Divider(
                      height:    1,
                      thickness: 0.5,
                      color:     AppColors.of(context).separator,
                      indent:    87,
                      endIndent: 16,
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
