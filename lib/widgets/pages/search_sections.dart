import 'package:flutter/material.dart';

import '../../utils/sample_music_data.dart';
import '../common_actions.dart';

class SearchSlivers extends StatelessWidget {
  const SearchSlivers({super.key, required this.scrollOffset});

  final double scrollOffset;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        _SearchAppBar(scrollOffset: scrollOffset),
        const SliverToBoxAdapter(child: _SearchTitle()),
        SliverPersistentHeader(pinned: true, delegate: SearchBarDelegate()),
        const SearchCategoryGrid(),
      ],
    );
  }
}

class _SearchAppBar extends StatelessWidget {
  const _SearchAppBar({required this.scrollOffset});

  final double scrollOffset;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.black,
      automaticallyImplyLeading: false,
      surfaceTintColor: Colors.transparent,
      title: Transform.translate(
        offset: Offset(0, (1 - (scrollOffset / 100).clamp(0.0, 1.0)) * 40),
        child: Opacity(
          opacity: ((((scrollOffset - 25) / 25).clamp(0.0, 1.0)) * 1.5)
              .clamp(0.0, 1.0),
          child: const Text('Cari',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Opacity(
          opacity: (scrollOffset / 140).clamp(0.0, 1.0),
          child: Container(height: 0.9, color: const Color(0xFF48484A)),
        ),
      ),
      actions: const [CommonActions()],
    );
  }
}

class _SearchTitle extends StatelessWidget {
  const _SearchTitle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        'Cari',
        style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }
}

class SearchBarDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 67;

  @override
  double get maxExtent => 67;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 18),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            SizedBox(width: 13),
            Text('Artis, Lagu, Lirik, dan lainnya',
                style: TextStyle(color: Colors.grey, fontSize: 17)),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}

class SearchCategoryGrid extends StatelessWidget {
  const SearchCategoryGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _SearchCategoryTile(category: searchCategories[index]),
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

class _SearchCategoryTile extends StatelessWidget {
  const _SearchCategoryTile({required this.category});

  final Map category;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(category['image'], fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.1)],
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Text(
              category['title'],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
