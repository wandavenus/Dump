part of '../main.dart';

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // ThemeData is immutable (all values are const) — extracted here so it is
  // created once at first build and reused on every subsequent rebuild instead
  // of allocating a new heavyweight object each time.
  // TODO(refactor): move to a top-level constant when ThemeData gains a const
  //   constructor, or extract to a dedicated theme.dart file.
  static final ThemeData _appTheme = ThemeData(
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFF92D48),
      secondary: Color(0xFFF92D48),
    ),
    scaffoldBackgroundColor: const Color.fromARGB(255, 0, 0, 0),
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
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    fontFamily: 'SF Pro Text',
    textTheme: const TextTheme(
      displayLarge:   TextStyle(fontFamily: 'SF Pro Text'),
      displayMedium:  TextStyle(fontFamily: 'SF Pro Text'),
      displaySmall:   TextStyle(fontFamily: 'SF Pro Text'),
      headlineLarge:  TextStyle(fontFamily: 'SF Pro Text'),
      headlineMedium: TextStyle(fontFamily: 'SF Pro Text'),
      headlineSmall:  TextStyle(fontFamily: 'SF Pro Text'),
      titleLarge:     TextStyle(fontFamily: 'SF Pro Text'),
      titleMedium:    TextStyle(fontFamily: 'SF Pro Text'),
      titleSmall:     TextStyle(fontFamily: 'SF Pro Text'),
      bodyLarge:      TextStyle(fontFamily: 'SF Pro Text'),
      bodyMedium:     TextStyle(fontFamily: 'SF Pro Text'),
      bodySmall:      TextStyle(fontFamily: 'SF Pro Text'),
      labelLarge:     TextStyle(fontFamily: 'SF Pro Text'),
      labelMedium:    TextStyle(fontFamily: 'SF Pro Text'),
      labelSmall:     TextStyle(fontFamily: 'SF Pro Text'),
    ),
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // MediaCapabilitiesService holds a StreamSubscription (_stereoWideningSub)
    // that must be cancelled when the app widget tree is torn down.
    MediaCapabilitiesService.dispose();
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
      // ThemeData is defined as a static field above (_appTheme) so it is
      // allocated once and reused across rebuilds instead of being re-created
      // every time the widget tree rebuilds.
      theme: _appTheme,
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
