part of '../main.dart';

Future<void> main() async {
  // ── Zone guard — wraps SELURUH startup + runtime ──────────────────────────
  // Menangkap semua Future/Stream error yang tidak punya .catchError dari
  // inisialisasi awal hingga app berjalan. LogService mungkin belum init
  // saat error paling awal terjadi — debugPrint sebagai fallback.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (!kIsWeb) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
      );
    }

    // Empat service ini independen satu sama lain (masing-masing hanya
    // memuat pengaturan sendiri dari SharedPreferences), jadi dijalankan
    // paralel untuk mempercepat waktu ke first frame.
    await Future.wait([
      ThemeController.init(),
      LogService.init(),
      LyricsSettings.init(),
      UpNextSettings.init(),
      WatermarkService.init(),
    ]);
    NativeLogBridge.init();

    // ── Global error hooks (dipasang setelah LogService siap) ───────────────
    //
    // Hook 1 — Flutter framework errors: widget null-ref, layout overflow, dll.
    // presentError dipanggil dulu agar output debug default tetap muncul di
    // console, lalu baru disimpan ke LogService.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      LogService.error(
        'Flutter',
        details.exceptionAsString(),
        stackTrace: details.stack?.toString(),
      );
    };

    // Hook 2 — Dart VM errors yang tidak ter-catch: platform channel exception,
    // isolate uncaught error, dll. Return true = error dianggap sudah ditangani,
    // VM tidak crash.
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      LogService.error('Dart', error.toString(), stackTrace: stack.toString());
      return true;
    };

    // Register the open-file channel handler EARLY so warm-restart intents
    // are not dropped before AudioService is ready. The URI is stored on the
    // native side (pendingOpenFileUri) and drained by checkInitialUri() later.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      OpenFileService.registerHandler();
    }

    // MediaKitSettingsService harus diinisialisasi SEBELUM AudioEngineManager
    // agar setting ter-load ke ValueNotifiers sebelum MediaKitEngine.initialize()
    // memanggil MediaKitSettingsService.applyAll().
    await MediaKitSettingsService.initialize();

    // Order matters: AudioEngineManager harus diinisialisasi pertama
    // (memuat pilihan engine dan menginisialisasi engine yang dipilih).
    // AudioEngine (facade efek) harus siap sebelum AudioEffectsService.
    await AudioEngineManager.initialize();
    await AudioEngine.initialize();
    await AudioEffectsService.init();
    LyricsService.init();
    await MediaCapabilitiesService.initialize();
    AudioService.initialize();
    AudioFocusService.initialize();
    SleepTimerService.initialize();

    // Sync playback state dari engine aktif sebelum merender UI.
    unawaited(AudioService.syncFromNative());

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Permission.storage.request();
      await Permission.audio.request();
    }

    // Drain URI from the intent that cold-started the app.
    // Must come AFTER permissions and AudioService.initialize() because
    // _playUri calls AudioService.playSongAt().
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(OpenFileService.checkInitialUri());
    }

    runApp(const MyApp());
  }, (Object error, StackTrace stack) {
    // Zone handler: fallback ke debugPrint jika LogService belum selesai init.
    if (LogService.isInitialized) {
      LogService.error('Zone', error.toString(), stackTrace: stack.toString());
    } else {
      debugPrint('[Zone/pre-init] $error\n$stack');
    }
  });
}
