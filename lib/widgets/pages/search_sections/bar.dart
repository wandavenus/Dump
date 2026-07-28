part of '../search_sections.dart';

const double _kSearchBarHeight = 68;

class _StickySearchBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickySearchBarDelegate({required this.child});

  @override
  double get minExtent => _kSearchBarHeight;

  @override
  double get maxExtent => _kSearchBarHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _StickySearchBarDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final bool loading;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.loading,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 10),
      child: GestureDetector(
        // Request focus ONLY when user explicitly taps the search bar
        onTap: focusNode.requestFocus,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: false, // Never autofocus on page load
                  style: TextStyle(color: c.primaryLabel, fontSize: 16),
                  cursorColor: const Color(0xFFF92D48),
                  decoration: InputDecoration(
                    hintText: context.l10n.searchHint,
                    hintStyle: TextStyle(color: c.secondaryLabel, fontSize: 15),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => focusNode.unfocus(),
                  onTapOutside: (_) => focusNode.unfocus(),
                ),
              ),
              if (loading)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.secondaryLabel,
                    ),
                  ),
                )
              else if (isSearching)
                GestureDetector(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.cancel,
                      color: c.secondaryLabel,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Search Results ───────────────────────────────────────────────────────────
