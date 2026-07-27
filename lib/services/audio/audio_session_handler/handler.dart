part of '../audio_session_handler.dart';

/// Configures the OS audio session category for music playback.
///
/// Audio focus, ducking, and NOISY-headphones handling are now managed
/// natively by `Media3PlaybackService.kt` (ExoPlayer's built-in focus
/// handling + BroadcastReceiver for ACTION_AUDIO_BECOMING_NOISY).
/// This class is kept for structural compatibility but is intentionally
/// minimal.
class AudioSessionHandler {
  AudioSessionHandler._();

  static AudioSession? _session;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      LogService.log('AudioSession', 'Skipped on web');
      return;
    }

    try {
      _session = await AudioSession.instance;
      await _session!.configure(const AudioSessionConfiguration.music());
      LogService.log('AudioSession', 'Configured for music playback');
    } on Exception catch (e) {
      // AudioSession.instance and configure() can throw PlatformException or
      // StateError depending on the platform and audio session plugin version.
      LogService.warn('AudioSession', 'Init failed: $e');
    }
  }

  /// No-op: audio focus and NOISY-headphones handling are managed natively
  /// by `Media3PlaybackService.kt` (ExoPlayer focus + BroadcastReceiver).
  static void onAppPause() {}

  /// No-op: see [onAppPause].
  static void onAppResume() {}
}
