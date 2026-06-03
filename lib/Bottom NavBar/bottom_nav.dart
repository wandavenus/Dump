// ignore_for_file: prefer_const_literals_to_create_immutables
import '../services/audio_service.dart';
import 'package:musicplayer/widgets/mini_player.dart';
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
     extendBody: true,
 body: IndexedStack(
  index: _selected_index,
  children: _pages.cast<Widget>(),
),
      bottomNavigationBar: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    const MiniPlayer(),
Container(
  height: 1.0,
  color: const Color(0xFF38383A),
),
    SizedBox(
        height: 80,

        // padding: EdgeInsets.only(bottom: 0),
        // color: Colors.amber,
        child: Theme(
          data: Theme.of(context).copyWith(
            // Apply transparent color to both splashColor and highlightColor
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _selected_index,
            onTap: _navgateBottomBar,
            items: [
              const BottomNavigationBarItem(
                icon: Icon(
                  Icons.home_filled,
                  size: 26,
                ),
                label: 'Beranda',
              ),
              const BottomNavigationBarItem(
                  icon: Icon(
                    Icons.grid_view_rounded,
                    size: 26,
                  ),
                  label: 'Baru'),
              const BottomNavigationBarItem(
                  icon: Icon(
                    Icons.sensors,
                    size: 26,
                  ),
                  label: 'Radio'),
              const BottomNavigationBarItem(
                  icon: Icon(
                    Icons.subscriptions_rounded,
                    size: 26,
                  ),
                  label: 'Perpustakaan'),
              const BottomNavigationBarItem(
                  icon: Icon(
                    Icons.search,
                    size: 26,
                  ),
                  label: 'Cari'),
            ],
            elevation: 0,
            selectedLabelStyle: const TextStyle(color: Colors.white),
            selectedItemColor: const Color(0xFFF92D48),
            unselectedItemColor: Colors.grey,
            showUnselectedLabels: true,
            backgroundColor: const Color(0xFF1C1C1E),
            unselectedFontSize: 11.0,
            selectedFontSize: 11.0,
          ),
        ),
      ),
   ],
),
 );
  }
}
