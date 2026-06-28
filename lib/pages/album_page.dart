import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/pages/album_sections.dart';

class AlbumPage extends StatelessWidget {
  const AlbumPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    final album = args['album'] as LocalSong;
    final songs = args['songs'] as List<LocalSong>;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: album.album,
        scrollOffset: 100,
        automaticallyImplyLeading: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: const [],
      ),
      body: AlbumPageContent(album: album, songs: songs),
    );
  }
}
