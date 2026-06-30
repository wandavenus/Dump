import 'package:flutter/material.dart';
import 'package:musicplayer/services/scroll_to_top_service.dart';
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
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    ScrollToTopService.signal(2).addListener(_onScrollToTop);
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
    if (notification is ScrollUpdateNotification &&
        notification.metrics.axis == Axis.vertical) {
      setState(() => _scrollOffset = notification.metrics.pixels);
    }
    return false;
  }

  @override
  void dispose() {
    ScrollToTopService.signal(2).removeListener(_onScrollToTop);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassTheme,
      builder: (context, isGlass, _) {
        final topPad =
            isGlass ? MediaQuery.of(context).padding.top + kToolbarHeight : 0.0;

        return Scaffold(
          extendBodyBehindAppBar: isGlass,
          appBar: FadingTitleAppBar(
            title: 'Radio',
            scrollOffset: _scrollOffset,
          ),
          body: PrimaryScrollController(
            controller: _scroll,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScroll,
              child: Padding(
                padding: EdgeInsets.only(top: topPad),
                child: const RadioPageContent(),
              ),
            ),
          ),
        );
      },
    );
  }
}
