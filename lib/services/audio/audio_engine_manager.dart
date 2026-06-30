// ignore_for_file: close_sinks

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_song.dart';
import '../log_service.dart';
import 'engine_abstraction.dart';
import 'engines/media3_engine.dart';
import 'engines/media_kit_engine.dart';

/// Central manager untuk Hybrid Audio Engine.
///
/// Hanya SATU engine yang aktif pada satu waktu.
/// Seluruh layer di atas (AudioService, AudioEffectsService,
/// MediaCapabilitiesService, UI) hanya berkomunikasi dengan
/// [AudioEngineManager] — tidak langsung ke [Media3PlaybackBridge]
/// maupun media_kit [Player].
///
/// Perpindahan engine via [switchEngine]:
///   1. Simpan state (queue, index, posisi, shuffle, repeat).
///   2. Pause engine lama.
///   3. Dispose engine lama sepenuhnya (stop native service untuk Media3).
///   4. Inisialisasi engine baru.
///   5. Restore state.
///   6. Resume playback jika sebelumnya sedang play.
class AudioEngineManager {
  AudioEngineManager._();

  // ── Singleton state ───────────────────────────────────────────────────────

  static AbstractAudioEngine? _engine;
  static PlaybackEngineType _engineType = PlaybackEngineType.media3;
  static bool _initialized = false;

  static final ValueNotifier<PlaybackEngineType> activeEngineType =
      ValueNotifier(PlaybackEngineType.media3);

  static final ValueNotifier<bool> isSwitching = ValueNotifier(false);

  /// Callback yang dipanggil setelah setiap engine switch selesai
  /// (setelah state di-restore). Diregistrasi oleh AudioEffectsService
  /// untuk me-re-apply pengaturan DSP ke engine baru.
  ///
  /// Pola callback dipakai (bukan import langsung) untuk menghindari
  /// circular dependency: AudioEffectsService → AudioEngineManager.
  static VoidCallback? _postSwitchCallback;

  /// Registrasi callback yang dipanggil setelah setiap engine switch.
  /// Dipanggil sekali oleh AudioEffectsService.init().
  static void registerPostSwitchCallback(VoidCallback callback) {
    _postSwitchCallback = callback;
  }

  // ── Forwarding StreamControllers ──────────────────────────────────────────
  // Semua consumer (AudioService, MediaCapabilitiesService, dll.) subscribe
  // ke stream-stream ini — bukan langsung ke engine. Saat engine diganti,
  // _subscribeToEngine() menghubungkan source baru ke controller yang sama.

  static final _playbackStateCtrl =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  static final _positionCtrl = StreamController<Duration>.broadcast();
  static final _durationCtrl = StreamController<Duration>.broadcast();
  static final _currentTrackCtrl =
      StreamController<Map<dynamic, dynamic>?>.broadcast();
  static final _queueCtrl = StreamController<List<dynamic>>.broadcast();
  static final _bufferingCtrl = StreamController<bool>.broadcast();
  static final _shuffleCtrl = StreamController<bool>.broadcast();
  static final _repeatCtrl = StreamController<String>.broadcast();
  static final _sleepTimerCtrl =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  static final _audioSessionCtrl = StreamController<int>.broadcast();
  static final _audioFormatCtrl =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  static final _skipSilenceCtrl = StreamController<bool>.broadcast();
  static final _stereoWideningCtrl =
      StreamController<Map<dynamic, dynamic>>.broadcast();

  static final List<StreamSubscription<dynamic>> _engineSubs = [];

  // ── Public streams ────────────────────────────────────────────────────────

  static Stream<Map<dynamic, dynamic>> get playbackStateStream =>
      _playbackStateCtrl.stream;
  static Stream<Duration> get positionStream => _positionCtrl.stream;
  static Stream<Duration> get durationStream => _durationCtrl.stream;
  static Stream<Map<dynamic, dynamic>?> get currentTrackStream =>
      _currentTrackCtrl.stream;
  static Stream<List<dynamic>> get queueStream => _queueCtrl.stream;
  static Stream<bool> get bufferingStateStream => _bufferingCtrl.stream;
  static Stream<bool> get shuffleModeStream => _shuffleCtrl.stream;
  static Stream<String> get repeatModeStream => _repeatCtrl.stream;
  static Stream<Map<dynamic, dynamic>> get sleepTimerStream =>
      _sleepTimerCtrl.stream;
  static Stream<int> get audioSessionIdStream => _audioSessionCtrl.stream;
  static Stream<Map<dynamic, dynamic>> get audioFormatStream =>
      _audioFormatCtrl.stream;
  static Stream<bool> get skipSilenceStream => _skipSilenceCtrl.stream;
  static Stream<Map<dynamic, dynamic>> get stereoWideningStream =>
      _stereoWideningCtrl.stream;

  // ── Init ──────────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!kIsWeb) {
      MediaKit.ensureInitialized();
    }

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('playback_engine') ?? 'media3';
    _engineType = PlaybackEngineType.fromPrefKey(saved);
    activeEngineType.value = _engineType;

    _engine = _createEngine(_engineType);
    await _engine!.initialize();
    _subscribeToEngine(_engine!);

    LogService.log(
      'AudioEngineManager',
      'Initialized — engine: ${_engineType.displayName}',
    );
  }

  // ── Engine switching ──────────────────────────────────────────────────────

  /// Beralih ke [newType]. Semua state dipreservasi secara atomik.
  static Future<void> switchEngine(PlaybackEngineType newType) async {
    if (_engineType == newType) return;
    if (isSwitching.value) return;

    // Set flag SEBELUM await pertama untuk mencegah concurrent switch.
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
      final wasPlaying = snapshot?['isPlaying'] as bool? ?? false;
      final shuffle = snapshot?['shuffleEnabled'] as bool? ?? false;
      final repeatMode = snapshot?['repeatMode'] as String? ?? 'off';

      // 2. Pause engine lama
      try {
        await _engine?.pause();
      } catch (_) {}

      // 3. Simpan preferensi
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playback_engine', newType.prefKey);

      // 4. Dispose engine lama (Media3Engine.dispose() menghentikan Android service)
      _cancelEngineSubscriptions();
      try {
        await _engine?.dispose();
      } catch (e) {
        LogService.warn('AudioEngineManager', 'Dispose engine lama: $e');
      }
      _engine = null;

      // 5. Inisialisasi engine baru
      _engineType = newType;
      activeEngineType.value = newType;
      _engine = _createEngine(newType);
      await _engine!.initialize();
      _subscribeToEngine(_engine!);

      // 6. Restore state
      if (queue.isNotEmpty) {
        await _engine!.setQueue(queue, index.clamp(0, queue.length - 1));
        await _engine!.setShuffleMode(shuffle);
        await _engine!.setRepeatMode(repeatMode);

        if (positionMs > 0) {
          await _engine!.seek(Duration(milliseconds: positionMs));
        }

        if (wasPlaying) await _engine!.play();
      }

      // 7. Re-apply semua pengaturan DSP (speed, pitch, EQ, bass, reverb, dll.)
      // ke engine baru. Pengaturan ini tidak tersimpan di engine — hanya di
      // AudioEffectsService — sehingga harus dikirim ulang setelah setiap switch.
      // Dipanggil di luar blok queue agar selalu berjalan, bahkan saat queue kosong.
      _postSwitchCallback?.call();

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

  // ── Transport ─────────────────────────────────────────────────────────────

  static Future<void> play() => _engine?.play() ?? Future.value();
  static Future<void> pause() => _engine?.pause() ?? Future.value();
  static Future<void> stop() => _engine?.stop() ?? Future.value();
  static Future<void> seek(Duration p) => _engine?.seek(p) ?? Future.value();
  static Future<void> skipNext() => _engine?.skipNext() ?? Future.value();
  static Future<void> skipPrevious() =>
      _engine?.skipPrevious() ?? Future.value();
  static Future<void> setTrack(int i) => _engine?.setTrack(i) ?? Future.value();

  // ── Mode ──────────────────────────────────────────────────────────────────

  static Future<void> setRepeatMode(String m) =>
      _engine?.setRepeatMode(m) ?? Future.value();
  static Future<void> setShuffleMode(bool e) =>
      _engine?.setShuffleMode(e) ?? Future.value();

  // ── Playback parameters ───────────────────────────────────────────────────

  static Future<void> setVolume(double v) =>
      _engine?.setVolume(v) ?? Future.value();
  static Future<void> setSpeed(double v) =>
      _engine?.setSpeed(v) ?? Future.value();
  static Future<void> setPitch(double v) =>
      _engine?.setPitch(v) ?? Future.value();

  // ── Queue mutations ───────────────────────────────────────────────────────

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

  // ── DSP effects ───────────────────────────────────────────────────────────

  static Future<void> setBassBoost(int strength) =>
      _engine?.setBassBoost(strength) ?? Future.value();
  static Future<void> setBassBoostEnabled(bool e) =>
      _engine?.setBassBoostEnabled(e) ?? Future.value();
  static Future<void> setVirtualizerEnabled(bool e) =>
      _engine?.setVirtualizerEnabled(e) ?? Future.value();
  static Future<void> setVirtualizerStrength(int s) =>
      _engine?.setVirtualizerStrength(s) ?? Future.value();
  static Future<void> setReverbPreset(int p) =>
      _engine?.setReverbPreset(p) ?? Future.value();
  static Future<void> setEqualizerEnabled(bool e) =>
      _engine?.setEqualizerEnabled(e) ?? Future.value();
  static Future<void> setEqualizerBandGain(int b, double g) =>
      _engine?.setEqualizerBandGain(b, g) ?? Future.value();
  static Future<void> setLoudnessEnabled(bool e) =>
      _engine?.setLoudnessEnabled(e) ?? Future.value();
  static Future<void> setLoudnessTargetGain(double g) =>
      _engine?.setLoudnessTargetGain(g) ?? Future.value();
  static Future<void> setCrossfadeDuration(double s) =>
      _engine?.setCrossfadeDuration(s) ?? Future.value();

  static Future<EngineEqualizerParameters?> getEqualizerParameters() =>
      _engine?.getEqualizerParameters() ?? Future.value(null);

  static Future<Map<String, dynamic>?> getEffectSupport() =>
      _engine?.getEffectSupport() ?? Future.value(null);

  // ── Capabilities ─────────────────────────────────────────────────────────

  static Future<void> setSkipSilence(bool e) =>
      _engine?.setSkipSilence(e) ?? Future.value();

  static Future<void> setStereoWidening({
    required bool enabled,
    required double strength,
  }) =>
      _engine?.setStereoWidening(enabled: enabled, strength: strength) ??
      Future.value();

  static Future<Map<String, dynamic>?> getPlaybackStats() =>
      _engine?.getPlaybackStats() ?? Future.value(null);

  // ── Audio format ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getAudioFormat() =>
      _engine?.getAudioFormat() ?? Future.value(null);

  // ── Sleep timer ───────────────────────────────────────────────────────────

  static Future<void> setSleepTimer(int ms) =>
      _engine?.setSleepTimer(ms) ?? Future.value();
  static Future<void> setSleepTimerEndOfSong() =>
      _engine?.setSleepTimerEndOfSong() ?? Future.value();
  static Future<void> cancelSleepTimer() =>
      _engine?.cancelSleepTimer() ?? Future.value();

  // ── State snapshot ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getPlaybackSnapshot() =>
      _engine?.getPlaybackSnapshot() ?? Future.value(null);

  // ── Engine info ───────────────────────────────────────────────────────────

  static PlaybackEngineType get engineType => _engineType;
  static bool get isMedia3Active => _engineType == PlaybackEngineType.media3;
  static bool get isMediaKitActive =>
      _engineType == PlaybackEngineType.mediaKit;

  // ── Private helpers ───────────────────────────────────────────────────────

  static AbstractAudioEngine _createEngine(PlaybackEngineType type) =>
      switch (type) {
        PlaybackEngineType.media3 => Media3Engine(),
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
      engine.audioFormatStream.listen(_audioFormatCtrl.add),
      engine.skipSilenceStream.listen(_skipSilenceCtrl.add),
      engine.stereoWideningStream.listen(_stereoWideningCtrl.add),
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
