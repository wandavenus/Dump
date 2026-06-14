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
    if (state == AppLifecycleState.resumed) applyEdgeToEdge();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: MyScrollBehavior(),
      builder: (context, child) {
        applyEdgeToEdge();
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
      routes: {
        '/settings':   (context) => const SettingsPage(),
        '/list_test':  (context) => const WebView(child: ListTest()),
        '/firstpage':  (context) => const WebView(child: FirstPage()),
        '/browse':     (context) => const WebView(child: BrowsePage()),
        '/radio':      (context) => const WebView(child: RadioPage()),
        '/library':    (context) => const WebView(child: LibraryPage()),
        '/search':     (context) => const WebView(child: SearchPage()),
        '/home':       (context) => const WebView(child: HomePage()),
        '/album':      (context) => const WebView(child: AlbumPage()),
        '/artist':     (context) => const WebView(child: ArtistPage()),
        '/artistlist': (context) => const WebView(child: ArtistList()),
        '/musiclist':  (context) => const WebView(child: MusicList()),
        '/player':     (context) => const WebView(child: MusicPlayer()),
      },
    );
  }
}
