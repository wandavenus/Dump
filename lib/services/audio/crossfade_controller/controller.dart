part of '../crossfade_controller.dart';

/// Dual-player simultaneous crossfade.
///
/// Monitors the primary [AudioPlayer] position on a 20 ms tick.
/// When the track is within [crossfadeDuration] of its end:
///   1. The secondary player (preloaded by [DualPlayerManager]) starts
///      playing at volume 0.
///   2. Both players are faded simultaneously (primary out, secondary in)
///      using ease-curve functions.
///   3. When the fade completes [DualPlayerManager.promote] is called
///      with `fromCrossfade: true` so [AudioService._afterPromotion]
///      advances the queue without calling play().
///
/// [updateContext] must be called by [AudioService._schedulePreload]
/// whenever the next song or loop-mode changes.
class CrossfadeController {
  CrossfadeController._();

  // ── Context (set by AudioService._schedulePreload) ─────────────────────────

  static bool _nextIsGapless = false;
  static bool _loopOne       = false;

  /// Called by [AudioService._schedulePreload] before every preload so
  /// the controller knows whether to skip crossfade.
  static void updateContext({
    required bool nextIsGapless,
    required bool loopOne,
  }) {
    _nextIsGapless = nextIsGapless;
    _loopOne       = loopOne;
  }

  // ── Fade state ─────────────────────────────────────────────────────────────

  static bool _isFading             = false;
  static bool _promoted             = false;
  static int  _fadeStartRemainingMs = 0;

  static double? _lastPrimaryVol;
  static double? _lastSecondaryVol;
  
  /// True while a crossfade is in flight — checked by
  /// [AudioService._onTrackCompleted] to avoid double-advancing.
  static bool get isFading => _isFading;

  // ── Timer ──────────────────────────────────────────────────────────────────

  static Timer? _ticker;
  static bool   _running = false;

  static void initialize() {
    if (_running) return;
    _running = true;
    _ticker  = Timer.periodic(const Duration(milliseconds: 20), _onTick);
    LogService.log('Crossfade', 'Dual-player controller started (20 ms tick)');
  }

  // ── Main tick ──────────────────────────────────────────────────────────────

  static void _onTick(Timer _) {
    // Loop-one and same-album gapless transitions skip crossfade entirely.
    if (_loopOne || _nextIsGapless) {
      if (_isFading) _resetFade();
      return;
    }

    final crossSec = AudioEffectsService.crossfadeDuration.value;
    final primary  = DualPlayerManager.primaryPlayer;

    // ── Handle completed / idle ───────────────────────────────────────────────

    final ps = primary.processingState;
    if (ps == ProcessingState.completed || ps == ProcessingState.idle) {
      if (_isFading && !_promoted) _triggerPromotion();
      return;
    }

    // ── No crossfade configured ───────────────────────────────────────────────

    if (crossSec <= 0) {
      if (_isFading) _resetFade();
      return;
    }

    // ── Guard: valid position/duration ────────────────────────────────────────

    final pos = primary.position;
    final dur = primary.duration;
    if (dur == null || dur.inMilliseconds <= 0) return;

    final crossMs   = (crossSec * 1000).round();
    final remaining = (dur.inMilliseconds - pos.inMilliseconds)
        .clamp(0, dur.inMilliseconds);
    if (remaining <= 0) return;

    // ── Start crossfade when approaching end ──────────────────────────────────

    if (remaining <= crossMs && !_isFading && !_promoted) {
      final secondary = DualPlayerManager.secondaryPlayer;
      if (secondary == null) {
        LogService.verbose(
            'Crossfade', 'Crossfade skipped — secondary not ready');
        return;
      }

      try {
        _setVol(secondary, 0.0);

      if (!secondary.playing) {
        unawaited(secondary.play());
      }
        _isFading             = true;
        _promoted             = false;
        _fadeStartRemainingMs = remaining;
        LogService.log(
          'Crossfade',
          'Dual-player crossfade started '
          '(${remaining}ms left, config=${crossSec}s)',
        );
      } catch (e) {
        LogService.warn('Crossfade', 'Failed to start secondary: $e');
        return;
      }
    }

    // ── Animate volumes ───────────────────────────────────────────────────────

    if (_isFading) {
      final elapsed   = (_fadeStartRemainingMs - remaining).clamp(0, crossMs);
      final fadeRatio = (elapsed / crossMs).clamp(0.0, 1.0);

      final primaryVol = _logFadeOut(fadeRatio);

if (_lastPrimaryVol == null ||
    (primaryVol - _lastPrimaryVol!).abs() > 0.01) {
  _lastPrimaryVol = primaryVol;
  _setVol(primary, primaryVol);
}

final secondary = DualPlayerManager.secondaryPlayer;
if (secondary != null) {
  final secondaryVol = _logFadeIn(fadeRatio);

  if (_lastSecondaryVol == null ||
      (secondaryVol - _lastSecondaryVol!).abs() > 0.01) {
    _lastSecondaryVol = secondaryVol;
    _setVol(secondary, secondaryVol);
  }
}
      if (fadeRatio >= 1.0 && !_promoted) {
        _triggerPromotion();
      }
    }
  }

  // ── Promotion ─────────────────────────────────────────────────────────────

  static void _triggerPromotion() {
    if (_promoted) return;
    _promoted = true;
    _isFading = false;
    LogService.log('Crossfade', 'Fade complete — promoting secondary');
    _lastPrimaryVol = null;
    _lastSecondaryVol = null;
    unawaited(DualPlayerManager.promote(fromCrossfade: true));
  }

  // ── Public reset ──────────────────────────────────────────────────────────

  /// Aborts any in-flight crossfade and restores primary volume to 1.0.
  /// Called by [AudioService] on manual track changes (skip, queue jump).
  static void reset() {
    if (!_isFading && !_promoted) return;
    _resetFade();
    LogService.verbose('Crossfade', 'Reset by AudioService');
  }

  // ── Internal reset ────────────────────────────────────────────────────────

  static void _resetFade() {
   _lastPrimaryVol = null;
   _lastSecondaryVol = null; 
    
    _isFading = false;
    _promoted = false;
    try { _setVol(DualPlayerManager.primaryPlayer, 1.0); } catch (_) {}
    try {
  final sec = DualPlayerManager.secondaryPlayer;
  if (sec != null) {
    _setVol(sec, 0.0);
    unawaited(sec.pause());
  }
} catch (_) {}
  }

  // ── Volume helper ─────────────────────────────────────────────────────────

  static void _setVol(AudioPlayer p, double v) {
    try { p.setVolume(v.clamp(0.0, 1.0)); } catch (_) {}
  }

  // ── Logarithmic volume curves ─────────────────────────────────────────────
  //
  // Both curves operate in the dB domain so the transition sounds perceptually
  // smooth to the human ear (equal-loudness / Fletcher-Munson behaviour).
  //
  //   fade-out: 0 dB → −60 dB  as  t: 0 → 1   →  10^(−3t)
  //   fade-in : −60 dB → 0 dB  as  t: 0 → 1   →  10^(−3(1−t))
  //
  // At t = 0.5 each channel is at −30 dB (≈ 3 % linear), giving a tight
  // overlap without clipping at the crossover point.

  /// Primary channel: logarithmic fade-OUT (1.0 → ~0.001).
  static double _logFadeOut(double t) =>
    math.cos(t * math.pi / 2).clamp(0.0, 1.0);

  /// Secondary channel: logarithmic fade-IN (≈0.001 → 1.0).
  static double _logFadeIn(double t) =>
    math.sin(t * math.pi / 2).clamp(0.0, 1.0);

  // ── Dispose ───────────────────────────────────────────────────────────────

  static void dispose() {
    _ticker?.cancel();
    _ticker   = null;
    _running  = false;
    _isFading = false;
    _promoted = false;
    LogService.log('Crossfade', 'Disposed');
  }
}
