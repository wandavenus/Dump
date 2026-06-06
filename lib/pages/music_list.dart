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
  actions: [
  Padding(
    padding: const EdgeInsets.only(right: 4),
    child: IconButton(
      onPressed: () {},
      icon: const Icon(CupertinoIcons.airplayaudio),
    ),
  ),
  Padding(
    padding: const EdgeInsets.only(right: 8),
    child: IconButton(
      onPressed: () {},
      icon: const Icon(Icons.more_horiz),
    ),
  ),
],
Divider(
  height: 1,
  thickness: 0.3,
  color: Colors.white24,
)
),
      body: ListView.builder(
  itemCount: songs.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, // number of Rows in the grid
          childAspectRatio: .750, // ratio of Row width to row height
        ),
      
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
            child: Container(
              margin: const EdgeInsets.all(10),
              // color: Colors.amber,
              // height: 100,
              // width: 200,
              padding: const EdgeInsets.only(top: 5, left: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
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
                  const SizedBox(
                    height: 10,
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: SizedBox(
                          width: 300,
                          child: Text(
                            songs[index].title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 5,
                      ),
                      SizedBox(
                        width: 190,
                        child: Text(
  songs[index].artist ?? "Unknown Artist",
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color.fromARGB(255, 182, 182, 182), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
  
      ),
 
    );
  }
}
