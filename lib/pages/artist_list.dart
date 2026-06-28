import 'package:flutter/material.dart';

import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/pages/artist_list_sections.dart';

class ArtistList extends StatefulWidget {
  const ArtistList({super.key});

  @override
  State<ArtistList> createState() => _ArtistListState();
}

class _ArtistListState extends State<ArtistList> {
  final _scroll = ScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final o = _scroll.offset;
    if ((o - _offset).abs() > 0.5) setState(() => _offset = o);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: 'Favourite Artists',
        scrollOffset: _offset,
        actions: const [],
      ),
      body: ArtistListContent(scrollController: _scroll),
    );
  }
}
