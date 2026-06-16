part of '../audio_session_handler.dart';

/// Configures the OS audio session and handles interruptions (phone calls,
/// notifications, other apps) properly using the [audio_session] package.
/// This replaces the old placeholder in AudioFocusService.
class AudioSessionHandler {
  AudioSessionHandler._();

  static AudioSession? _session;
  static bool _initialized        = false;
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
        if (event.begin) {
          if (player.playing) {
            _pausedByInterruption = true;
            player.pause();
            // Also pause the secondary player if a crossfade is in progress.
            _pauseSecondaryAndResetFade();
            LogService.log('AudioSession', 'Paused: interruption (pause)');
          }
        } else {
          _handleInterruptionEnd(event);
        }
        break;

      case AudioInterruptionType.duck:
        if (event.begin) {
          player.setVolume(0.3);
          // Duck secondary too (might be fading in).
          try { DualPlayerManager.secondaryPlayer?.setVolume(0.3); } catch (_) {}
          LogService.log('AudioSession', 'Ducked: interruption');
        } else {
          player.setVolume(1.0);
          // Restore secondary to 0 (it should not be audible when preloading).
          try { DualPlayerManager.secondaryPlayer?.setVolume(0.0); } catch (_) {}
          LogService.log('AudioSession', 'Unducked');
        }
        break;

      case AudioInterruptionType.unknown:
        if (event.begin) {
          if (player.playing) {
            _pausedByInterruption = true;
            player.pause();
            _pauseSecondaryAndResetFade();
          }
        } else {
          _handleInterruptionEnd(event);
        }
        break;
    }
  }

  static void _handleInterruptionEnd(AudioInterruptionEvent event) {
    if (!_pausedByInterruption) return;
    _pausedByInterruption = false;
    AudioEngine.player.play();
    LogService.log('AudioSession', 'Resumed after interruption');
  }

  // ── Headphone disconnect ───────────────────────────────────────────────────

  static void _onBecomingNoisy(dynamic _) {
    final player = AudioEngine.player;
    if (player.playing) {
      player.pause();
      _pauseSecondaryAndResetFade();
      LogService.log('AudioSession', 'Paused: headphones disconnected');
    }
  }

  // ── Dual-player helper ────────────────────────────────────────────────────

  /// Pauses the secondary player and resets any in-flight crossfade so that
  /// resuming after an interruption starts cleanly from the primary.
  static void _pauseSecondaryAndResetFade() {
    try { DualPlayerManager.secondaryPlayer?.pause(); } catch (_) {}
    CrossfadeController.reset();
  }

  // ── Manual controls (for AppLifecycle) ────────────────────────────────────

  static void onAppPause() {
    // Handled automatically by the OS audio session.
  }

  static void onAppResume() {
    // Handled automatically by the OS audio session.
  }
}
