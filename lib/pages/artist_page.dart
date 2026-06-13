import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../widgets/pages/artist_sections.dart';

class ArtistPage extends StatelessWidget {
  const ArtistPage({super.key});

  @override
  Widget build(BuildContext context) {
    final songs = ModalRoute.of(context)!.settings.arguments as List<LocalSong>;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ArtistPageContent(
          songs: songs,
        ),
      ),
    );
  }
}