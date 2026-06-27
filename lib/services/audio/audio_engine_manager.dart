import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_song.dart';
import '../log_service.dart';
import 'engine_abstraction.dart';
import 'engines/media3_engine.dart';
import 'engines/media_kit_engine.dart';

/// Mengelola dua engine audio (Media3 & media_kit).
///
/// Hanya SATU engine yang aktif pada satu waktu.
/// AudioService & SleepTimerService hanya berkomunikasi dengan
/// AudioEngineManager — tidak langsung ke Media3PlaybackBridge maupun
/// media_kit Player.
///
/// Perpindahan engine dilakukan dengan [switchEngine], yang:
///   1. Menyimpan state saat ini (queue, index, posisi, shuffle, repeat).
///   2. Mem-pause playback.
///   3. Men-dispose engine lama sepenuhnya.
///   4. Menginisialisasi engine baru.
///   5. Me-restore state.
///   6. Melanjutkan playback jika sebelumnya sedang play.
class AudioEngineManager {
  AudioEngineManager._();

  // ── Singleton state ───────────────────────────────────────────────────────

  static AbstractAudioEngine? _engine;
  static PlaybackEngineType   _engineType = PlaybackEngineType.media3;
  static bool                 _initialized = false;

  static final ValueNotifier<PlaybackEngineType> activeEngineType =
      ValueNotifier(PlaybackEngineType.media3);

  // Notifier untuk UI — muncul saat perpindahan sedang berlangsung.
  static final ValueNotifier<bool> isSwitching = ValueNotifier(false);

  // ── Forwarding StreamControllers ─────────────────────────────────────────
  // AudioService & SleepTimerService subscribe ke stream ini.
  // Saat engine diganti, konten di-forward dari engine baru secara otomatis.

  static final _playbackStateCtrl =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  static final _positionCtrl       = StreamController<Duration>.broadcast();
  static final _durationCtrl       = StreamController<Duration>.broadcast();
  static final _currentTrackCtrl   =
      StreamController<Map<dynamic, dynamic>?>.broadcast();
  static final _queueCtrl          = StreamController<List<dynamic>>.broadcast();
  static final _bufferingCtrl      = StreamController<bool>.broadcast();
  static final _shuffleCtrl        = StreamController<bool>.broadcast();
  static final _repeatCtrl         = StreamController<String>.broadcast();
  static final _sleepTimerCtrl     =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  static final _audioSessionCtrl   = StreamController<int>.broadcast();

  /// Subscriptions ke engine yang sedang aktif.
  static final List<StreamSubscription<dynamic>> _engineSubs = [];

  // ── Public streams (yang digunakan AudioService, SleepTimerService, dll.) ─

  static Stream<Map<dynamic, dynamic>> get playbackStateStream =>
      _playbackStateCtrl.stream;
  static Stream<Duration>              get positionStream =>
      _positionCtrl.stream;
  static Stream<Duration>              get durationStream =>
      _durationCtrl.stream;
  static Stream<Map<dynamic, dynamic>?> get currentTrackStream =>
      _currentTrackCtrl.stream;
  static Stream<List<dynamic>>         get queueStream =>
      _queueCtrl.stream;
  static Stream<bool>                  get bufferingStateStream =>
      _bufferingCtrl.stream;
  static Stream<bool>                  get shuffleModeStream =>
      _shuffleCtrl.stream;
  static Stream<String>                get repeatModeStream =>
      _repeatCtrl.stream;
  static Stream<Map<dynamic, dynamic>> get sleepTimerStream =>
      _sleepTimerCtrl.stream;
  static Stream<int>                   get audioSessionIdStream =>
      _audioSessionCtrl.stream;

  // ── Init ──────────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Inisialisasi media_kit (wajib dipanggil sekali sebelum menggunakan Player)
    if (!kIsWeb) {
      MediaKit.ensureInitialized();
    }

    // Baca pilihan engine terakhir
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('playback_engine') ?? 'media3';
    _engineType = PlaybackEngineType.fromPrefKey(saved);
    activeEngineType.value = _engineType;

    // Buat dan inisialisasi engine
    _engine = _createEngine(_engineType);
    await _engine!.initialize();
    _subscribeToEngine(_engine!);

    LogService.log(
      'AudioEngineManager',
      'Initialized dengan engine: ${_engineType.displayName}',
    );
  }

  // ── Engine switching ──────────────────────────────────────────────────────

  /// Beralih ke engine baru. Menyimpan state, mem-release engine lama,
  /// menginisialisasi engine baru, dan me-restore state.
  static Future<void> switchEngine(PlaybackEngineType newType) async {
    if (_engineType == newType) return;
    if (isSwitching.value) return;

    isSwitching.value = true;
    LogService.log(
      'AudioEngineManager',
      'Beralih: ${_engineType.displayName} → ${newType.displayName}',
    );

    try {
      // 1. Simpan state saat ini
      final snapshot = await _engine?.getPlaybackSnapshot();
      final queue = _extractQueue(snapshot);
      final index = (snapshot?['currentIndex'] as num?)?.toInt() ?? 0;
      final positionMs = (snapshot?['positionMs'] as num?)?.toInt() ?? 0;
      final wasPlaying  = snapshot?['isPlaying'] as bool? ?? false;
      final shuffle     = snapshot?['shuffleEnabled'] as bool? ?? false;
      final repeatMode  = snapshot?['repeatMode'] as String? ?? 'off';

      // 2. Pause & simpan preferensi
      try { await _engine?.pause(); } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playback_engine', newType.prefKey);

      // 3. Release engine lama sepenuhnya
      _cancelEngineSubscriptions();
      try { await _engine?.dispose(); } catch (e) {
        LogService.warn('AudioEngineManager', 'Dispose engine lama: $e');
      }
      _engine = null;

      // 4. Inisialisasi engine baru
      _engineType            = newType;
      activeEngineType.value = newType;
      _engine                = _createEngine(newType);
      await _engine!.initialize();
      _subscribeToEngine(_engine!);

      // 5. Restore state
      if (queue.isNotEmpty) {
        await _engine!.setQueue(queue, index.clamp(0, queue.length - 1));
        await _engine!.setShuffleMode(shuffle);
        await _engine!.setRepeatMode(repeatMode);

        if (positionMs > 0) {
          await _engine!.seek(Duration(milliseconds: positionMs));
        }

        // 6. Resume jika sebelumnya sedang play
        if (wasPlaying) await _engine!.play();
      }

      LogService.log(
        'AudioEngineManager',
        'Perpindahan selesai → ${newType.displayName}',
      );
    } catch (e, st) {
      LogService.error(
        'AudioEngineManager',
        'switchEngine gagal: $e',
        stackTrace: st.toString(),
      );
    } finally {
      isSwitching.value = false;
    }
  }

  // ── Forwarded commands (digunakan AudioService) ───────────────────────────

  static Future<void> play()          => _engine?.play()          ?? Future.value();
  static Future<void> pause()         => _engine?.pause()         ?? Future.value();
  static Future<void> stop()          => _engine?.stop()          ?? Future.value();
  static Future<void> seek(Duration p) => _engine?.seek(p)        ?? Future.value();
  static Future<void> skipNext()      => _engine?.skipNext()      ?? Future.value();
  static Future<void> skipPrevious()  => _engine?.skipPrevious()  ?? Future.value();
  static Future<void> setTrack(int i) => _engine?.setTrack(i)     ?? Future.value();
  static Future<void> setRepeatMode(String m) =>
      _engine?.setRepeatMode(m) ?? Future.value();
  static Future<void> setShuffleMode(bool e) =>
      _engine?.setShuffleMode(e) ?? Future.value();
  static Future<void> setVolume(double v) =>
      _engine?.setVolume(v) ?? Future.value();
  static Future<void> setSpeed(double v) =>
      _engine?.setSpeed(v) ?? Future.value();
  static Future<void> setPitch(double v) =>
      _engine?.setPitch(v) ?? Future.value();

  static Future<void> setQueue(List<LocalSong> q, int i) =>
      _engine?.setQueue(q, i) ?? Future.value();
  static Future<void> insertNext(LocalSong s) =>
      _engine?.insertNext(s) ?? Future.value();
  static Future<void> appendToQueue(LocalSong s) =>
      _engine?.appendToQueue(s) ?? Future.value();
  static Future<void> removeFromQueue(int i) =>
      _engine?.removeFromQueue(i) ?? Future.value();
  static Future<void> reorderQueue(int o, int n) =>
      _engine?.reorderQueue(o, n) ?? Future.value();

  static Future<void> setSleepTimer(int ms) =>
      _engine?.setSleepTimer(ms) ?? Future.value();
  static Future<void> setSleepTimerEndOfSong() =>
      _engine?.setSleepTimerEndOfSong() ?? Future.value();
  static Future<void> cancelSleepTimer() =>
      _engine?.cancelSleepTimer() ?? Future.value();

  static Future<Map<String, dynamic>?> getPlaybackSnapshot() =>
      _engine?.getPlaybackSnapshot() ?? Future.value(null);

  // ── Current engine type ───────────────────────────────────────────────────

  static PlaybackEngineType get engineType => _engineType;

  static bool get isMedia3Active => _engineType == PlaybackEngineType.media3;
  static bool get isMediaKitActive => _engineType == PlaybackEngineType.mediaKit;

  // ── Private helpers ───────────────────────────────────────────────────────

  static AbstractAudioEngine _createEngine(PlaybackEngineType type) =>
      switch (type) {
        PlaybackEngineType.media3   => Media3Engine(),
        PlaybackEngineType.mediaKit => MediaKitEngine(),
      };

  static void _subscribeToEngine(AbstractAudioEngine engine) {
    _cancelEngineSubscriptions();

    _engineSubs.addAll([
      engine.playbackStateStream.listen(_playbackStateCtrl.add),
      engine.positionStream.listen(_positionCtrl.add),
      engine.durationStream.listen(_durationCtrl.add),
      engine.currentTrackStream.listen(_currentTrackCtrl.add),
      engine.queueStream.listen(_queueCtrl.add),
      engine.bufferingStateStream.listen(_bufferingCtrl.add),
      engine.shuffleModeStream.listen(_shuffleCtrl.add),
      engine.repeatModeStream.listen(_repeatCtrl.add),
      engine.sleepTimerStream.listen(_sleepTimerCtrl.add),
      engine.audioSessionIdStream.listen(_audioSessionCtrl.add),
    ]);
  }

  static void _cancelEngineSubscriptions() {
    for (final s in _engineSubs) {
      s.cancel();
    }
    _engineSubs.clear();
  }

  static List<LocalSong> _extractQueue(Map<String, dynamic>? snapshot) {
    try {
      final raw = snapshot?['queue'];
      if (raw == null || raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((m) => LocalSong.fromMap(m.cast<dynamic, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
