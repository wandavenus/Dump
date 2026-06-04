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
      "image": "https://pyxis.nymag.com/v1/imgs/3a3/b1f/2141226b8ab1ae07afe4b541ee0d2b0825-11-yic-pop-essay.rsocial.w1200.jpg",
      "title": "Pop"
    },
    {
      "image": "https://images.saymedia-content.com/.image/t_share/MTgzNjE1MzI5MDYxMTE5NzA1/best-modern-rock-bands.jpg",
      "title": "Rock"
    },
    {
      "image": "https://neonmusic.online/wp-content/uploads/2023/04/music-3264716_1280.jpg",
      "title": "Jazz"
    },
    {
      "image": "https://uproxx.com/wp-content/uploads/2018/02/hip-hop-grid-uproxx.jpg",
      "title": "Hip Hop"
    },
    {
      "image": "https://www.wideopencountry.com/wp-content/uploads/sites/4/2017/04/eric.jpg?fit=798%2C526",
      "title": "Country"
    },
    {
      "image": "https://c02.purpledshub.com/uploads/sites/43/2021/06/What-is-blues-music--1def93e.jpg",
      "title": "Blues"
    },
    {
      "image": "https://images.unsplash.com/photo-1624703307604-744ec383cbf4?q=80&w=2070&auto=format&fit=crop&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
      "title": "Electronic"
    },
    {
      "image": "https://i.guim.co.uk/img/media/b34325085c62cb49ec9b528b5586696100cecfa9/0_0_4000_2667/master/4000.jpg?width=700&quality=85&auto=format&fit=max&s=c7d68dd52e6cefddb7df03822e2d7759",
      "title": "Classical"
    },
    {
      "image": "https://cdn.britannica.com/73/101873-050-D341E939/Bob-Marley-1978.jpg",
      "title": "Reggae"
    },
    {
      "image": "https://ichef.bbci.co.uk/images/ic/480xn/p06y1mg4.jpg",
      "title": "Folk"
    },
    {
      "image": "https://pyxis.nymag.com/v1/imgs/3a3/b1f/2141226b8ab1ae07afe4b541ee0d2b0825-11-yic-pop-essay.rsocial.w1200.jpg",
      "title": "Pop"
    },
    {
      "image": "https://images.saymedia-content.com/.image/t_share/MTgzNjE1MzI5MDYxMTE5NzA1/best-modern-rock-bands.jpg",
      "title": "Rock"
    },
    {
      "image": "https://neonmusic.online/wp-content/uploads/2023/04/music-3264716_1280.jpg",
      "title": "Jazz"
    },
    {
      "image": "https://uproxx.com/wp-content/uploads/2018/02/hip-hop-grid-uproxx.jpg",
      "title": "Hip Hop"
    },
    {
      "image": "https://www.wideopencountry.com/wp-content/uploads/sites/4/2017/04/eric.jpg?fit=798%2C526",
      "title": "Country"
    },
    {
      "image": "https://c02.purpledshub.com/uploads/sites/43/2021/06/What-is-blues-music--1def93e.jpg",
      "title": "Blues"
    },
    {
      "image": "https://images.unsplash.com/photo-1624703307604-744ec383cbf4?q=80&w=2070&auto=format&fit=crop&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
      "title": "Electronic"
    },
    {
      "image": "https://i.guim.co.uk/img/media/b34325085c62cb49ec9b528b5586696100cecfa9/0_0_4000_2667/master/4000.jpg?width=700&quality=85&auto=format&fit=max&s=c7d68dd52e6cefddb7df03822e2d7759",
      "title": "Classical"
    },
    {
      "image": "https://cdn.britannica.com/73/101873-050-D341E939/Bob-Marley-1978.jpg",
      "title": "Reggae"
    },
    {
      "image": "https://ichef.bbci.co.uk/images/ic/480xn/p06y1mg4.jpg",
      "title": "Folk"
    },
    {
      "image": "https://pyxis.nymag.com/v1/imgs/3a3/b1f/2141226b8ab1ae07afe4b541ee0d2b0825-11-yic-pop-essay.rsocial.w1200.jpg",
      "title": "Pop"
    },
    {
      "image": "https://images.saymedia-content.com/.image/t_share/MTgzNjE1MzI5MDYxMTE5NzA1/best-modern-rock-bands.jpg",
      "title": "Rock"
    },
    {
      "image": "https://neonmusic.online/wp-content/uploads/2023/04/music-3264716_1280.jpg",
      "title": "Jazz"
    },
    {
      "image": "https://uproxx.com/wp-content/uploads/2018/02/hip-hop-grid-uproxx.jpg",
      "title": "Hip Hop"
    },
    {
      "image": "https://www.wideopencountry.com/wp-content/uploads/sites/4/2017/04/eric.jpg?fit=798%2C526",
      "title": "Country"
    },
    {
      "image": "https://c02.purpledshub.com/uploads/sites/43/2021/06/What-is-blues-music--1def93e.jpg",
      "title": "Blues"
    },
    {
      "image": "https://images.unsplash.com/photo-1624703307604-744ec383cbf4?q=80&w=2070&auto=format&fit=crop&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
      "title": "Electronic"
    },
    {
      "image": "https://i.guim.co.uk/img/media/b34325085c62cb49ec9b528b5586696100cecfa9/0_0_4000_2667/master/4000.jpg?width=700&quality=85&auto=format&fit=max&s=c7d68dd52e6cefddb7df03822e2d7759",
      "title": "Classical"
    },
    {
      "image": "https://cdn.britannica.com/73/101873-050-D341E939/Bob-Marley-1978.jpg",
      "title": "Reggae"
    },
    {
      "image": "https://ichef.bbci.co.uk/images/ic/480xn/p06y1mg4.jpg",
      "title": "Folk"
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
  centerTitle: true,
  title: AnimatedOpacity(
    duration: const Duration(milliseconds: 180),
    opacity: _scrollOffset > 55 ? 0 : 1,
    child: const Text(
      "Cari",
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
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
  child: AnimatedOpacity(
    duration: const Duration(milliseconds: 180),
    opacity: _scrollOffset > 55 ? 0 : 1,
    child: const Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        6,
      ),
      child: Text(
        "Cari",
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  ),
),

  SliverPersistentHeader(
    pinned: true,
    delegate: _SearchBarDelegate(),
  ),

SliverList(
  delegate: SliverChildBuilderDelegate(
    (context, index) => ListTile(
      title: Text(
        "Genre $index",
        style: const TextStyle(color: Colors.white),
      ),
    ),
    childCount: 30,
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
  double get minExtent => 60;

  @override
  double get maxExtent => 60;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            SizedBox(width: 12),
            
            SizedBox(width: 8),
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