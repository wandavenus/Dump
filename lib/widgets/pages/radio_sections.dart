import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/sample_music_data.dart';
import '../common/scrolling_page_chrome.dart';
import 'home_sections.dart';

class RadioPageContent extends StatelessWidget {
  const RadioPageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const LargePageTitle(title: 'Radio'),
          const HeaderDivider(),
          const SizedBox(height: 12),
          const RadioStationsList(),
          const SectionTitle(
            title: 'Recently Played',
            routeName: '/musiclist',
            horizontalPadding: 16,
            showChevron: false,
          ),
          SongCarousel(songs: radioSongs, itemCount: 2),
        ],
      ),
    );
  }
}

class RadioStationsList extends StatelessWidget {
  const RadioStationsList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        radioStations.length,
        (index) => RadioStationCard(station: radioStations[index]),
      ),
    );
  }
}

class RadioStationCard extends StatelessWidget {
  const RadioStationCard({super.key, required this.station});

  final Map station;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(station['text1'],
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(station['text2'],
                style: const TextStyle(color: Colors.grey, fontSize: 15)),
          ),
          Container(
            height: 240,
            margin: const EdgeInsets.only(left: 16, right: 16, top: 10),
            child: Row(
              children: [
                ClipPath(
                  clipper: ShapeBorderClipper(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: CachedNetworkImage(
                    placeholder: (context, url) => const CircularProgressIndicator(),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                    imageUrl: station['image'],
                    height: 220,
                    width: 170,
                    fit: BoxFit.cover,
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 220,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color.fromARGB(255, 52, 52, 52), Color.fromARGB(255, 27, 27, 27)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('LIVE • 9:30 - 11:30 PM',
                              style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                          Text(station['title'],
                              style: const TextStyle(fontSize: 18), overflow: TextOverflow.ellipsis),
                          Text(station['artist'],
                              style: const TextStyle(color: Colors.grey, fontSize: 14),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
