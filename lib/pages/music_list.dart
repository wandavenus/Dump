import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/widgets/common_actions.dart';

import '../models/local_song.dart';
import '../services/audio_service.dart';
import '../services/media_store_service.dart';
import '../widgets/song_artwork.dart';

class MusicList extends StatefulWidget {
  const MusicList({super.key});

  @override
  State<MusicList> createState() => _MusicListState();
}

class _MusicListState extends State<MusicList> {
  List<LocalSong> songs = [];
  bool refreshMiniPlayer = false;

  @override
  void initState() {
    super.initState();
    loadSongs();
  }

  Future<void> loadSongs() async {
    songs = await MediaStoreService.getSongs();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
      body: ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) {
          return InkWell(
            onTap: () async {
              Navigator.pushNamed(
                context,
                '/player',
                arguments: {
                  'index': index,
                  'song': songs[index],
                  'songs': songs,
                },
              );
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              leading: SizedBox(
                width: 55,
                height: 55,
                child: SongArtwork(
                  albumId: songs[index].albumId,
                  size: 55,
                ),
              ),
              title: Text(
                songs[index].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                songs[index].artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
    );
  }
}
