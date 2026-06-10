import 'package:flutter/material.dart';

import '../../utils/sample_music_data.dart';
import 'detail_sections.dart';

class AlbumPageContent extends StatelessWidget {
  const AlbumPageContent({super.key, required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final album = albumTopPicks[currentIndex];
    final songs = albumSongs[currentIndex];
    return SingleChildScrollView(
      child: Column(
        children: [
          const DetailTopBar(),
          AlbumHero(album: album),
          const PlayShuffleButtons(),
          SongListSection(songs: songs),
        ],
      ),
    );
  }
}
