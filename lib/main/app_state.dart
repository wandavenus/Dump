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
    MediaCapabilitiesService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      applyEdgeToEdge();
      unawaited(
        AudioService.syncFromNative().catchError(
          (Object e) => LogService.warn('AppState', 'syncFromNative error: $e'),
        ),
      );
      unawaited(OpenFileService.onResume());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      NativePaletteService.clearMemoryCache();
      unawaited(
        LyricsSettings.flush().catchError(
          (Object e) =>
              LogService.warn('AppState', 'LyricsSettings.flush error: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (_, mode, _) {
        return ListenableBuilder(
          listenable: LanguageManager.instance,
          builder: (_, _) {
            final locale = LanguageManager.instance.locale;
            return MaterialApp(
              scrollBehavior: MyScrollBehavior(),
              theme: AppThemes.light,
              darkTheme: AppThemes.dark,
              themeMode: mode,
              // ── Localization ──────────────────────────────────────────────
              locale: locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en'), Locale('id')],
              localeResolutionCallback: (deviceLocale, supported) {
                // If user chose explicit locale, honour it (already set via
                // LanguageManager.locale above).
                if (locale != null) return locale;
                // Otherwise follow device locale, falling back to English.
                if (deviceLocale != null) {
                  final match = supported.where(
                    (l) => l.languageCode == deviceLocale.languageCode,
                  );
                  if (match.isNotEmpty) return match.first;
                }
                return const Locale('en');
              },
              // ─────────────────────────────────────────────────────────────
              builder: (context, child) {
                applyEdgeToEdge();
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
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
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
              debugShowCheckedModeBanner: false,
              home: const WebView(child: FirstPage()),
            );
          },
        );
      },
    );
  }
}
