part of '../../library_sections.dart';

/// Height used for the sticky search + play/shuffle controls header.
const double _kLibraryControlsHeight = 140;

/// [SliverPersistentHeaderDelegate] that pins the search bar and
/// play/shuffle buttons below the scrolling title header.
///
/// Mirrors the behaviour of the search bar on the Search page.
class _StickyLibraryControlsDelegate extends SliverPersistentHeaderDelegate {
  const _StickyLibraryControlsDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => _kLibraryControlsHeight;

  @override
  double get maxExtent => _kLibraryControlsHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: child);
  }

  @override
  bool shouldRebuild(
      covariant _StickyLibraryControlsDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
