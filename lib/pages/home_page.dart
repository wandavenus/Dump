import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:musicplayer/webView/webViewContainer.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List TopPicks = [
    {
      //here i mentioned the color in hexadecimal format should start with 0xFF
      "topMsg": "Made for you",
      "image": "https://upload.wikimedia.org/wikipedia/en/1/1b/Joji_-_Nectar.png",
      "title": "Nectar",
      "artist": "Joji",
      "song": ""
    },
    {
      "topMsg": "New Release",
      "image": "https://static.stereogum.com/uploads/2023/03/LDR-Tunnel-1679672318-1000x1000.jpg",
      "title": "Ocean Blvd",
      "artist": "Lana Del Rey",
      "song": ""
    },
    {
      "topMsg": "Featuring Tame Impala",
      "image": "https://qodeinteractive.com/magazine/wp-content/uploads/2020/06/16-Tame-Impala.jpg",
      "title": "Tame Impala",
      "artist": "Currents",
      "song": ""
    },
    {
      "topMsg": "Made for you",
      "image": "https://t2.gstatic.com/licensed-image?q=tbn:ANd9GcT9kry1myZTi2dMJ7OtgJjmdT__lImpI-pJ9mdq42Cz8HhIet_ro_Obp6q4xbksBbpT",
      "title": "The dark side of the moon",
      "artist": "Pink floyd ",
      "song": ""
    },
    // {
    //   "topMsg": "Featuring Tame Nico",
    //   "image":
    //       "https://upload.wikimedia.org/wikipedia/en/0/0c/Velvet_Underground_and_Nico.jpg",
    //   "title": "The Velvet Underground and Nico",
    //   "artist": "Nico",
    //   "song": ""
    // },
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
    },
    
    {
      "id": "spatial_01",
      "title": "Pre-game marching band",
      "album": "Spatial Audio",
      "artist": "Watson Wu",
      "genre": "People",
      "source": "https://storage.googleapis.com/uamp/Spatial Audio/Marching band.wav",
      "image": "https://storage.googleapis.com/uamp/Spatial Audio/Marching band.jpg",
      "trackNumber": 1,
      "totalTrackCount": 6,
      "duration": 56,
      "site": "https://library.soundfield.com/track/163"
    },
    {
      "id": "spatial_02",
      "title": "Chickens on a farm",
      "album": "Spatial Audio",
      "artist": "Watson Wu",
      "genre": "Animals",
      "source": "https://storage.googleapis.com/uamp/Spatial Audio/Chickens.wav",
      "image": "https://storage.googleapis.com/uamp/Spatial Audio/Chickens.jpg",
      "trackNumber": 2,
      "totalTrackCount": 6,
      "duration": 180,
      "site": "https://library.soundfield.com/track/129"
    },
    {
      "id": "spatial_03",
      "title": "Rural market busker",
      "album": "Spatial Audio",
      "artist": "Stephan Schutze",
      "genre": "Ambience",
      "source": "https://storage.googleapis.com/uamp/Spatial Audio/Rural market.wav",
      "image": "https://storage.googleapis.com/uamp/Spatial Audio/Rural market.jpg",
      "trackNumber": 3,
      "totalTrackCount": 6,
      "duration": 299,
      "site": "https://library.soundfield.com/track/55"
    },
    {
      "id": "spatial_04",
      "title": "Steamtrain interior",
      "album": "Spatial Audio",
      "artist": "Stephan Schutze",
      "genre": "Ambience",
      "source": "https://storage.googleapis.com/uamp/Spatial Audio/Steamtrain.wav",
      "image": "https://storage.googleapis.com/uamp/Spatial Audio/Steamtrain.jpg",
      "trackNumber": 4,
      "totalTrackCount": 6,
      "duration": 296,
      "site": "https://library.soundfield.com/track/65"
    }
    
  ];
  List Artist = [
    [
      {
        'artist': 'Joji',
        'artist_img': 'https://www.billboard.com/wp-content/uploads/2020/03/joji-2020-cr-Damien-Maloney-billboard-1548-1585678185.jpg?w=942&h=623&crop=1',
        'image': 'https://i.scdn.co/image/ab67616d0000b27308596cc28b9f5b00bfe08ae7', //url
        'song': 'Glimpse of Us',
        'album': 'Nectar',
      },
      {
        'artist': 'Joji',
        'artist_img': 'https://www.billboard.com/wp-content/uploads/2020/03/joji-2020-cr-Damien-Maloney-billboard-1548-1585678185.jpg?w=942&h=623&crop=1',

        'image': 'https://i.scdn.co/image/ab67616d0000b27360ba1d6104d0475c7555a6b2', //url
        'song': 'Slow Dancing in the Dark',
        'album': 'BALLADS 1',
      },
      {
        'artist': 'Joji',
        'artist_img': 'https://www.billboard.com/wp-content/uploads/2020/03/joji-2020-cr-Damien-Maloney-billboard-1548-1585678185.jpg?w=942&h=623&crop=1',

        'image': 'https://i.scdn.co/image/ab67616d0000b2734896429a87abfacd5d90587b', //url
        'song': 'Run',
        'album': 'BALLADS 1',
      },
      {
        'artist': 'Joji',
        'artist_img': 'https://www.billboard.com/wp-content/uploads/2020/03/joji-2020-cr-Damien-Maloney-billboard-1548-1585678185.jpg?w=942&h=623&crop=1',

        'image': 'https://i.scdn.co/image/ab67616d0000b27323c552a7a4fdafac02e08c34', //url
        'song': 'Sanctuary',
        'album': 'NECTAR',
      },
    ],
    [
      {
        'artist': 'Lana Del Rey',
        'artist_img': 'https://media.themusic.com.au/images/standard/Artists/L/lana-del-rey/lana-del-rey-did-you-know.990x660.jpg',
        'image': 'https://i.scdn.co/image/ab67616d0000b273cb76604d9c5963544cf5be64', //url
        'song': 'Born to Die',
        'album': 'Born to Die',
      },
      {
        'artist': 'Lana Del Rey',
        'artist_img': 'https://media.themusic.com.au/images/standard/Artists/L/lana-del-rey/lana-del-rey-did-you-know.990x660.jpg',
        'image': 'https://i.scdn.co/image/ab67616d00001e02aa27708d07f49c82ff0d0dae', //url
        'song': 'Video Games',
        'album': 'Born to Die',
      },
      {
        'artist': 'Lana Del Rey',
        'artist_img': 'https://media.themusic.com.au/images/standard/Artists/L/lana-del-rey/lana-del-rey-did-you-know.990x660.jpg',
        'image': 'https://i.scdn.co/image/ab67616d00001e020fa3aa7c15a3d57b3c6f74e9', //url
        'song': 'Summertime Sadness',
        'album': 'Born to Die',
      },
      {
        'artist': 'Lana Del Rey',
        'artist_img': 'https://media.themusic.com.au/images/standard/Artists/L/lana-del-rey/lana-del-rey-did-you-know.990x660.jpg',
        'image': 'https://i.scdn.co/image/ab67616d00001e021624590458126fc8b8c64c2f', //url
        'song': 'Blue Jeans',
        'album': 'Ultraviolence',
      },
    ],
    [
      {
        'artist': 'Tame Impala',
        'artist_img': 'https://i0.wp.com/sinusoidalmusic.com/wp-content/uploads/2023/03/Web-capture_10-3-2023_194552_i1.wp.com_.jpeg?fit=1684%2C945&ssl=1',
        'image': 'https://i.scdn.co/image/ab67616d0000b2739169478a2159b97202ef35b0', //url
        'song': 'Let It Happen',
        'album': 'Currents',
      },
      {
        'artist': 'Tame Impala',
        'artist_img': 'https://i0.wp.com/sinusoidalmusic.com/wp-content/uploads/2023/03/Web-capture_10-3-2023_194552_i1.wp.com_.jpeg?fit=1684%2C945&ssl=1',

        'image': 'https://i.scdn.co/image/ab67616d0000b2739e1cfc756886ac782e363d79', //url
        'song': 'The Less I Know the Better',
        'album': 'Currents',
      },
      {
        'artist': 'Tame Impala',
        'artist_img': 'https://i0.wp.com/sinusoidalmusic.com/wp-content/uploads/2023/03/Web-capture_10-3-2023_194552_i1.wp.com_.jpeg?fit=1684%2C945&ssl=1',

        'image': 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQy07EW5VPnMshmSD9_Gy2kFRmm4X3_1ckmutnBnPx9-GqHyI8isKu0tnhmwJL9ioUhynE&usqp=CAU', //url
        'song': 'Elephant',
        'album': 'Lonerism',
      },
      {
        'artist': 'Tame Impala',
        'artist_img': 'https://i0.wp.com/sinusoidalmusic.com/wp-content/uploads/2023/03/Web-capture_10-3-2023_194552_i1.wp.com_.jpeg?fit=1684%2C945&ssl=1',

        'image': 'https://i.scdn.co/image/ab67616d0000b273370c12f82872c9cfaee80193', //url
        'song': 'Feels Like We Only Go Backwards',
        'album': 'Currents',
      },
    ],
    [
      {
        'artist': 'Nico',
        'artist_img': 'https://m.media-amazon.com/images/M/MV5BNjIxYzRiMTgtN2Y2Ni00Zjg0LTkxOWEtMTg1Y2UxZjliM2MwL2ltYWdlXkEyXkFqcGdeQXVyNDkzNTM2ODg@._V1_.jpg',
        'image': 'https://i.scdn.co/image/ab67616d0000b2739169478a2159b97202ef35b0', //url
        'song': 'Let It Happen',
        'album': 'Currents',
      },
      {
        'artist': 'Nico',
        'artist_img': 'https://m.media-amazon.com/images/M/MV5BNjIxYzRiMTgtN2Y2Ni00Zjg0LTkxOWEtMTg1Y2UxZjliM2MwL2ltYWdlXkEyXkFqcGdeQXVyNDkzNTM2ODg@._V1_.jpg',
        'image': 'https://i.scdn.co/image/ab67616d0000b2739e1cfc756886ac782e363d79', //url
        'song': 'The Less I Know the Better',
        'album': 'Currents',
      },
      {
        'artist': 'Nico',
        'artist_img': 'https://m.media-amazon.com/images/M/MV5BNjIxYzRiMTgtN2Y2Ni00Zjg0LTkxOWEtMTg1Y2UxZjliM2MwL2ltYWdlXkEyXkFqcGdeQXVyNDkzNTM2ODg@._V1_.jpg',
        'image': 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQy07EW5VPnMshmSD9_Gy2kFRmm4X3_1ckmutnBnPx9-GqHyI8isKu0tnhmwJL9ioUhynE&usqp=CAU', //url
        'song': 'Elephant',
        'album': 'Lonerism',
      },
      {
        'artist': 'Nico',
        'artist_img': 'https://m.media-amazon.com/images/M/MV5BNjIxYzRiMTgtN2Y2Ni00Zjg0LTkxOWEtMTg1Y2UxZjliM2MwL2ltYWdlXkEyXkFqcGdeQXVyNDkzNTM2ODg@._V1_.jpg',
        'image': 'https://i.scdn.co/image/ab67616d0000b273370c12f82872c9cfaee80193', //url
        'song': 'Feels Like We Only Go Backwards',
        'album': 'Currents',
      },
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  automaticallyImplyLeading: false,
  backgroundColor: Colors.black,
  surfaceTintColor: Colors.transparent,

  actions: [
    IconButton(
      onPressed: () {},
      icon: const Icon(
        Icons.cast_outlined,
        color: Color(0xFFF92D48),
        size: 24,
      ),
    ),
    PopupMenuButton(
      icon: const Icon(
        Icons.more_vert,
        color: Color(0xFFF92D48),
        size: 24,
      ),
      itemBuilder: (context) => [],
    ),
  ],
),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              // color: Colors.amber,
              padding: const EdgeInsets.only(left: 15),
              child: const Text(
                "Top Picks For You",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              // color: Color.fromARGB(255, 5, 69, 68),
              height: 371,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                itemCount: TopPicks.length,
                itemBuilder: (context, index) {
                  return InkWell(
                    onTap: () {
                      Navigator.pushNamed(context, '/album', arguments: {
                        'index': index
                      });
                    },
                    child: Container(
                      // color: Colors.amber,
                      margin: const EdgeInsets.only(right: 10, left: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            TopPicks[index]['topMsg'],
                            style: const TextStyle(color: Color.fromARGB(255, 153, 153, 153), fontSize: 15),
                          ),
                          const SizedBox(
                            height: 7,
                          ),
                          ClipPath(
                            clipper: const ShapeBorderClipper(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
                              ),
                            ),
                            child: CachedNetworkImage(
                              placeholder: (context, url) => const CircularProgressIndicator(),
                              errorWidget: (context, url, error) => const Icon(Icons.error),
                              imageUrl: TopPicks[index]['image'],
                              height: 250,
                              width: 250,
                              fit: BoxFit.cover,
                            ),
                          ),
                          ClipPath(
                            clipper: const ShapeBorderClipper(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(15), bottomRight: Radius.circular(15)),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.only(left: 10, right: 10),
                              height: 70,
                              width: 250,
                              decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                colors: [
                                  Color.fromARGB(255, 83, 83, 83),
                                  Color.fromARGB(255, 36, 36, 36)
                                ],
                                stops: [
                                  0,
                                  1
                                ],
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                              )),

                              // color: Color.fromARGB(255, 255, 227, 114),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Padding(padding: EdgeInsets.only(top: 1)),
                                  Text(
                                    TopPicks[index]['title'],
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    TopPicks[index]['artist'],
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              // color: Colors.amber,
              margin: const EdgeInsets.only(top: 20),
              height: 30,
              padding: const EdgeInsets.only(left: 15),
              child: InkWell(
                onTap: () {
                  Navigator.pushNamed(context, '/musiclist');
                },
                child: const Row(
                  children: [
                    Text(
                      "Recently Played",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Color.fromARGB(255, 186, 186, 186),
                    )
                  ],
                ),
              ),
            ),
            SizedBox(
              // color: Color.fromARGB(255, 5, 69, 68),
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                itemCount: 10,
                itemBuilder: (context, index) {
                  return InkWell(
                    onTap: () {
                      Navigator.pushNamed(context, '/player', arguments: {
                        'index': index
                      });
                    },
                    child: Container(
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
                              imageUrl: song[index]['image'],
                              height: 170,
                              width: 170,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(padding: EdgeInsets.only(top: 2.5)),
                              SizedBox(
                                width: 165,
                                // color: Colors.amberAccent,
                                child: Text(
                                  song[index]['title'],
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 15, color: Colors.white),
                                ),
                              ),
                              Text(
                                song[index]['artist'],
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              // color: Colors.amber,
              margin: const EdgeInsets.only(top: 20),
              // height: 300,
              padding: const EdgeInsets.only(left: 15),
              child: InkWell(
                onTap: () {
                  Navigator.pushNamed(context, '/artistlist');
                },
                child: const Row(
                  children: [
                    Text(
                      "Favourite Artists",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Color.fromARGB(255, 186, 186, 186),
                    )
                  ],
                ),
              ),
            ),
            SizedBox(
                height: 250,
                // width: 165,
                // color: Colors.blue,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: Artist.length,
                  itemBuilder: (context, index) {
                    return InkWell(
                      onTap: () {
                        Navigator.pushNamed(context, '/artist', arguments: {
                          'index': index
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(top: 20, left: 15, bottom: 20),
                        // color: const Color.fromARGB(255, 112, 145, 172),
                        child: Column(
                          children: [
                            ClipPath(
                                clipper: ShapeBorderClipper(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(200),
                                  ),
                                ),
                                child: CachedNetworkImage(
                                  placeholder: (context, url) => const CircularProgressIndicator(),
                                  errorWidget: (context, url, error) => const Icon(Icons.error),
                                  imageUrl: Artist[index][index]['artist_img'],
                                  height: 150,
                                  width: 150,
                                  fit: BoxFit.cover,
                                )),
                            const SizedBox(
                              height: 5,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  Artist[index][index]['artist'],
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(
                                  width: 5,
                                ),
                                const Icon(
                                  Icons.star,
                                  color: Color.fromARGB(255, 255, 0, 0),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ))
          ],
        ),
      ),
    );
  }
}
