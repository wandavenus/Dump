import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/pages/artist_sections.dart';

class ArtistPage extends StatelessWidget {
  const ArtistPage({super.key});

  @override
  Widget build(BuildContext context) {
    final songs = ModalRoute.of(context)!.settings.arguments as List<LocalSong>;
    final artistName = songs.isNotEmpty ? songs.first.artist : 'Artist';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: artistName,
        scrollOffset: 100,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: const [],
      ),
      body: ArtistPageContent(songs: songs),
    );
  }
}
