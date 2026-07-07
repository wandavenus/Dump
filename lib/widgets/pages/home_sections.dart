import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../utils/constants.dart';
import '../../services/artwork_repository.dart';
import '../../services/history_service.dart';
import '../../services/media_store_service.dart';
import '../../services/palette_extractor.dart';
import '../common/scrolling_page_chrome.dart';
import '../local_song_carousel.dart';
import '../song_artwork.dart';

part 'home/albums_section.dart';
part 'home/albums_section/section.dart';
part 'home/albums_section/state.dart';
part 'home/albums_section/card.dart';
part 'home/recently_played_section.dart';
part 'home/artists_section.dart';
part 'home/artists_section/section.dart';
part 'home/artists_section/state.dart';
part 'home/artists_section/card.dart';

class HomePageContent extends StatelessWidget {
  const HomePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    // Ruang kosong di bawah section terakhir agar tidak tertutup mini player.
    // Mini player: 64.5 px + system bottom inset (gesture nav bar).
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 64.5;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LargePageTitle(title: 'Beranda', align: false),
          const HeaderDivider(),
          const _LocalAlbumsSection(),
          const SectionTitle(title: 'Baru Dimainkan', routeName: '/musiclist'),
          const _RecentlyPlayedSection(),
          const SectionTitle(title: 'Artis Favorit', routeName: '/artistlist'),
          const _LocalArtistsSection(),
          SizedBox(height: bottomClearance),
        ],
      ),
    );
  }
}

class _AlbumGroup {
  final int albumId;
  final List<LocalSong> songs;

  _AlbumGroup({required this.albumId, required this.songs});

  String get name => songs.first.album;
  String get artist => songs.first.artist;
  int get coverSongId => songs.first.id;
}

class _ArtistGroup {
  final String name;
  final List<LocalSong> songs;

  _ArtistGroup({required this.name, required this.songs});

  int get coverSongId => songs.first.id;
}
