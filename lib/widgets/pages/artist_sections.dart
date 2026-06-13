import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import 'detail_sections.dart';

class ArtistPageContent extends StatelessWidget {
  const ArtistPageContent({super.key, required this.songs});

  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          ArtistHero(songs: songs),
          PlayShuffleButtons(songs: songs),
          SongListSection(songs: songs, showHeader: true),
        ],
      ),
    );
  }
}
