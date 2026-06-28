import 'package:flutter/material.dart';
import 'package:musicplayer/services/scroll_to_top_service.dart';

import '../widgets/pages/search_sections.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  double _scrollOffset = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    ScrollToTopService.signal(4).addListener(_onScrollToTop);
  }

  void _onScrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  bool _handleScroll(ScrollNotification notification) {
    setState(() => _scrollOffset = notification.metrics.pixels);
    return false;
  }

  @override
  void dispose() {
    ScrollToTopService.signal(4).removeListener(_onScrollToTop);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PrimaryScrollController(
        controller: _scroll,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScroll,
          child: SearchSlivers(scrollOffset: _scrollOffset),
        ),
      ),
    );
  }
}
