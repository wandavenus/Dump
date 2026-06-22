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
    } catch (e) {
      LogService.warn('AudioSession', 'Init failed: $e');
    }
  }

  static void onAppPause() {}
  static void onAppResume() {}
}
