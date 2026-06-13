import 'package:flutter/material.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/pages/radio_sections.dart';

class RadioPage extends StatefulWidget {
  const RadioPage({super.key});

  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
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
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassTheme,
      builder: (context, isGlass, _) {
        final topPad = isGlass
            ? MediaQuery.of(context).padding.top + kToolbarHeight
            : 0.0;

        return Scaffold(
          extendBodyBehindAppBar: isGlass,
          appBar: FadingTitleAppBar(
            title: 'Radio',
            scrollOffset: _scrollOffset,
          ),
          body: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: Padding(
              padding: EdgeInsets.only(top: topPad),
              child: const RadioPageContent(),
            ),
          ),
        );
      },
    );
  }
}
