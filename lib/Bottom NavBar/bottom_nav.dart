// ignore_for_file: prefer_const_literals_to_create_immutables
import '../services/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:glassmorphism_widgets/glassmorphism_widgets.dart';
import 'package:musicplayer/pages/artist_list.dart';
import 'package:musicplayer/pages/browse_page.dart';
import 'package:musicplayer/pages/home_page.dart';
import 'package:musicplayer/pages/library_page.dart';
import 'package:musicplayer/pages/music_list.dart';
import 'package:musicplayer/pages/radio.dart';
import 'package:musicplayer/pages/search_page.dart';

class FirstPage extends StatefulWidget {
  const FirstPage({super.key});

  @override
  State<FirstPage> createState() => _FirstPageState();
}

class _FirstPageState extends State<FirstPage> {
  int _selected_index = 0;

  void _navgateBottomBar(int index) {
    setState(() {
      _selected_index = index;
    });
  }

  final List _pages = [
    const HomePage(),
    const BrowsePage(),
    const RadioPage(),
    const LibraryPage(),
    const SearchPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selected_index],
      bottomNavigationBar: Column(
  mainAxisSize: MainAxisSize.min,
  children: [

    if (AudioService.currentSong != null)
      Container(
        height: 65,
        margin: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [

            const Icon(
              Icons.music_note,
              color: Colors.white,
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Text(
                AudioService.currentSong!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            IconButton(
              onPressed: () async {
                if (AudioService.player.playing) {
                  await AudioService.player.pause();
                } else {
                  await AudioService.player.play();
                }

                setState(() {});
              },
              icon: Icon(
                AudioService.player.playing
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
            ),
          ],
        ),
      ),

    SizedBox(
      height: 80,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selected_index,
          onTap: _navgateBottomBar,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_filled, size: 35),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded, size: 35),
              label: 'Browse',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.sensors, size: 35),
              label: 'Radio',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.subscriptions_rounded, size: 35),
              label: 'Library',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.search, size: 35),
              label: 'Search',
            ),
          ],
          elevation: 0,
          selectedLabelStyle: const TextStyle(color: Colors.white),
          selectedItemColor: const Color.fromARGB(255, 255, 17, 0),
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
          backgroundColor: Colors.transparent,
          unselectedFontSize: 13.0,
          selectedFontSize: 13.0,
          ),
        ),
      ),
    ),
  ],
),
        
      ),
    );
  }
}
