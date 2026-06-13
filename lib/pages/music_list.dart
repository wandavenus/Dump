import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../services/audio_service.dart';
import '../services/media_store_service.dart';
import '../themes/theme_controller.dart';
import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/player/player_hero_tags.dart';
import '../widgets/player/player_panel_controller.dart';
import '../widgets/song_artwork.dart';

class MusicList extends StatefulWidget {
  const MusicList({super.key});

  @override
  State<MusicList> createState() => _MusicListState();
}

class _MusicListState extends State<MusicList> {
  late Future<List<LocalSong>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = MediaStoreService.getSongs();
  }

  Future<void> _refreshSongs() async {
    setState(() => _songsFuture = MediaStoreService.getSongs());
    await _songsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.allGlass,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: ThemeController.glassTheme.value
              ? Colors.transparent
              : Colors.black,
          appBar: const DownloadsGlassAppBar(),
          body: FutureBuilder<List<LocalSong>>(
            future: _songsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final songs = snapshot.data ?? const <LocalSong>[];
              if (songs.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refreshSongs,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 180),
                      Icon(Icons.music_note, size: 56, color: Colors.white38),
                      SizedBox(height: 12),
                      Center(
                        child: Text(
                          'Tidak ada lagu lokal ditemukan',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _refreshSongs,
                child: ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      onTap: () async {
                        await AudioService.playSongAt(
                            playlist: songs, index: index);
                        PlayerPanelController.instance.open();
                      },
                      leading: Hero(
                        tag: PlayerHeroTags.artwork(song),
                        child: SongArtwork(songId: song.id, size: 55),
                      ),
                      title: Hero(
                        tag: PlayerHeroTags.title(song),
                        child: Material(
                          type: MaterialType.transparency,
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      subtitle: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
