import 'package:flutter/material.dart';

import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/pages/artist_list_sections.dart';

class ArtistList extends StatefulWidget {
  const ArtistList({super.key});

  @override
  State<ArtistList> createState() => _ArtistListState();
}

class _ArtistListState extends State<ArtistList> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FadingTitleAppBar(
        title: 'Favourite Artist',
        scrollOffset: 100,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: const [],
      ),
      body: const ArtistListContent(),
    );
  }
}
