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
      unawaited(AudioService.syncFromNative().catchError(
        (e) => LogService.warn('AppState', 'syncFromNative error: $e'),
      ));
      // Check for any pending open-file URI that arrived during a warm restart
      // before the Dart handler was fully ready.
      unawaited(OpenFileService.onResume());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Clear heavy in-memory caches to free up RAM for other apps while we
      // are in the background. Disk caches remain safe.
      PaletteExtractor.clearMemoryCache();

      // Flush any debounced settings writes (e.g. lyrics appearance sliders)
      // before the app goes to background, so a pending write isn't lost.
      unawaited(LyricsSettings.flush().catchError(
        (e) => LogService.warn('AppState', 'LyricsSettings.flush error: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: MyScrollBehavior(),
      builder: (context, child) {
        applyEdgeToEdge();   // Jangan di pindahkan
        return ValueListenableBuilder<bool>(
          valueListenable: WatermarkService.visible,
          builder: (_, show, _) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (show)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: SafeArea(
                      bottom: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            WatermarkService.text,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                              decoration: TextDecoration.none,
                              shadows: const [
                                Shadow(
                                  color: Color(0xCC000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      theme: ThemeData(
        // ColorScheme.dark() defaults to a purple primary (0xFFBB86FC) and
        // teal secondary (0xFF03DAC6) from Material's baseline dark theme.
        // Any widget that relies on theme colors without an explicit color
        // (text selection handles, Switch/Slider/Checkbox/Radio thumbs,
        // ProgressIndicator, ripple/splash highlights, etc.) would otherwise
        // render in that default purple/teal instead of the app's red accent.
        // Overriding primary/secondary here makes them all follow the same
        // red used everywhere else in the app (Color(0xFFF92D48)).
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF92D48),
          secondary: Color(0xFFF92D48),
        ),
        scaffoldBackgroundColor: const Color.fromARGB(255, 0, 0, 0),

        // Radius kotak untuk semua AlertDialog & PopupMenuButton dipaksa 3px
        // di sini supaya konsisten di seluruh app tanpa perlu set shape
        // manual di tiap pemanggilan showDialog/PopupMenuButton.
        dialogTheme: const DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(3)),
          ),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(3)),
          ),
        ),

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
