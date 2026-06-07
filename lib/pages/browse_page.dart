import 'dart:math';
import 'package:musicplayer/widgets/common_actions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
 
double _scrollOffset = 0;

 List ban = [
    {
      't1': 'WOMENS HISTORY MONTH',
      't2': 'Alpha',
      't3': 'Apple Music',
      'img': 'assets/1.jpg',
    },
    {
      't1': 'NEW PLAYLIST',
      't2': 'Reception Hits',
      't3': 'Apple Music',
      'img': 'assets/2.jpg',
    },
    
    {
      't1': 'ADD TO YOUR LIBRARY',
      't2': 'Soul Revival',
      't3': 'Apple Music R&B',
      'img': 'assets/4.jpg',
    }
    
  ];
  List song = [
    {
      "id": "wake_up_01",
      "title": "Intro - The Way Of Waking Up (feat. Alan Watts)",
      "album": "Wake Up",
      "artist": "The Kyoto Connection",
      "genre": "Electronic",
      "source": "https://storage.googleapis.com/uamp/The_Kyoto_Connection_-_Wake_Up/01_-_Intro_-_The_Way_Of_Waking_Up_feat_Alan_Watts.mp3",
      "image": "https://d1csarkz8obe9u.cloudfront.net/posterpreviews/love-song-mixtape-album-cover-template-design-250a66b33422287542e2690b437f881b_screen.jpg?ts=1635176340",
      "trackNumber": 1,
      "totalTrackCount": 13,
      "duration": 90,
      "site": "http://freemusicarchive.org/music/The_Kyoto_Connection/Wake_Up_1957/"
    },
    {
      "id": "wake_up_02",
      "title": "Geisha",
      "album": "Wake Up",
      "artist": "The Kyoto Connection",
      "genre": "Electronic",
      "source": "https://storage.googleapis.com/uamp/The_Kyoto_Connection_-_Wake_Up/02_-_Geisha.mp3",
      "image": "https://storage.googleapis.com/uamp/The_Kyoto_Connection_-_Wake_Up/art.jpg",
      "trackNumber": 2,
      "totalTrackCount": 13,
      "duration": 267,
      "site": "http://freemusicarchive.org/music/The_Kyoto_Connection/Wake_Up_1957/"
    },
    {
      "id": "wake_up_03",
      "title": "Voyage I - Waterfall",
      "album": "Wake Up",
      "artist": "The Kyoto Connection",
      "genre": "Electronic",
      "source": "https://storage.googleapis.com/uamp/The_Kyoto_Connection_-_Wake_Up/03_-_Voyage_I_-_Waterfall.mp3",
      "image": "https://storage.googleapis.com/uamp/The_Kyoto_Connection_-_Wake_Up/art.jpg",
      "trackNumber": 3,
      "totalTrackCount": 13,
      "duration": 264,
      "site": "http://freemusicarchive.org/music/The_Kyoto_Connection/Wake_Up_1957/"
    }
    
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: Colors.black,
    surfaceTintColor: Colors.transparent,

title: Transform.translate(
  offset: Offset(
    0,
    (1 - (_scrollOffset / 100).clamp(0.0, 1.0)) * 40,
  ),
  child: Opacity(
    opacity: ((((_scrollOffset - 25) / 25)
          .clamp(0.0, 1.0)) *
        1.5)
    .clamp(0.0, 1.0),
    child: const Text(
      "Baru",
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
 ),    
centerTitle: false,

   actions: const [
  CommonActions(),
],
 
bottom: PreferredSize(
  preferredSize: const Size.fromHeight(0.5),
  child: Opacity(
    opacity: (_scrollOffset / 140).clamp(0.0, 1.0),
    child: Container(
      height: 0.9,
      color: const Color(0xFF48484A),
    ),
  ),
),
  ),
      body: NotificationListener<ScrollNotification>(
  onNotification: (notification) {
  if (notification is ScrollUpdateNotification &&
      notification.metrics.axis == Axis.vertical) {
    setState(() {
      _scrollOffset = notification.metrics.pixels;
    });
  }
  return false;
},
  child: SingleChildScrollView(
        child: Column(
          children: [
          
const Padding(
  padding: EdgeInsets.fromLTRB(
    16,
    14,
    16,
    6,
  ),
  child: Align(
    alignment: Alignment.centerLeft,
    child: Text(
      "Baru",
      style: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
),

const Padding(
  padding: EdgeInsets.symmetric(
    horizontal: 16,
  ),
  child: Divider(
    color: Color(0xFF48484A),
    thickness: 0.5,
    height: 0,
  ),
),

const SizedBox(height: 12),

  Container(
                padding: const EdgeInsets.only(
  top: 0,
),
                height: 350,
                // width: 1080 / 2.5,
                // color: const Color.fromARGB(255, 80, 71, 37),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: ban.length,
                  itemBuilder: (context, index) {
                    return Container(
                      // color: Colors.red,
                      width: 370,
                      margin: const EdgeInsets.only(left: 6, right: 6),
                      child: Center(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ban[index]['t1'],
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              ban[index]['t2'],
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.normal, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              ban[index]['t3'],
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.normal, color: Colors.grey),
                            ),
                            const SizedBox(
                              height: 5,
                            ),
                            ClipPath(
                                clipper: ShapeBorderClipper(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                                ),
                                child: Image.asset(
                                  ban[index]['img'],
                                  height: 720 / 3,
                                  width: 1080 / 3,
                                  fit: BoxFit.cover,
                                )),
                          ],
                        ),
                      ),
                    );
                  },
                )),
            Container(
              margin: const EdgeInsets.only(top: 10),
              // color: Colors.amber,
              padding: const EdgeInsets.only(left: 15),
              child: const Row(
                children: [
                  Text(
                    "We Recommend",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Color.fromARGB(255, 186, 186, 186),
                  )
                ],
              ),
            ),
            SizedBox(
              // color: Color.fromARGB(255, 5, 69, 68),
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                itemCount: song.length,
                itemBuilder: (context, index) {
                  int randomIndex = Random().nextInt(song.length);

                  return Container(
                    // color: Colors.amber,
                    margin: const EdgeInsets.only(right: 10, left: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          height: 10,
                        ),
                        ClipPath(
                          clipper: ShapeBorderClipper(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: CachedNetworkImage(
                            placeholder: (context, url) => const CircularProgressIndicator(),
                            errorWidget: (context, url, error) => const Icon(Icons.error),
                            imageUrl: song[randomIndex]['image'],
                            height: 170,
                            width: 170,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(padding: EdgeInsets.only(top: 1)),
                            SizedBox(
                              width: 165,
                              // color: Colors.amberAccent,
                              child: Text(
                                song[randomIndex]['title'],
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 15, color: Colors.white),
                              ),
                            ),
                            Text(
                              song[randomIndex]['artist'],
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 10),
              // color: Colors.amber,
              padding: const EdgeInsets.only(left: 15),
              child: const Row(
                children: [
                  Text(
                    "Now in Spatial Audio",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Color.fromARGB(255, 186, 186, 186),
                  )
                ],
              ),
            ),
            SizedBox(
              // color: Color.fromARGB(255, 5, 69, 68),
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                itemCount: song.length,
                itemBuilder: (context, index) {
                  int randomIndex = Random().nextInt(song.length);

                  return Container(
                    // color: Colors.amber,
                    margin: const EdgeInsets.only(right: 10, left: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          height: 10,
                        ),
                        ClipPath(
                          clipper: ShapeBorderClipper(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: CachedNetworkImage(
                            placeholder: (context, url) => const CircularProgressIndicator(),
                            errorWidget: (context, url, error) => const Icon(Icons.error),
                            imageUrl: song[randomIndex]['image'],
                            height: 170,
                            width: 170,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(padding: EdgeInsets.only(top: 1)),
                            SizedBox(
                              width: 165,
                              // color: Colors.amberAccent,
                              child: Text(
                                song[randomIndex]['title'],
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 15, color: Colors.white),
                              ),
                            ),
                            Text(
                              song[randomIndex]['artist'],
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 10),
              // color: Colors.amber,
              padding: const EdgeInsets.only(left: 15),
              child: const Row(
                children: [
                  Text(
                    "Apple Music Sing",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Color.fromARGB(255, 186, 186, 186),
                  )
                ],
              ),
            ),
            SizedBox(
              // color: Colors.amber,
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Column(
                    // mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            // color: const Color.fromARGB(255, 255, 7, 94),
                            gradient: const LinearGradient(
                              colors: [
                                Color.fromARGB(255, 251, 47, 88),
                                Color.fromARGB(255, 255, 174, 174)
                              ],
                              stops: [
                                0.4,
                                1
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            )),
                        margin: const EdgeInsets.only(top: 10, left: 10),
                        height: 100,
                        width: 200,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "Let's",
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Color.fromARGB(255, 255, 255, 255),
                                    offset: Offset(0, 0),
                                    blurRadius: 15,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                          margin: const EdgeInsets.only(top: 5, left: 10),
                          child: const Text(
                            "Start Singing",
                            style: TextStyle(color: Colors.white),
                          ))
                    ],
                  ),
                  Column(
                    // mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            // color: const Color.fromARGB(255, 255, 7, 94),
                            gradient: const LinearGradient(
                              colors: [
                                Color.fromARGB(255, 251, 47, 88),
                                Color.fromARGB(255, 255, 174, 174)
                              ],
                              stops: [
                                0.4,
                                1
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            )),
                        margin: const EdgeInsets.only(top: 10, left: 10),
                        height: 100,
                        width: 200,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "Sing",
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Color.fromARGB(255, 255, 255, 255),
                                    offset: Offset(0, 0),
                                    blurRadius: 15,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.music_note_outlined,
                              size: 35,
                              shadows: [
                                Shadow(
                                  color: Color.fromARGB(255, 255, 255, 255),
                                  offset: Offset(0, 0),
                                  blurRadius: 15,
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                      Container(
                          margin: const EdgeInsets.only(top: 5, left: 10),
                          child: const Text(
                            "Start Singing",
                            style: TextStyle(color: Colors.white),
                          ))
                    ],
                  ),
                  Column(
                    // mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            // color: const Color.fromARGB(255, 255, 7, 94),
                            gradient: const LinearGradient(
                              colors: [
                                Color.fromARGB(255, 251, 47, 88),
                                Color.fromARGB(255, 255, 174, 174)
                              ],
                              stops: [
                                0.4,
                                1
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            )),
                        margin: const EdgeInsets.only(top: 10, left: 10),
                        height: 100,
                        width: 200,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "With",
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Color.fromARGB(255, 255, 255, 255),
                                    offset: Offset(0, 0),
                                    blurRadius: 15,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                          margin: const EdgeInsets.only(top: 5, left: 10),
                          child: const Text(
                            "Start Singing",
                            style: TextStyle(color: Colors.white),
                          ))
                    ],
                  ),
                  Column(
                    // mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            // color: const Color.fromARGB(255, 255, 7, 94),
                            gradient: const LinearGradient(
                              colors: [
                                Color.fromARGB(255, 251, 47, 88),
                                Color.fromARGB(255, 255, 174, 174)
                              ],
                              stops: [
                                0.4,
                                1
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            )),
                        margin: const EdgeInsets.only(top: 10, left: 10),
                        height: 100,
                        width: 200,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "Apple",
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Color.fromARGB(255, 255, 255, 255),
                                    offset: Offset(0, 0),
                                    blurRadius: 15,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                          margin: const EdgeInsets.only(top: 5, left: 10),
                          child: const Text(
                            "Start Singing",
                            style: TextStyle(color: Colors.white),
                          ))
                    ],
                  ),
                  Column(
                    // mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            // color: const Color.fromARGB(255, 255, 7, 94),
                            gradient: const LinearGradient(
                              colors: [
                                Color.fromARGB(255, 251, 47, 88),
                                Color.fromARGB(255, 255, 174, 174)
                              ],
                              stops: [
                                0.4,
                                1
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            )),
                        margin: const EdgeInsets.only(top: 10, left: 10),
                        height: 100,
                        width: 200,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "Music",
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Color.fromARGB(255, 255, 255, 255),
                                    offset: Offset(0, 0),
                                    blurRadius: 15,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                          margin: const EdgeInsets.only(top: 5, left: 10),
                          child: const Text(
                            "Start Singing",
                            style: TextStyle(color: Colors.white),
                          ))
                    ],
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 10),
              // color: Colors.amber,
              padding: const EdgeInsets.only(left: 15),
              child: const Row(
                children: [
                  Text(
                    "Daily Top 100",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Color.fromARGB(255, 186, 186, 186),
                  )
                ],
              ),
            ),
            SizedBox(
              // color: Color.fromARGB(255, 5, 69, 68),
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                itemCount: song.length,
                itemBuilder: (context, index) {
                  int randomIndex = Random().nextInt(song.length);

                  return Container(
                    // color: Colors.amber,
                    margin: const EdgeInsets.only(right: 10, left: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          height: 10,
                        ),
                        ClipPath(
                          clipper: ShapeBorderClipper(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: CachedNetworkImage(
                            placeholder: (context, url) => const CircularProgressIndicator(),
                            errorWidget: (context, url, error) => const Icon(Icons.error),
                            imageUrl: song[randomIndex]['image'],
                            height: 170,
                            width: 170,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(padding: EdgeInsets.only(top: 1)),
                            SizedBox(
                              width: 165,
                              // color: Colors.amberAccent,
                              child: Text(
                                song[randomIndex]['title'],
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 15, color: Colors.white),
                              ),
                            ),
                            Text(
                              song[randomIndex]['artist'],
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
       ),
      ),
     
  );
  }
}
