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
      displayLarge:   _sfProText,
      displayMedium:  _sfProText,
      displaySmall:   _sfProText,
      headlineLarge:  _sfProText,
      headlineMedium: _sfProText,
      headlineSmall:  _sfProText,
      titleLarge:     _sfProText,
      titleMedium:    _sfProText,
      titleSmall:     _sfProText,
      bodyLarge:      _sfProText,
      bodyMedium:     _sfProText,
      bodySmall:      _sfProText,
      labelLarge:     _sfProText,
      labelMedium:    _sfProText,
      labelSmall:     _sfProText,
    ),
  );

  static const TextStyle _sfProText = TextStyle(fontFamily: 'SF Pro Text');
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
      home: const WebView(child: FirstPage()),
    );
  }
}
