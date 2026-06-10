import 'package:flutter/material.dart';

import '../widgets/pages/album_sections.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final routes = ModalRoute.of(context)?.settings.arguments as Map<String, int>?;
      if (routes != null && routes.containsKey('index')) {
        setState(() => currentIndex = routes['index']!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: AlbumPageContent(currentIndex: currentIndex));
  }
}
