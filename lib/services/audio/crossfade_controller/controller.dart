part of '../crossfade_controller.dart';

/// Implements real crossfade: as a track approaches its end, volume fades
/// smoothly to 0, the next track starts, then volume ramps back to 1.
///
/// Uses a lightweight periodic timer (50 ms ticks) to compute the fade curve
/// without adding heavy stream overhead.
class CrossfadeController {
  CrossfadeController._();

  static Timer? _ticker;
  static bool _fading = false;
  static bool _initialized = false;

  // ── Init / dispose ─────────────────────────────────────────────────────────

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _ticker = Timer.periodic(const Duration(milliseconds: 50), _onTick);
    LogService.log('Crossfade', 'Controller initialized');
  }

  static void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _initialized = false;
    _fading = false;
  }

  // ── Tick ───────────────────────────────────────────────────────────────────

  static void _onTick(Timer _) {
    final crossSec = AudioEffectsService.crossfadeDuration.value;
    if (crossSec <= 0) {
      // Crossfade disabled – reset volume if we left it dirty
      if (_fading) {
        _fading = false;
        _setVolume(1.0);
      }
      return;
    }

    final player = AudioEngine.player;

    // Only active while the player is playing a real track.
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
      // ── Fade-out phase ──────────────────────────────────────────────────
      final fadeRatio = (remaining / crossMs).clamp(0.0, 1.0).toDouble();
      final volume = _easeInQuad(fadeRatio);
      _setVolume(volume);

      if (!_fading) {
        _fading = true;
        LogService.log('Crossfade', 'Fade-out started (${remaining}ms left)');
      }

      // Near the very end: trigger advance so the transition feels smooth.
      if (remaining <= 120) {
        _triggerNext(player);
      }
    } else if (_fading) {
      // ── Fade-in phase (next track just started) ─────────────────────────
      final elapsed = pos.inMilliseconds;
      final fadeInRatio = (elapsed / crossMs).clamp(0.0, 1.0).toDouble();
      final volume = _easeOutQuad(fadeInRatio);
      _setVolume(volume);

      if (fadeInRatio >= 1.0) {
        _fading = false;
        _setVolume(1.0);
        LogService.log('Crossfade', 'Fade-in complete');
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static bool _triggered = false;

  static void _triggerNext(AudioPlayer player) {
    if (_triggered) return;
    _triggered = true;

    Future.microtask(() async {
      try {
        if (player.hasNext) {
          await player.seekToNext();
        }
      } catch (error) {
        LogService.warn('Crossfade', 'seekToNext gagal: $error');
      }
      _triggered = false;
    });
  }

  static void _setVolume(double v) {
    try {
      AudioEngine.player.setVolume(v.clamp(0.0, 1.0).toDouble());
    } catch (error) {
      LogService.warn('Crossfade', 'setVolume gagal: $error');
    }
  }

  // Ease curves for a more musical feel.
  static double _easeInQuad(double t) => t * t;
  static double _easeOutQuad(double t) => t * (2 - t);
}
