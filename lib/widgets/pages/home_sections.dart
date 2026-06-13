import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/history_service.dart';
import '../../services/media_store_service.dart';
import '../common/scrolling_page_chrome.dart';
import '../local_song_carousel.dart';
import '../song_artwork.dart';

part 'home/albums_section.dart';
part 'home/recently_played_section.dart';
part 'home/artists_section.dart';

// ─── Entry point ──────────────────────────────────────────────────────────────

class HomePageContent extends StatelessWidget {
  const HomePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          LargePageTitle(title: 'Beranda', align: false),
          HeaderDivider(),
          _LocalAlbumsSection(),
          SectionTitle(title: 'Recently Played', routeName: '/musiclist'),
          _RecentlyPlayedSection(),
          SectionTitle(title: 'Favourite Artists', routeName: '/artistlist'),
          _LocalArtistsSection(),
        ],
      ),
    );
  }
}

// ─── Data models (shared across part files via library scope) ─────────────────

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
