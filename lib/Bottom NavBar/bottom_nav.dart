// ignore_for_file: prefer_const_literals_to_create_immutables
import 'package:flutter/material.dart';
import 'package:musicplayer/pages/browse_page.dart';
import 'package:musicplayer/pages/home_page.dart';
import 'package:musicplayer/pages/library_page.dart';
import 'package:musicplayer/pages/radio.dart';
import 'package:musicplayer/pages/search_page.dart';
import 'package:musicplayer/themes/glass_navbar.dart';
import 'package:musicplayer/widgets/mini_player.dart';

class FirstPage extends StatefulWidget {
  const FirstPage({super.key});

  @override
  State<FirstPage> createState() => _FirstPageState();
}

class _FirstPageState extends State<FirstPage> {
  int _selectedIndex = 0;

  void _navigateBottomBar(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  final List<Widget> _pages = const [
    HomePage(),
    BrowsePage(),
    RadioPage(),
    LibraryPage(),
    SearchPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final navBar = Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _navigateBottomBar,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled, size: 26),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded, size: 26),
            label: 'Baru',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sensors, size: 26),
            label: 'Radio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.subscriptions_rounded, size: 26),
            label: 'Perpustakaan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search, size: 26),
            label: 'Cari',
          ),
        ],
        elevation: 0,
        selectedLabelStyle: const TextStyle(color: Colors.white),
        selectedItemColor: const Color(0xFFFF2D55),
        unselectedItemColor: Colors.white60,
        showUnselectedLabels: true,
        backgroundColor: Colors.transparent,
        unselectedFontSize: 11,
        selectedFontSize: 11,
      ),
    );

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          SizedBox(
            height: 72,
            child: GlassNavBar(child: navBar),
          ),
        ],
      ),
    );
  }
}
