part of '../search_sections.dart';

class SearchCategoryGrid extends StatelessWidget {
  const SearchCategoryGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              _SearchCategoryTile(category: searchCategories[index]),
          childCount: searchCategories.length,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // 2 kolom di potret; kolom bertambah di window lebar supaya tile
          // tidak ikut meregang mengikuti lebar layar.
          crossAxisCount: responsiveColumns(
            context,
            targetTileWidth: 190,
            maxColumns: 4,
          ),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.0,
        ),
      ),
    );
  }
}
