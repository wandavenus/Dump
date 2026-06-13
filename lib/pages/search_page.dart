import 'package:flutter/material.dart';

import '../themes/theme_controller.dart';
import '../widgets/pages/search_sections.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  double _scrollOffset = 0;

  bool _handleScroll(ScrollNotification notification) {
    setState(() => _scrollOffset = notification.metrics.pixels);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.allGlass,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: ThemeController.glassTheme.value
              ? Colors.transparent
              : Colors.black,
          body: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: SearchSlivers(scrollOffset: _scrollOffset),
          ),
        );
      },
    );
  }
}
