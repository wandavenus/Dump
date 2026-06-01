import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// import 'package:musicplayer/audioManager.dart';

class MusicList extends StatefulWidget {
  const MusicList({super.key});

  @override
  State<MusicList> createState() => _MusicListState();
}

class _MusicListState extends State<MusicList> {
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
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.red),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          "         Recently Played",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: GridView.builder(
        itemCount: song.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, // number of Rows in the grid
          childAspectRatio: .750, // ratio of Row width to row height
        ),
        itemBuilder: (context, index) {
          return InkWell(
            onTap: () async {
              Navigator.pushNamed(context, '/player', arguments: {
                'index': index
              });
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
                  ClipPath(
                    clipper: ShapeBorderClipper(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    child: CachedNetworkImage(
                      placeholder: (context, url) => const CircularProgressIndicator(),
                      errorWidget: (context, url, error) => const Icon(Icons.error),
                      imageUrl: song[index]['image'],
                      height: 180,
                      width: 180,
                      fit: BoxFit.cover,
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
                            song[index]['title'],
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
                          song[index]['artist'],
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
