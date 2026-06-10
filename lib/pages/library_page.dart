import 'package:flutter/material.dart';

import '../widgets/common_actions.dart';
import '../widgets/pages/library_sections.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
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
          child: Container(height: 0.9, color: Colors.transparent),
      body: const LibraryContent(),
    );
  }
}
    );
  }
}