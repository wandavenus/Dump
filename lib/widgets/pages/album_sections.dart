import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import 'detail_sections.dart';

class AlbumPageContent extends StatelessWidget {
  const AlbumPageContent({
    super.key,
    required this.album,
    required this.songs,
  });

  final LocalSong album;
  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const DetailTopBar(),
          AlbumHero(album: album),
          PlayShuffleButtons(songs: songs),
          SongListSection(songs: songs),
        ],
      ),
    );
  }
}
