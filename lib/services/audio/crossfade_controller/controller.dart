part of '../crossfade_controller.dart';

/// Implements volume fading around track transitions.
class CrossfadeController {
  CrossfadeController._();

  static Timer? _ticker;
  static bool _fading = false;
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _ticker = Timer.periodic(const Duration(milliseconds: 20), _onTick);
    LogService.log('Crossfade', 'Controller initialized');
  }

  static void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _initialized = false;
    _fading = false;
  }

  static void _onTick(Timer _) {
    final crossSec = AudioEffectsService.crossfadeDuration.value;
    if (crossSec <= 0) {
      if (_fading) {
        _fading = false;
        _setVolume(1.0);
      }
      return;
    }

    final player = AudioEngine.player;

    if (player.processingState == ProcessingState.idle ||
        player.processingState == ProcessingState.completed) {
      _fading = false;
      return;
    }

    final pos = player.position;
    final dur = player.duration;
    if (dur == null || dur.inMilliseconds <= 0) return;

    final crossMs = (crossSec * 1000).round();
    final remaining = dur.inMilliseconds - pos.inMilliseconds;

    if (remaining <= 0) return;

    if (remaining <= crossMs) {
      final fadeRatio = (remaining / crossMs).clamp(0.0, 1.0).toDouble();
      final volume = _easeInQuad(fadeRatio);
      _setVolume(volume);

      if (!_fading) {
        _fading = true;
        LogService.log('Crossfade', 'Fade-out started (${remaining}ms left)');
      }
    } else if (_fading) {
      final fadeInRatio = (pos.inMilliseconds / crossMs)
          .clamp(0.0, 1.0)
          .toDouble();
      final volume = _easeOutQuad(fadeInRatio);
      _setVolume(volume);

      if (fadeInRatio >= 1.0) {
        _fading = false;
        _setVolume(1.0);
        LogService.log('Crossfade', 'Fade-in complete');
      }
    }
  }

  static void _setVolume(double v) {
    try {
      AudioEngine.player.setVolume(v.clamp(0.0, 1.0).toDouble());
    } catch (error) {
      LogService.warn('Crossfade', 'setVolume gagal: $error');
    }
  }

  static double _easeInQuad(double t) => t * t;

  static double _easeOutQuad(double t) => 1 - ((1 - t) * (1 - t));
}
