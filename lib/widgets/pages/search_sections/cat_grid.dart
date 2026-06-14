part of '../search_sections.dart';

class SearchCategoryGrid extends StatelessWidget {
  const SearchCategoryGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              _SearchCategoryTile(category: searchCategories[index]),
          childCount: searchCategories.length,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.3,
        ),
      ),
    );
  }
}
