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
//
//  Tick/fade logic is in fade_helpers.dart (same library).
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
    _ticker = Timer.periodic(const Duration(milliseconds: 20), _cfOnTick);
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
  static Future<void> triggerNow(int nextIndex) async {
    if (_crossfading) {
      if (!_standbyReady) _pendingIndex = nextIndex;
      return;
    }

    final song = _getSong?.call(nextIndex);
    if (song == null) return;

    _pendingIndex = nextIndex;
    _crossfading  = true;
    _standbyReady = false;
    await _cfStartStandby(song);
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
}
