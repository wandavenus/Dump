import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_service.dart';
import 'log_service.dart';

enum SleepTimerMode { duration, endOfSong }

class SleepTimerService {
  SleepTimerService._();

  static Timer? _timer;
  static Timer? _tick;
  static SleepTimerMode? _mode;

  static final ValueNotifier<Duration?> remaining = ValueNotifier(null);
  static final ValueNotifier<bool> isActive = ValueNotifier(false);

  static bool get endOfSongMode => _mode == SleepTimerMode.endOfSong;

  // ── Start by duration ──────────────────────────────────────────────────────

  static void startDuration(Duration duration) {
    cancel();
    _mode = SleepTimerMode.duration;
    isActive.value = true;
    remaining.value = duration;

    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final cur = remaining.value;
      if (cur == null || cur <= Duration.zero) {
        _triggerStop();
        return;
      }
      remaining.value = cur - const Duration(seconds: 1);
    });

    _timer = Timer(duration, _triggerStop);
    LogService.log('SleepTimer', 'Dimulai: ${duration.inMinutes} menit');
  }

  // ── Start at end of current song ──────────────────────────────────────────

  static void startEndOfSong() {
    cancel();
    _mode = SleepTimerMode.endOfSong;
    isActive.value = true;
    remaining.value = null;
    LogService.log('SleepTimer', 'Mode akhir lagu aktif');
  }

  // ── Called by AudioService when song ends ─────────────────────────────────

  static void onSongEnded() {
    if (_mode == SleepTimerMode.endOfSong && isActive.value) {
      LogService.log('SleepTimer', 'Lagu selesai — memicu stop');
      _triggerStop();
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static void _triggerStop() {
    final wasActive = isActive.value;
    cancel();
    if (wasActive) {
      try {
        AudioService.pause();
      } catch (_) {}
      LogService.log('SleepTimer', 'Musik dihentikan oleh sleep timer');
    }
  }

  // ── Cancel ────────────────────────────────────────────────────────────────

  static void cancel() {
    _timer?.cancel();
    _tick?.cancel();
    _timer = null;
    _tick = null;
    _mode = null;
    isActive.value = false;
    remaining.value = null;
    LogService.log('SleepTimer', 'Dibatalkan');
  }

  // ── Quick presets ─────────────────────────────────────────────────────────

  static const List<({String label, Duration? duration})> presets = [
    (label: '15 menit',   duration: Duration(minutes: 15)),
    (label: '30 menit',   duration: Duration(minutes: 30)),
    (label: '45 menit',   duration: Duration(minutes: 45)),
    (label: '1 jam',      duration: Duration(hours: 1)),
    (label: '1,5 jam',    duration: Duration(minutes: 90)),
    (label: '2 jam',      duration: Duration(hours: 2)),
    (label: 'Akhir lagu', duration: null),
  ];
}
