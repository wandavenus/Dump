import 'media3/media3_audio_player.dart';

/// Compatibility shim for old Flutter notification hooks.
///
/// Android notification, lock-screen, headset, and Bluetooth controls are now
/// owned by the native Media3 `MediaSessionService`. The existing Flutter audio
/// service still calls this class, but the methods are intentionally no-ops so
/// the UI code can remain unchanged during the native migration.
class BackgroundAudioHandler {
  BackgroundAudioHandler() {
    _instance = this;
  }

  static BackgroundAudioHandler? _instance = BackgroundAudioHandler();
  static BackgroundAudioHandler? get instance => _instance;

  static Future<void> Function()? onPlayRequested;
  static Future<void> Function()? onPauseRequested;
  static Future<void> Function()? onSkipNextRequested;
  static Future<void> Function()? onSkipPrevRequested;
  static Future<void> Function(Duration)? onSeekRequested;
  static Future<void> Function()? onStopRequested;
  static Future<void> Function()? onSetRepeatRequested;
  static Future<void> Function(bool)? onSetShuffleRequested;

  void updateNowPlaying({
    required String id,
    required String title,
    String? artist,
    String? album,
    Duration? duration,
    Uri? artUri,
  }) {}

  void pushPlaybackState({
    required bool playing,
    required ProcessingState processingState,
    Duration updatePosition = Duration.zero,
    double speed = 1.0,
  }) {}
}
