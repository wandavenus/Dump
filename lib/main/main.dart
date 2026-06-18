part of '../main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
  await LyricsSettings.init();

  // Order matters: AudioEngine must be ready before AudioEffectsService,
  // which must be ready before AudioService.
  await AudioEngine.initialize();
  await AudioEffectsService.init();
  AudioService.initialize();
  AudioFocusService.initialize();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await Permission.storage.request();
    await Permission.audio.request();
  }

  runApp(const MyApp());
}
