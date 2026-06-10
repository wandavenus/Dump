import 'package:flutter/material.dart';

import '../../utils/sample_music_data.dart';
import 'detail_sections.dart';

class ArtistPageContent extends StatelessWidget {
  const ArtistPageContent({super.key, required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final songs = artistSongs[currentIndex];
    return SingleChildScrollView(
      child: Column(
        children: [
          ArtistHero(songs: songs),
          const PlayShuffleButtons(),
          SongListSection(songs: songs, showHeader: true),
        ],
      ),
    );
  }
}
