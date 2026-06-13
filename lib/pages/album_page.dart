import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../widgets/pages/album_sections.dart';

class AlbumPage extends StatelessWidget {
  const AlbumPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments
            as Map<String, dynamic>;

    final album = args['album'] as LocalSong;
    final songs = args['songs'] as List<LocalSong>;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: AlbumPageContent(
          album: album,
          songs: songs,
        ),
      ),
    );
  }
}