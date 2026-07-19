import 'package:flutter/material.dart';

import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/common_actions.dart';
import '../widgets/pages/artist_list_sections.dart';

class ArtistList extends StatefulWidget {
  const ArtistList({super.key});

  @override
  State<ArtistList> createState() => _ArtistListState();
}

class _ArtistListState extends State<ArtistList> {
  final _scroll = ScrollController();
  final _offsetNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final o = _scroll.offset;
    if ((o - _offsetNotifier.value).abs() > 0.5) _offsetNotifier.value = o;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _offsetNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: 'Artis Favorit',
        scrollOffsetListenable: _offsetNotifier,
        actions: const [CommonActions()],
      ),
      body: ArtistListContent(scrollController: _scroll),
    );
  }
}
