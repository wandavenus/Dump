import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio/playback_manager.dart';
import 'log_service.dart';

enum SleepTimerMode { duration, endOfSong }

/// Sleep timer — fully native-backed.
///
/// All timer logic runs inside Media3PlaybackService.kt on a Handler so it
/// fires reliably while the app is backgrounded.
///
/// This class is a thin UI adapter:
///   • Delegates start/cancel to native via MethodChannel.
///   • Mirrors the native sleepTimerStream into [remaining] + [isActive]
///     ValueNotifiers so UI widgets can react without polling.
///
/// AudioService automatically keeps [AudioPlaybackState.sleepTimerActive] and
/// [AudioPlaybackState.sleepTimerRemainingMs] up-to-date from the same stream.
class SleepTimerService {
  SleepTimerService._();

  static StreamSubscription<Map<dynamic, dynamic>>? _sub;
  static SleepTimerMode? _mode;

  static final ValueNotifier<Duration?> remaining = ValueNotifier(null);
  static final ValueNotifier<bool> isActive = ValueNotifier(false);

  /// True while the 20-second fade-out is running (timer already fired,
  /// volume still ramping down). Kept separate from [isActive] — which stays
  /// true during the fade so the sheet keeps showing a cancel button — so the
  /// active card can render "Fading out…" instead of a 00:00 countdown.
  static final ValueNotifier<bool> isFading = ValueNotifier(false);

  static bool get endOfSongMode => _mode == SleepTimerMode.endOfSong;

  // ── Initialize (subscribe to native stream) ───────────────────────────────

  static void initialize() {
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _sub = PlaybackManager.sleepTimerStream.listen((map) {
      final active = map['active'] as bool? ?? false;
      final fading = map['fading'] as bool? ?? false;
      final endOfSong = map['endOfSong'] as bool? ?? false;
      final remainingMs = (map['remainingMs'] as num?)?.toInt() ?? 0;

      isActive.value = active;
      isFading.value = fading;

      if (!active) {
        remaining.value = null;
        _mode = null;
      } else if (endOfSong) {
        _mode = SleepTimerMode.endOfSong;
        remaining.value = null;
      } else {
        _mode = SleepTimerMode.duration;
        remaining.value = Duration(milliseconds: remainingMs);
      }
    });
  }

  // F5 fix: the timer lives in the native service — the optimistic UI state
  // must be rolled back if the MethodChannel call actually fails (e.g. the
  // service never became ready and _invoke's 5 retries were exhausted). A
  // failed start provably means no native timer was armed; a failed cancel
  // means the (dead/not-ready) service had no timer to cancel either — so
  // resetting to inactive is always the truthful state.
  static Future<void> _send(Future<void> nativeCall, String action) async {
    try {
      await nativeCall;
    } on Exception catch (e) {
      LogService.warn('SleepTimer', '$action failed — timer not armed: $e');
      resetToInactive();
    }
  }

  // ── Start by duration ─────────────────────────────────────────────────────

  static void startDuration(Duration duration) {
    _mode = SleepTimerMode.duration;
    isActive.value = true;
    isFading.value = false;
    remaining.value = duration;
    unawaited(
      _send(
        PlaybackManager.setSleepTimer(duration.inMilliseconds),
        'Start timer',
      ),
    );
    LogService.log('SleepTimer', 'Started: ${duration.inMinutes} min');
  }

  // ── Start at end of current song ──────────────────────────────────────────

  static void startEndOfSong() {
    _mode = SleepTimerMode.endOfSong;
    isActive.value = true;
    isFading.value = false;
    remaining.value = null;
    unawaited(
      _send(PlaybackManager.setSleepTimerEndOfSong(), 'Start end-of-song timer'),
    );
    LogService.log('SleepTimer', 'End-of-song mode');
  }

  // ── Cancel ────────────────────────────────────────────────────────────────

  static void cancel() {
    _mode = null;
    isActive.value = false;
    isFading.value = false;
    remaining.value = null;
    unawaited(_send(PlaybackManager.cancelSleepTimer(), 'Cancel timer'));
    LogService.log('SleepTimer', 'Cancelled');
  }

  /// F3 safety net: called when a native snapshot is unavailable (service is
  /// not running / not responding). The timer lives inside the service, so a
  /// dead service provably has no armed timer — reset the mirror instead of
  /// leaving a stale "active" state with a frozen countdown.
  static void resetToInactive() {
    _mode = null;
    isActive.value = false;
    isFading.value = false;
    remaining.value = null;
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  static void dispose() {
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _sub = null;
    isActive.value = false;
    isFading.value = false;
    remaining.value = null;
    _mode = null;
  }

  // ── Quick presets (unchanged from previous impl) ──────────────────────────

  static const List<({Duration? duration})> presets = [
    (duration: Duration(minutes: 15)),
    (duration: Duration(minutes: 30)),
    (duration: Duration(minutes: 45)),
    (duration: Duration(hours: 1)),
    (duration: Duration(minutes: 90)),
    (duration: Duration(hours: 2)),
    (duration: null),
  ];
}
