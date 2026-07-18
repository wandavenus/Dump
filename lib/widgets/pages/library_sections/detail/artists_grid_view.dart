part of '../../library_sections.dart';

/// CustomScrollView for the Artists (Artis) library tab.
///
/// Displays artists in a 2-column grid. Uses the pre-sorted [artists]
/// cache from the parent state.
class _ArtistsGridView extends StatelessWidget {
  const _ArtistsGridView({
    required this.artists,
    required this.filter,
    required this.scroll,
    required this.titleHeader,
    required this.stickyControls,
    required this.bottomClearance,
  });

  /// Pre-sorted artist list from the parent state cache.
  final List<ArtistInfo> artists;
  final String           filter;
  final ScrollController scroll;
  final Widget           titleHeader;
  final Widget           stickyControls;
  final double           bottomClearance;

  @override
  Widget build(BuildContext context) {
    final filtered = filter.isEmpty
        ? artists
        : artists
            .where((a) => a.name.toLowerCase().contains(filter))
            .toList();

    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverToBoxAdapter(child: titleHeader),
        stickyControls,
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, bottomClearance),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:   2,
              crossAxisSpacing: 8,
              mainAxisSpacing:  16,
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => ArtistListRow(artist: filtered[index]),
              childCount: filtered.length,
            ),
          ),
        ),
      ],
    );
  }
}
