import 'package:flutter/material.dart';

import '../themes/theme_controller.dart';
import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/pages/home_sections.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
              title: 'Beranda', scrollOffset: _scrollOffset),
          body: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: const HomePageContent(),
          ),
        );
      },
    );
  }
}
