import 'package:flutter/material.dart';
import 'package:musicplayer/services/scroll_to_top_service.dart';

import '../widgets/common_actions.dart';
import '../widgets/pages/library_sections.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    ScrollToTopService.signal(3).addListener(_onScrollToTop);
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

  @override
  void dispose() {
    ScrollToTopService.signal(3).removeListener(_onScrollToTop);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        title: const SizedBox.shrink(),
        centerTitle: false,
        actions: const [CommonActions()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(
            height: 0.9,
            color: Colors.transparent,
          ),
        ),
      ),
      body: PrimaryScrollController(
        controller: _scroll,
        child: const LibraryContent(),
      ),
    );
  }
}
