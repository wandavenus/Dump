import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class RadioPage extends StatefulWidget {
  const RadioPage({super.key});

  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
 
double _scrollOffset = 0;

 List radio = [  
  
    {
      'text1': 'Music Hits',
      'text2': 'Songs you know and love',
      "topMsg": "New Release",
      "image": "https://static.stereogum.com/uploads/2023/03/LDR-Tunnel-1679672318-1000x1000.jpg",
      "title": "Ocean Blvd",
      "artist": "Lana Del Rey",
      "song": ""
    },
    {
      'text1': 'Music Country',
      'text2': 'Where it sounds like home',
      "topMsg": "Featuring Tame Impala",
      "image": "https://qodeinteractive.com/magazine/wp-content/uploads/2020/06/16-Tame-Impala.jpg",
      "title": "Tame Impala",
      "artist": "Currents",
      "song": ""
    },
    {
      'text1': 'Music Country',
      'text2': 'Where it sounds like home',
      "topMsg": "Made for you",
      "image": "https://t2.gstatic.com/licensed-image?q=tbn:ANd9GcT9kry1myZTi2dMJ7OtgJjmdT__lImpI-pJ9mdq42Cz8HhIet_ro_Obp6q4xbksBbpT",
      "title": "The dark side of the moon",
      "artist": "Pink floyd ",
      "song": ""
    },
    
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
      "Radio",
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
),

centerTitle: false,

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
      body: NotificationListener<ScrollNotification>(
  onNotification: (notification) {
    setState(() {
      _scrollOffset = notification.metrics.pixels;
    });
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
      "Radio",
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
            // height: 600,
            child: Column(children: [
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                // color: Colors.amber,
                child: Column(
                  children: [
                    Column(
                      // crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    
                                    Container(margin: const EdgeInsets.only(left: 10), child: Text(radio[0]['text1'], style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                                  ],
                                ),
                                Container(margin: const EdgeInsets.only(left: 10), child: Text(radio[0]['text2'], style: const TextStyle(color: Colors.grey, fontSize: 15))),
                              ],
                            ),
                            
                          ],
                        ),
                        Container(
                          // color: Colors.amber,
                          margin: const EdgeInsets.fromLTRB(
  16,
  10,
  16,
  10,
),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipPath(
                                clipper: const ShapeBorderClipper(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
                                  ),
                                ),
                                child: CachedNetworkImage(
                                  placeholder: (context, url) => const CircularProgressIndicator(),
                                  errorWidget: (context, url, error) => const Icon(Icons.error),
                                  imageUrl: radio[0]['image'],
                                  height: 180,
                                  width: double.infinity,
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
                                  height: 80,
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                    colors: [
                                      Color.fromARGB(255, 83, 83, 83),
                                      Color.fromARGB(255, 65, 65, 65)
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text("LIVE • 9:30 - 11:30 PM", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                                Text(
                                                  radio[0]['title'],
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  radio[0]['artist'],
                                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                            
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                // color: Colors.amber,
                child: Column(
                  children: [
                    Column(
                      // crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    
                                    Container(margin: const EdgeInsets.only(left: 10), child: Text(radio[1]['text1'], style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                                  ],
                                ),
                                Container(margin: const EdgeInsets.only(left: 10), child: Text(radio[1]['text2'], style: const TextStyle(color: Colors.grey, fontSize: 15))),
                              ],
                            ),
                            
                          ],
                        ),
                        Container(
                          // color: Colors.amber,
                          margin: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipPath(
                                clipper: const ShapeBorderClipper(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
                                  ),
                                ),
                                child: CachedNetworkImage(
                                  placeholder: (context, url) => const CircularProgressIndicator(),
                                  errorWidget: (context, url, error) => const Icon(Icons.error),
                                  imageUrl: radio[1]['image'],
                                  height: 180,
                                  width: double.infinity,
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
                                  height: 80,
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                    colors: [
                                      Color.fromARGB(255, 83, 83, 83),
                                      Color.fromARGB(255, 65, 65, 65)
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text("LIVE • 9:30 - 11:30 PM", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                                Text(
                                                  radio[1]['title'],
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  radio[1]['artist'],
                                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                            
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                // color: Colors.amber,
                child: Column(
                  children: [
                    Column(
                      // crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    
                                    Container(margin: const EdgeInsets.only(left: 10), child: Text(radio[2]['text1'], style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                                  ],
                                ),
                                Container(margin: const EdgeInsets.only(left: 10), child: Text(radio[2]['text2'], style: const TextStyle(color: Colors.grey, fontSize: 15))),
                              ],
                            ),
                            
                          ],
                        ),
                        Container(
                          // color: Colors.amber,
                          margin: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipPath(
                                clipper: const ShapeBorderClipper(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
                                  ),
                                ),
                                child: CachedNetworkImage(
                                  placeholder: (context, url) => const CircularProgressIndicator(),
                                  errorWidget: (context, url, error) => const Icon(Icons.error),
                                  imageUrl: radio[2]['image'],
                                  height: 180,
                                  width: double.infinity,
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
                                  height: 80,
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                    colors: [
                                      Color.fromARGB(255, 83, 83, 83),
                                      Color.fromARGB(255, 65, 65, 65)
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text("LIVE • 9:30 - 11:30 PM", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                                Text(
                                                  radio[2]['title'],
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  radio[2]['artist'],
                                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                            
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ]),
          ),
          Container(
            // color: Colors.amber,
            margin: const EdgeInsets.only(top: 20),
            height: 30,
            padding: const EdgeInsets.only(left: 16),
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
              itemCount: 4,
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
        ],
      ),
    ),
    );
  }
}
