part of '../bottom_nav.dart';

class _FirstPageState extends State<FirstPage> {
  int _selectedIndex = 0;

  // One Navigator key per tab — each tab has its own navigation stack.
  final List<GlobalKey<NavigatorState>> _tabNavKeys = List.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );

  // Root widget for each tab.
  static const List<Widget> _tabRoots = [
    HomePage(),
    BrowsePage(),
    RadioPage(),
    LibraryPage(),
    SearchPage(),
  ];

  void _navgateBottomBar(int index) {
    if (index == _selectedIndex) {
      ScrollToTopService.trigger(index);
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  /// Route generator shared by every tab's inner Navigator.
  /// Handles detail pages so they render inside the tab stack,
  /// keeping BottomNav and MiniPlayer visible.
  Route<dynamic>? _tabRoute(int tabIndex, RouteSettings settings) {
    // Initial route — show the tab's root page with no transition.
    if (settings.name == Navigator.defaultRouteName) {
      return PageRouteBuilder<void>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => _tabRoots[tabIndex],
        transitionsBuilder: (_, __, ___, child) => child,
      );
    }

    // Detail routes pushed from within any tab.
    Widget? page;
    switch (settings.name) {
      case '/album':
        page = const WebView(child: AlbumPage());
      case '/artist':
        page = const WebView(child: ArtistPage());
      case '/artistlist':
        page = const WebView(child: ArtistList());
      case '/musiclist':
        page = const WebView(child: MusicList());
      case '/player':
        page = const WebView(child: MusicPlayer());
      default:
        return null;
    }
    return ZoomFadeRoute(page: page, settings: settings);
  }

  /// Returns true if the active tab's navigator can pop (has a route to go back to).
  bool get _innerCanPop =>
      _tabNavKeys[_selectedIndex].currentState?.canPop() ?? false;

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
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 26), label: 'Beranda'),
              BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded, size: 26), label: 'Baru'),
              BottomNavigationBarItem(icon: Icon(Icons.sensors, size: 26), label: 'Radio'),
              BottomNavigationBarItem(icon: Icon(Icons.subscriptions_rounded, size: 26), label: 'Perpustakaan'),
              BottomNavigationBarItem(icon: Icon(Icons.search, size: 26), label: 'Cari'),
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

        return ValueListenableBuilder<bool>(
          valueListenable: PlayerSheetController.expanded,
          builder: (context, expanded, _) {
            return PopScope(
              // Block back gesture if player is open OR a detail page is shown.
              canPop: !expanded && !_innerCanPop,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (expanded) {
                  PlayerSheetController.close();
                } else {
                  _tabNavKeys[_selectedIndex].currentState?.maybePop();
                }
              },
              child: Stack(
                children: [
                  Scaffold(
                    extendBody: isGlass,
                    body: IndexedStack(
                      index: _selectedIndex,
                      children: List.generate(
                        5,
                        (i) => Navigator(
                          key: _tabNavKeys[i],
                          onGenerateRoute: (s) => _tabRoute(i, s),
                        ),
                      ),
                    ),
                    bottomNavigationBar: ValueListenableBuilder<double>(
                      valueListenable: PlayerSheetController.progress,
                      builder: (context, progress, _) {
                        final column = Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                          offset: Offset(0, 70 * progress),
                          child: isGlass ? GlassNavBar(child: column) : column,
                        );
                      },
                    ),
                  ),
                  // Unified morph player: handles both mini and full-player.
                  const UnifiedMorphPlayer(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
