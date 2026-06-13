import 'package:flutter/foundation.dart';
import 'audio_service.dart';
import 'log_service.dart';

/// Mengelola audio focus – pause saat interupsi, resume saat fokus kembali.
/// Pada web: dikelola oleh browser. Pada native: bisa diperluas pakai audio_session.
class AudioFocusService {
  AudioFocusService._();

  static bool _initialized = false;
  static bool _pausedByFocus = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    AudioService.player.playerStateStream.listen((state) {
      LogService.log(
        'AudioFocus',
        'ProcessingState: ${state.processingState}, playing: ${state.playing}',
      );
    });

    if (!kIsWeb) {
      _listenNativeFocus();
    }

    LogService.log('AudioFocus', 'Initialized');
  }

  static void _listenNativeFocus() {
    // Placeholder untuk native audio_session integration
    // Implementasi penuh perlu package: audio_session
  }

  /// Dipanggil ketika fokus audio hilang (misalnya notifikasi, panggilan).
  static void onFocusLoss({bool transient = false}) {
    if (AudioService.isPlaying) {
      _pausedByFocus = true;
      AudioService.pause();
      LogService.log('AudioFocus', 'Focus lost (transient: $transient) – paused');
    }
  }

  /// Dipanggil ketika fokus audio kembali.
  static void onFocusGain() {
    if (_pausedByFocus) {
      _pausedByFocus = false;
      AudioService.play();
      LogService.log('AudioFocus', 'Focus gained – resumed');
    }
  }

  static void onFocusDuck() {
    try {
      AudioService.player.setVolume(0.3);
      LogService.log('AudioFocus', 'Ducked volume');
    } catch (_) {}
  }

  static void onFocusUnduck() {
    try {
      AudioService.player.setVolume(1.0);
      LogService.log('AudioFocus', 'Restored volume');
    } catch (_) {}
  }
}
