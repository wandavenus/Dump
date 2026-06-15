part of '../crossfade_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CrossfadeController — True Dual-Player Crossfade
// ─────────────────────────────────────────────────────────────────────────────
//
//  Crossfade flow:
//    1. Timer detects remaining ≤ crossfadeDuration on active player.
//    2. Next track is loaded on the STANDBY player at volume=0.
//    3. Both players run simultaneously:
//         active:  volume  1 → 0  (ease-out)
//         standby: volume  0 → 1  (ease-in)
//    4. When complete: AudioEngine.handoff() swaps roles.
//       Old active is stopped; AudioService callback updates state.
//
//  Manual skip with crossfade:
//    Caller invokes triggerNow(nextIndex) and the same flow runs immediately.
// ─────────────────────────────────────────────────────────────────────────────

class CrossfadeController {
  CrossfadeController._();

  static Timer? _ticker;
  static bool _crossfading   = false;
  static bool _standbyReady  = false;
  static int? _pendingIndex;

  // ── Callbacks registered by AudioService ─────────────────────────────────

  static int? Function()? _getNextIndex;
  static LocalSong? Function(int index)? _getSong;
  static void Function(int newIndex)? _onHandoffComplete;

  // ── Init / Dispose ────────────────────────────────────────────────────────

  static void initialize({
    required int? Function() getNextIndex,
    required LocalSong? Function(int index) getSong,
    required void Function(int newIndex) onHandoffComplete,
  }) {
    _getNextIndex      = getNextIndex;
    _getSong           = getSong;
    _onHandoffComplete = onHandoffComplete;

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 20), _onTick);
    LogService.log('Crossfade', 'Controller initialized (dual-player)');
  }

  static void dispose() {
    _ticker?.cancel();
    _ticker       = null;
    _crossfading  = false;
    _standbyReady = false;
    _pendingIndex = null;
  }

  // ── Manual trigger ────────────────────────────────────────────────────────

  /// Immediately start a crossfade to [nextIndex], regardless of position.
  /// Used by AudioService.skipNext / skipPrevious / playFromCurrentQueue.
  static Future<void> triggerNow(int nextIndex) async {
    if (_crossfading) {
      // Allow overriding the pending song mid-crossfade only if not yet committed
      if (!_standbyReady) {
        _pendingIndex = nextIndex;
      }
      return;
    }

    final song = _getSong?.call(nextIndex);
    if (song == null) return;

    _pendingIndex = nextIndex;
    _crossfading  = true;
    _standbyReady = false;
    await _startStandby(song);
  }

  /// Abort any running crossfade and restore both players to a clean state.
  static void cancel() {
    if (!_crossfading) return;
    try {
      AudioEngine.activeSlot.setVolume(1.0);
      AudioEngine.standbySlot.setVolume(0.0);
      AudioEngine.standbyPlayer.stop();
    } catch (_) {}
    _crossfading  = false;
    _standbyReady = false;
    _pendingIndex = null;
    LogService.log('Crossfade', 'Cancelled');
  }

  // ── Timer tick ────────────────────────────────────────────────────────────

  static void _onTick(Timer _) {
    final crossSec = AudioEffectsService.crossfadeDuration.value;
    final active   = AudioEngine.activePlayer;

    // Nothing to do if player is idle/stopped
    if (active.processingState == ProcessingState.idle    ||
        active.processingState == ProcessingState.completed) {
      if (_crossfading) _crossfading = false;
      return;
    }

    final pos = active.position;
    final dur = active.duration;
    if (dur == null || dur.inMilliseconds <= 0) return;

    final remainingMs = (dur - pos).inMilliseconds;
    if (remainingMs < 0) return;

    // Crossfade disabled – reset if somehow active
    if (crossSec <= 0) {
      if (_crossfading) cancel();
      return;
    }

    final crossMs = (crossSec * 1000).round();

    // ── Auto-trigger when approaching end ────────────────────────────────
    if (!_crossfading && remainingMs > 0 && remainingMs <= crossMs) {
      final nextIdx  = _getNextIndex?.call();
      final nextSong = nextIdx != null ? _getSong?.call(nextIdx) : null;
      if (nextIdx != null && nextSong != null) {
        _pendingIndex = nextIdx;
        _crossfading  = true;
        _standbyReady = false;
        _startStandby(nextSong);
      }
      return; // let next tick start the actual fade
    }

    // ── Run fade ──────────────────────────────────────────────────────────
    if (_crossfading && _standbyReady) {
      if (remainingMs <= 0) {
        _complete();
        return;
      }
      final ratio = (remainingMs / crossMs).clamp(0.0, 1.0);
      AudioEngine.activeSlot.setVolume(_easeOut(ratio));
      AudioEngine.standbySlot.setVolume(_easeIn(1.0 - ratio));

      if (ratio <= 0.01) _complete(); // small epsilon to avoid floating-point runon
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<void> _startStandby(LocalSong song) async {
    try {
      final standby = AudioEngine.standbyPlayer;
      AudioEngine.standbySlot.setVolume(0.0);
      await standby.setAudioSource(buildAudioSource(song));
      await standby.play();
      _standbyReady = true;
      LogService.log('Crossfade', 'Standby loaded: ${song.title}');
    } catch (e) {
      LogService.warn('Crossfade', 'startStandby failed: $e');
      _crossfading  = false;
      _standbyReady = false;
      _pendingIndex = null;
    }
  }

  static void _complete() {
    final prevActivePlayer = AudioEngine.activePlayer;
    final nextIdx          = _pendingIndex;

    // Swap roles
    AudioEngine.handoff();

    // New active should be at full volume
    AudioEngine.activeSlot.setVolume(1.0);

    // Stop old active (now standby), reset volume for future use
    try {
      prevActivePlayer.stop();
      prevActivePlayer.setVolume(1.0);
    } catch (_) {}

    _crossfading  = false;
    _standbyReady = false;
    _pendingIndex = null;

    if (nextIdx != null) {
      _onHandoffComplete?.call(nextIdx);
      LogService.log('Crossfade', 'Complete → index $nextIdx');
    }
  }

  // ── Easing ────────────────────────────────────────────────────────────────

  static double _easeIn(double t)  => t * t;
  static double _easeOut(double t) => 1.0 - (1.0 - t) * (1.0 - t);
}
