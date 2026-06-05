import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  
double _scrollOffset = 0;

List<Map<String, dynamic>> BrowseCat = [
    {
      "image": "assets/images/search/radio.webp",
      "title": "Apple Music Radio"
    },
    {
      "image": "assets/images/search/konser.webp",
      "title": "Concerts"
    },
    {
      "image": "assets/images/search/hits.webp",
      "title": "Hits"
    },
    {
      "image": "assets/images/search/kpop.webp",
      "title": "K-Pop"
    },
    {
      "image": "assets/images/search/pop.webp",
      "title": "Pop"
    },
    {
      "image": "assets/images/search/indie.webp",
      "title": "Indie"
    },
    {
      "image": "assets/images/search/klasik.webp",
      "title": "Classical"
    }, 
    {
      "image": "assets/images/search/metal.webp",
      "title": "Metal"
    },
    {
      "image": "assets/images/search/akustik.webp",
      "title": "Acoustic"
    },
    {
      "image": "assets/images/search/jazz.webp",
      "title": "Jazz"
    },
    {
      "image": "assets/images/search/blues.webp",
      "title": "Blues"
    },
    {
      "image": "assets/images/search/dj.webp",
      "title": "Dj Mixes"
    },
    {
      "image": "assets/images/search/hiphop.webp",
      "title": "Hip-Hop"
    },
    {
      "image": "assets/images/search/rnb.webp",
      "title": "RnB"
    },
    {
      "image": "assets/images/search/rock.webp",
      "title": "Rock"
    },
    {
      "image": "assets/images/search/electronic.webp",
      "title": "Electronic"
    },
    {
      "image": "assets/images/search/dance.webp",
      "title": "Dance"
    },
   
   ];

@override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
  onNotification: (notification) {
    setState(() {
      _scrollOffset = notification.metrics.pixels;
    });
    return false;
  },
  child: CustomScrollView(
        slivers: [
  SliverAppBar(
  pinned: true,
  backgroundColor: Colors.black,
  automaticallyImplyLeading: false,
  surfaceTintColor: Colors.transparent,
  title: Transform.translate(
  offset: Offset(
    0,
    (1 - (_scrollOffset / 100).clamp(0.0, 1.0)) * 6,
  ),
child: Opacity(
 opacity: ((_scrollOffset - 50) / 25)
    .clamp(0.0, 1.0),
 child: const Text(
    "Cari",
    style: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
   ),
  ),
 ),
),

bottom: PreferredSize(
  preferredSize: const Size.fromHeight(0.5),
  child: Opacity(
    opacity: (_scrollOffset / 140).clamp(0.0, 1.0),
    child: Container(
      height: 0.9,
      color: const Color(0xFF48484A),
    ),
  ),
),
actions: [
  IconButton(
    onPressed: () {},
    icon: const Icon(
      Icons.cast_outlined,
      color: Color(0xFFF92D48),
      size: 24,
    ),
  ),
  PopupMenuButton(
    icon: const Icon(
      Icons.more_vert,
      color: Color(0xFFF92D48),
      size: 24,
    ),
    itemBuilder: (context) => [],
  ),
],
),

SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(
      16,
      14,
      16,
      6,
    ),
    child: const Text(
      "Cari",
      style: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  ),
),
  
SliverPersistentHeader(
    pinned: true,
    delegate: _SearchBarDelegate(),
  ),

SliverPadding(
  padding: const EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 10,
  ),
  sliver: SliverGrid(
    delegate: SliverChildBuilderDelegate(
      (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
  BrowseCat[index]["image"],
  fit: BoxFit.cover,
),

              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.6),
                    ],
                  ),
                ),
              ),

              Positioned(
                left: 10,
                bottom: 10,
                child: Text(
                  BrowseCat[index]["title"],
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
      },
      childCount: BrowseCat.length,
    ),
    gridDelegate:
        const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2,
    ),
  ),
),

],
),
),
);
  }
}

class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 67;

  @override
  double get maxExtent => 67;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(
  left: 16,
  right: 16,
  top: 12,
  bottom: 18,
),
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            SizedBox(width: 13),
            
            
            Text(
              "Artis, Lagu, Lirik, dan lainnya",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),  
    );
  }

  @override
  bool shouldRebuild(
    covariant SliverPersistentHeaderDelegate oldDelegate,
  ) {
    return false;
  }
}