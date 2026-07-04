part of '../main.dart';

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      applyEdgeToEdge();
      // Re-synchronize with the native Media3 service so the mini player
      // reappears immediately if background playback was active.
      unawaited(AudioService.syncFromNative());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Flush any debounced settings writes (e.g. lyrics appearance sliders)
      // before the app goes to background, so a pending write isn't lost.
      unawaited(LyricsSettings.flush());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: MyScrollBehavior(),
      builder: (context, child) {
        applyEdgeToEdge();   // Jangan di pindahkan
        return child ?? const SizedBox.shrink();
      },
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(),
        scaffoldBackgroundColor: const Color.fromARGB(255, 0, 0, 0),
      
        snackBarTheme: const SnackBarThemeData(
  contentTextStyle: TextStyle(
    color: Colors.white,
  ),
),
        
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        fontFamily: 'SF Pro Display',
        textTheme: const TextTheme(
          displayLarge:  TextStyle(fontFamily: 'SF Pro Display'),
          displayMedium: TextStyle(fontFamily: 'SF Pro Display'),
          displaySmall:  TextStyle(fontFamily: 'SF Pro Display'),
          headlineLarge:  TextStyle(fontFamily: 'SF Pro Display'),
          headlineMedium: TextStyle(fontFamily: 'SF Pro Display'),
          headlineSmall:  TextStyle(fontFamily: 'SF Pro Display'),
          titleLarge:  TextStyle(fontFamily: 'SF Pro Display'),
          titleMedium: TextStyle(fontFamily: 'SF Pro Display'),
          titleSmall:  TextStyle(fontFamily: 'SF Pro Display'),
          bodyLarge:   TextStyle(fontFamily: 'SF Pro Display'),
          bodyMedium:  TextStyle(fontFamily: 'SF Pro Display'),
          bodySmall:   TextStyle(fontFamily: 'SF Pro Display'),
          labelLarge:  TextStyle(fontFamily: 'SF Pro Display'),
          labelMedium: TextStyle(fontFamily: 'SF Pro Display'),
          labelSmall:  TextStyle(fontFamily: 'SF Pro Display'),
        ),
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/firstpage',
      onGenerateRoute: (settings) {
        Widget buildPage() {
          switch (settings.name) {
            case '/settings':   return const SettingsPage();
            case '/firstpage':  return const WebView(child: FirstPage());
            case '/browse':     return const WebView(child: BrowsePage());
            case '/radio':      return const WebView(child: RadioPage());
            case '/library':    return const WebView(child: LibraryPage());
            case '/search':     return const WebView(child: SearchPage());
            case '/home':       return const WebView(child: HomePage());
            case '/album':      return const WebView(child: AlbumPage());
            case '/artist':     return const WebView(child: ArtistPage());
            case '/artistlist': return const WebView(child: ArtistList());
            case '/musiclist':  return const WebView(child: MusicList());
            case '/player':     return const WebView(child: MusicPlayer());
            default:            return const SizedBox.shrink();
          }
        }

        // Unknown route — let Flutter handle it.
        if (settings.name == null ||
            ![
              '/settings', '/firstpage', '/browse', '/radio', '/library',
              '/search', '/home', '/album', '/artist', '/artistlist',
              '/musiclist', '/player',
            ].contains(settings.name)) {
          return null;
        }

        return ZoomFadeRoute(page: buildPage(), settings: settings);
      },
    );
  }
}
