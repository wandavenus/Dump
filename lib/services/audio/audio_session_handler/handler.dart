part of '../audio_session_handler.dart';

/// Configures the OS audio session and handles interruptions (phone calls,
/// notifications, other apps) using the [audio_session] package.
///
/// All operations are applied to [AudioEngine.activePlayer]; the standby
/// player is already silent, so it needs no special treatment.
class AudioSessionHandler {
  AudioSessionHandler._();

  static AudioSession? _session;
  static bool _initialized          = false;
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
    // Always act on the ACTIVE player; standby is muted already.
    final player = AudioEngine.activePlayer;

    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (player.playing) {
            _pausedByInterruption = true;
            player.pause();
            LogService.log('AudioSession', 'Paused: interruption');
          }
          break;
        case AudioInterruptionType.duck:
          player.setVolume(0.3);
          LogService.log('AudioSession', 'Ducked');
          break;
      }
    } else {
      _handleInterruptionEnd(event);
    }
  }

  static void _handleInterruptionEnd(AudioInterruptionEvent event) {
    final player = AudioEngine.activePlayer;
    switch (event.type) {
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
    final player = AudioEngine.activePlayer;
    if (player.playing) {
      player.pause();
      LogService.log('AudioSession', 'Paused: headphones disconnected');
    }
  }

  static void onAppPause()  {} // handled automatically by the OS session
  static void onAppResume() {}
}
