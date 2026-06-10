import 'package:flutter/material.dart';

import '../widgets/pages/artist_sections.dart';

class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key});

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
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
    return Scaffold(body: ArtistPageContent(currentIndex: currentIndex));
  }
}
