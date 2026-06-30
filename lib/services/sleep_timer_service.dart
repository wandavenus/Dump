import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio/audio_engine_manager.dart';
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

  static bool get endOfSongMode => _mode == SleepTimerMode.endOfSong;

  // ── Initialize (subscribe to native stream) ───────────────────────────────

  static void initialize() {
    _sub?.cancel();
    _sub = AudioEngineManager.sleepTimerStream.listen((map) {
      final active = map['active'] as bool? ?? false;
      final endOfSong = map['endOfSong'] as bool? ?? false;
      final remainingMs = (map['remainingMs'] as num?)?.toInt() ?? 0;

      isActive.value = active;

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

  // ── Start by duration ─────────────────────────────────────────────────────

  static void startDuration(Duration duration) {
    _mode = SleepTimerMode.duration;
    isActive.value = true;
    remaining.value = duration;
    unawaited(AudioEngineManager.setSleepTimer(duration.inMilliseconds));
    LogService.log('SleepTimer', 'Started: ${duration.inMinutes} min');
  }

  // ── Start at end of current song ──────────────────────────────────────────

  static void startEndOfSong() {
    _mode = SleepTimerMode.endOfSong;
    isActive.value = true;
    remaining.value = null;
    unawaited(AudioEngineManager.setSleepTimerEndOfSong());
    LogService.log('SleepTimer', 'End-of-song mode');
  }

  // ── Cancel ────────────────────────────────────────────────────────────────

  static void cancel() {
    _mode = null;
    isActive.value = false;
    remaining.value = null;
    unawaited(AudioEngineManager.cancelSleepTimer());
    LogService.log('SleepTimer', 'Cancelled');
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  // ── Quick presets (unchanged from previous impl) ──────────────────────────

  static const List<({String label, Duration? duration})> presets = [
    (label: '15 menit', duration: Duration(minutes: 15)),
    (label: '30 menit', duration: Duration(minutes: 30)),
    (label: '45 menit', duration: Duration(minutes: 45)),
    (label: '1 jam', duration: Duration(hours: 1)),
    (label: '1,5 jam', duration: Duration(minutes: 90)),
    (label: '2 jam', duration: Duration(hours: 2)),
    (label: 'Akhir lagu', duration: null),
  ];
}
