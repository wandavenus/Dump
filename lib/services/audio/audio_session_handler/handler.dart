part of '../audio_session_handler.dart';

/// Configures the OS audio session and handles interruptions (phone calls,
/// notifications, other apps) properly using the [audio_session] package.
/// This replaces the old placeholder in AudioFocusService.
class AudioSessionHandler {
  AudioSessionHandler._();

  static AudioSession? _session;
  static bool _initialized = false;
  static bool _pausedByInterruption = false;

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

      _session!.interruptionEventStream.listen(_onInterruption);
      _session!.becomingNoisyEventStream.listen(_onBecomingNoisy);

      LogService.log('AudioSession', 'Configured for music playback');
    } catch (e) {
      LogService.warn('AudioSession', 'Init failed: $e');
    }
  }

  // ── Interruption handling ──────────────────────────────────────────────────

  static void _onInterruption(AudioInterruptionEvent event) {
    final player = AudioEngine.player;
    switch (event.type) {
      case AudioInterruptionType.pause:
        if (player.playing) {
          _pausedByInterruption = true;
          player.pause();
          LogService.log('AudioSession', 'Paused: interruption (pause)');
        }
        break;
      case AudioInterruptionType.duck:
        player.setVolume(0.3);
        LogService.log('AudioSession', 'Ducked: interruption');
        break;
      case AudioInterruptionType.unknown:
        if (event.begin) {
          if (player.playing) {
            _pausedByInterruption = true;
            player.pause();
          }
        } else {
          // Interruption ended
          _handleInterruptionEnd(event);
        }
        break;
    }

    if (!event.begin) {
      _handleInterruptionEnd(event);
    }
  }

  static void _handleInterruptionEnd(AudioInterruptionEvent event) {
    final player = AudioEngine.player;
    switch (event.type) {
      case AudioInterruptionType.pause:
        if (_pausedByInterruption) {
          _pausedByInterruption = false;
          player.play();
          LogService.log('AudioSession', 'Resumed after pause interruption');
        }
        break;
      case AudioInterruptionType.duck:
        player.setVolume(1.0);
        LogService.log('AudioSession', 'Unducked');
        break;
      default:
        if (_pausedByInterruption) {
          _pausedByInterruption = false;
          player.play();
          LogService.log('AudioSession', 'Resumed after interruption');
        }
        break;
    }
  }

  // ── Headphone disconnect ───────────────────────────────────────────────────

  static void _onBecomingNoisy(dynamic _) {
    final player = AudioEngine.player;
    if (player.playing) {
      player.pause();
      LogService.log('AudioSession', 'Paused: headphones disconnected');
    }
  }

  // ── Manual controls (for AppLifecycle) ────────────────────────────────────

  static void onAppPause() {
    // Audio session handles this automatically via the OS
  }

  static void onAppResume() {
    // Audio session handles this automatically via the OS
  }
}
