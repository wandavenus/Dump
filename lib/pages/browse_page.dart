import 'package:flutter/material.dart';

import '../themes/theme_controller.dart';
import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/pages/browse_sections.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  double _scrollOffset = 0;

  bool _handleScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.metrics.axis == Axis.vertical) {
      setState(() => _scrollOffset = notification.metrics.pixels);
    }
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
          appBar: FadingTitleAppBar(
              title: 'Baru', scrollOffset: _scrollOffset),
          body: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: const BrowsePageContent(),
          ),
        );
      },
    );
  }
}
