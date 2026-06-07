import 'package:musicplayer/widgets/common_actions.dart';
import '../services/audio_service.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';


class MusicList extends StatefulWidget {
  const MusicList({super.key});

  @override
  State<MusicList> createState() => _MusicListState();
}

class _MusicListState extends State<MusicList> {
final OnAudioQuery audioQuery = OnAudioQuery();
List<SongModel> songs = [];
bool refreshMiniPlayer = false;
  @override
void initState() {
  super.initState();
  loadSongs();
}

Future<void> loadSongs() async {
  bool permission = await audioQuery.permissionsRequest();

  if (permission) {
    songs = await audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

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
    "Unduhan",
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
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: 55,
          height: 55,
          child: QueryArtworkWidget(
            controller: audioQuery,
            id: songs[index].id,
            type: ArtworkType.AUDIO,
            artworkFit: BoxFit.cover,
            nullArtworkWidget: const Icon(
              Icons.music_note,
              size: 30,
            ),
          ),
        ),
      ),
      title: Text(
        songs[index].title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        songs[index].artist ?? "Unknown Artist",
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