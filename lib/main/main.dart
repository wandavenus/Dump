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

  await ThemeController.init();
  await LogService.init();
  NativeLogBridge.init();
  await LyricsSettings.init();
  await UpNextSettings.init();

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

  runApp(const MyApp());
}
