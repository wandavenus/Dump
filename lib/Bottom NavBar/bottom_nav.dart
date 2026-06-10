// ignore_for_file: prefer_const_literals_to_create_immutables
import 'package:musicplayer/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/pages/browse_page.dart';
import 'package:musicplayer/pages/home_page.dart';
import 'package:musicplayer/pages/library_page.dart';
import 'package:musicplayer/pages/radio.dart';
import 'package:musicplayer/pages/search_page.dart';
import 'package:musicplayer/themes/apple_music_blur.dart';
import 'package:musicplayer/themes/glass_navbar.dart';
import 'package:musicplayer/themes/theme_controller.dart';

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
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassTheme,
      builder: (context, isGlass, _) {
        final navBar = Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _selected_index,
            onTap: _navgateBottomBar,
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 26), label: 'Beranda'),
              const BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded, size: 26), label: 'Baru'),
              const BottomNavigationBarItem(icon: Icon(Icons.sensors, size: 26), label: 'Radio'),
              const BottomNavigationBarItem(icon: Icon(Icons.subscriptions_rounded, size: 26), label: 'Perpustakaan'),
              const BottomNavigationBarItem(icon: Icon(Icons.search, size: 26), label: 'Cari'),
            ],
            elevation: 0,
            selectedLabelStyle: const TextStyle(
              color: AppleMusicColors.label,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
            selectedItemColor: AppleMusicColors.accent,
            unselectedItemColor: AppleMusicColors.tertiaryLabel,
            showUnselectedLabels: true,
            backgroundColor: Colors.transparent,
            unselectedFontSize: 11.0,
            selectedFontSize: 11.0,
          ),
        );

        return Scaffold(
          backgroundColor: AppleMusicColors.background,
          extendBody: true,
          body: IndexedStack(
            index: _selected_index,
            children: _pages.cast<Widget>(),
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MiniPlayer(),
              SizedBox(
                height: 70,
                child: isGlass
                    ? GlassNavBar(child: navBar)
                    : AppleMusicMaterial(
                        style: AppleMusicMaterialStyle.regular,
                        borderRadius: BorderRadius.zero,
                        showShadow: false,
                        child: navBar,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
