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
        fontFamily: 'SF Pro Text',
        textTheme: const TextTheme(
          displayLarge:  TextStyle(fontFamily: 'SF Pro Text'),
          displayMedium: TextStyle(fontFamily: 'SF Pro Text'),
          displaySmall:  TextStyle(fontFamily: 'SF Pro Text'),
          headlineLarge:  TextStyle(fontFamily: 'SF Pro Text'),
          headlineMedium: TextStyle(fontFamily: 'SF Pro Text'),
          headlineSmall:  TextStyle(fontFamily: 'SF Pro Text'),
          titleLarge:  TextStyle(fontFamily: 'SF Pro Text'),
          titleMedium: TextStyle(fontFamily: 'SF Pro Text'),
          titleSmall:  TextStyle(fontFamily: 'SF Pro Text'),
          bodyLarge:   TextStyle(fontFamily: 'SF Pro Text'),
          bodyMedium:  TextStyle(fontFamily: 'SF Pro Text'),
          bodySmall:   TextStyle(fontFamily: 'SF Pro Text'),
          labelLarge:  TextStyle(fontFamily: 'SF Pro Text'),
          labelMedium: TextStyle(fontFamily: 'SF Pro Text'),
          labelSmall:  TextStyle(fontFamily: 'SF Pro Text'),
        ),
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/firstpage',
      onGenerateRoute: (settings) {
        // Detail routes (/album, /artist, etc.) are now handled by each tab's
        // inner Navigator inside FirstPage, so they won't reach here.
        // Only the app shell and settings are handled at the root level.
        switch (settings.name) {
          case '/firstpage':
            return ZoomFadeRoute(
              page: const WebView(child: FirstPage()),
              settings: settings,
            );
          case '/settings':
            return ZoomFadeRoute(
              page: const SettingsPage(),
              settings: settings,
            );
          default:
            return null;
        }
      },
    );
  }
}
