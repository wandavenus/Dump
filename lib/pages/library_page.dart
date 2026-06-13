import 'package:flutter/material.dart';

import '../themes/theme_controller.dart';
import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/pages/library_sections.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.allGlass,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: ThemeController.glassTheme.value
              ? Colors.transparent
              : Colors.black,
          appBar: const LibraryGlassAppBar(),
          body: const LibraryContent(),
        );
      },
    );
  }
}
