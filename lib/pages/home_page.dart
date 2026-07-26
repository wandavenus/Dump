import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';
import 'package:musicplayer/services/scroll_to_top_service.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/pages/home_sections.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scrollOffsetNotifier = ValueNotifier<double>(0.0);
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    ScrollToTopService.signal(0).addListener(_onScrollToTop);
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

  // Clamp ke batas atas animasi AppBar (divider opacity selesai di 140px).
  // Di atas 140 tidak ada visual yang berubah, sehingga notifier tidak
  // diupdate sama sekali. Di dalam 0–140 setiap sub-pixel perubahan lolos.
  static const double _kAnimEnd = 140.0;

  bool _handleScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.metrics.axis == Axis.vertical) {
      final clamped = notification.metrics.pixels.clamp(0.0, _kAnimEnd);
      if (clamped != _scrollOffsetNotifier.value) {
        _scrollOffsetNotifier.value = clamped;
      }
    }
    return false;
  }

  @override
  void dispose() {
    ScrollToTopService.signal(0).removeListener(_onScrollToTop);
    _scroll.dispose();
    _scrollOffsetNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassTheme,
      builder: (context, isGlass, _) {
        final topPad = isGlass
            ? MediaQuery.paddingOf(context).top + kToolbarHeight
            : 0.0;

        return Scaffold(
          extendBodyBehindAppBar: isGlass,
          appBar: FadingTitleAppBar(
            title: context.l10n.homeTitle,
            scrollOffsetListenable: _scrollOffsetNotifier,
          ),
          body: PrimaryScrollController(
            controller: _scroll,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScroll,
              child: Padding(
                padding: EdgeInsets.only(top: topPad),
                child: const HomePageContent(),
              ),
            ),
          ),
        );
      },
    );
  }
}
