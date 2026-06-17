part of '../bottom_nav.dart';

class _FirstPageState extends State<FirstPage> {
  int _selectedIndex = 0;

  void _navgateBottomBar(int index) {
    setState(() {
      _selectedIndex = index;
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
            currentIndex: _selectedIndex,
            onTap: _navgateBottomBar,
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 26), label: 'Beranda'),
              const BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded, size: 26), label: 'Baru'),
              const BottomNavigationBarItem(icon: Icon(Icons.sensors, size: 26), label: 'Radio'),
              const BottomNavigationBarItem(icon: Icon(Icons.subscriptions_rounded, size: 26), label: 'Perpustakaan'),
              const BottomNavigationBarItem(icon: Icon(Icons.search, size: 26), label: 'Cari'),
            ],
            elevation: 0,
            selectedLabelStyle: const TextStyle(color: Colors.white),
            selectedItemColor: const Color(0xFFF92D48),
            unselectedItemColor: Colors.grey,
            showUnselectedLabels: true,
            backgroundColor: isGlass ? Colors.transparent : const Color(0xFF1C1C1E),
            unselectedFontSize: 11.0,
            selectedFontSize: 11.0,
          ),
        );

        return PopScope(
          canPop: !PlayerSheetController.expanded.value,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && PlayerSheetController.expanded.value) {
              PlayerSheetController.close();
            }
          },
          child: Stack(
            children: [
              Scaffold(
                extendBody: isGlass,
                body: IndexedStack(
                  index: _selectedIndex,
                  children: _pages.cast<Widget>(),
                ),
                bottomNavigationBar: ValueListenableBuilder<double>(
                  valueListenable: PlayerSheetController.progress,
                  builder: (context, progress, _) {
                    final opacity = (1 - progress).clamp(0.0, 1.0);

                    final column = Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: opacity,
                          child: const MiniPlayer(),
                        ),
                        if (!isGlass)
                          Container(
                            height: 1.5,
                            color: const Color(0xFF38383A),
                          ),
                        SizedBox(
                          height: 70,
                          child: navBar,
                        ),
                      ],
                    );

                    return Transform.translate(
                      offset: Offset(0, 24 * progress),
                      child: Opacity(
                        opacity: opacity,
                        child: isGlass ? GlassNavBar(child: column) : column,
                      ),
                    );
                  },
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: PlayerSheetController.expanded,
                builder: (context, expanded, _) {
                  return PlayerSheet(expanded: expanded);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}