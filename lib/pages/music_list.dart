import 'package:flutter/material.dart';
import 'package:musicplayer/themes/apple_music_blur.dart';
import 'package:musicplayer/widgets/common_actions.dart';

import '../models/local_song.dart';
import '../services/media_store_service.dart';
import '../widgets/song_artwork.dart';
import 'music_player.dart';

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
    setState(() {
      _songsFuture = MediaStoreService.getSongs();
    });
    await _songsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const AppleMusicBarBackground(),
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text(
          'Unduhan',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: const [
          CommonActions(),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 0.3,
            color: Colors.white24,
          ),
        ),
      ),
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
                    horizontal: 16,
                    vertical: 2,
                  ),
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      '/player',
                      arguments: {
                        'index': index,
                        'song': song,
                        'songs': songs,
                      },
                    );
                  },
                  leading: Hero(
                    tag: PlayerHeroTags.artwork(song),
                    child: SongArtwork(
                      songId: song.id,
                      size: 55,
                    ),
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
  }
}
