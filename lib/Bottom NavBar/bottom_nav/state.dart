part of '../bottom_nav.dart';

/// Observer yang dipasang di setiap tab Navigator.
/// Setiap kali route berubah (push/pop), ia memanggil [onChanged]
/// sehingga _FirstPageState bisa rebuild dan PopScope.canPop selalu akurat.
class _TabNavObserver extends NavigatorObserver {
  final VoidCallback onChanged;
  _TabNavObserver({required this.onChanged});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      onChanged();
}

class _FirstPageState extends State<FirstPage> {
  int _selectedIndex = 0;

  // Satu Navigator key per tab.
  final List<GlobalKey<NavigatorState>> _tabNavKeys = List.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );

  // Observer reaktif per tab — trigger setState agar canPop selalu segar.
  late final List<_TabNavObserver> _tabObservers;

  @override
  void initState() {
    super.initState();
    _tabObservers = List.generate(
      5,
      (_) => _TabNavObserver(onChanged: () {
        if (mounted) setState(() {});
      }),
    );
  }

  // Root widget tiap tab.
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

  /// Route generator bersama untuk semua tab Navigator.
  Route<dynamic>? _tabRoute(int tabIndex, RouteSettings settings) {
    // Initial route — tampilkan halaman tab tanpa animasi.
    if (settings.name == Navigator.defaultRouteName) {
      return PageRouteBuilder<void>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => _tabRoots[tabIndex],
        transitionsBuilder: (_, __, ___, child) => child,
      );
    }

    // Detail routes yang di-push dari dalam tab manapun.
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
      default:
        return null;
    }
    return ZoomFadeRoute(page: page, settings: settings);
  }

  /// Reaktif: selalu akurat karena _TabNavObserver trigger setState saat route berubah.
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
              // canPop akurat karena observer rebuild saat inner nav berubah.
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
                          observers: [_tabObservers[i]],
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
