part of '../main.dart';

Future<void> main() async {
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
  ]);
  NativeLogBridge.init();

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
}
