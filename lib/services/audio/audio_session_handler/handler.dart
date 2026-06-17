part of '../audio_session_handler.dart';

/// Configures the OS audio session and handles interruptions (phone calls,
/// notifications, other apps) properly using the [audio_session] package.
/// This replaces the old placeholder in AudioFocusService.
class AudioSessionHandler {
  AudioSessionHandler._();

  static AudioSession? _session;
  static bool _initialized          = false;
  static bool _pausedByInterruption = false;

  /// True while a player promotion is in progress.
  ///
  /// During promotion the old primary is being stopped and disposed; any OS
  /// interruption events fired in that window are spurious (MIUI 12 / Android
  /// 11 focus-steal) and must be ignored.
  static bool _inPromotion = false;

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

      // Register the promotion lock callbacks with DualPlayerManager so they
      // are called atomically around every player swap.
      DualPlayerManager.onBeforePromote = beginPromotion;
      DualPlayerManager.onAfterPromote  = endPromotion;

      LogService.log('AudioSession', 'Configured for music playback');
    } catch (e) {
      LogService.warn('AudioSession', 'Init failed: $e');
    }
  }

  // ── Promotion focus lock ───────────────────────────────────────────────────

  /// Acquires the audio-focus lock before a player swap.
  ///
  /// Calling [AudioSession.setActive(true)] before the swap tells the OS that
  /// the session is still active, preventing MIUI 12 from interpreting the
  /// old player's upcoming [stop()] as a voluntary focus abandonment.
  static void beginPromotion() {
    _inPromotion = true;
    // Fire-and-forget: setActive is best-effort; failure doesn't block swap.
    if (_session != null) {
      _session!.setActive(true).catchError(
        (Object _) => false,
      );
    }
    LogService.verbose('AudioSession', 'Promotion lock acquired');
  }

  /// Releases the focus lock after the old primary player is fully disposed.
  static void endPromotion() {
    _inPromotion = false;
    LogService.verbose('AudioSession', 'Promotion lock released');
  }

  // ── Interruption handling ──────────────────────────────────────────────────

  static void _onInterruption(AudioInterruptionEvent event) {
    if (_inPromotion) {
      LogService.verbose(
        'AudioSession',
        'Interruption suppressed (promotion in progress): '
        '${event.type.name} begin=${event.begin}',
      );
      return;
    }

    final player = AudioEngine.player;

    switch (event.type) {
      case AudioInterruptionType.pause:
        if (event.begin) {
          if (player.playing) {
            _pausedByInterruption = true;
            player.pause();
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
          try { DualPlayerManager.secondaryPlayer?.setVolume(0.3); } catch (_) {}
          LogService.log('AudioSession', 'Ducked: interruption');
        } else {
          player.setVolume(1.0);
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

  static void _onBecomingNoisy(dynamic _) {
    final player = AudioEngine.player;
    if (player.playing) {
      player.pause();
      _pauseSecondaryAndResetFade();
      LogService.log('AudioSession', 'Paused: headphones disconnected');
    }
  }

  static void _pauseSecondaryAndResetFade() {
    try { DualPlayerManager.secondaryPlayer?.pause(); } catch (_) {}
    CrossfadeController.reset();
  }

  static void onAppPause() {}

  static void onAppResume() {}
}
