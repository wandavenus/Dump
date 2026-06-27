import 'dart:async';

import '../../../models/local_song.dart';
import '../engine_abstraction.dart';
import '../media3/media3_playback_bridge.dart';

/// Engine yang membungkus implementasi Media3/ExoPlayer.
///
/// Seluruh logika DSP, crossfade, antrian, efek, dll. tetap di native Kotlin.
/// Kelas ini meneruskan perintah dan stream ke [Media3PlaybackBridge].
///
/// [Media3PlaybackBridge] adalah satu-satunya kelas yang diizinkan
/// berkomunikasi dengan Android MethodChannel/EventChannel playback.
class Media3Engine implements AbstractAudioEngine {
  bool _initialized = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  /// Menghentikan playback native dan melepas resource.
  ///
  /// Memanggil [Media3PlaybackBridge.stop] untuk mentransisikan ExoPlayer ke
  /// STATE_IDLE, yang memicu [Media3PlaybackService] untuk menghentikan
  /// foreground service dan melepas MediaSession.
  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    try {
      await Media3PlaybackBridge.stop();
    } catch (_) {}
    _initialized = false;
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  @override
  Future<void> play() => Media3PlaybackBridge.play();

  @override
  Future<void> pause() => Media3PlaybackBridge.pause();

  @override
  Future<void> stop() => Media3PlaybackBridge.stop();

  @override
  Future<void> seek(Duration position) => Media3PlaybackBridge.seek(position);

  // ── Queue ─────────────────────────────────────────────────────────────────

  @override
  Future<void> setQueue(List<LocalSong> queue, int index) =>
      Media3PlaybackBridge.setQueue(queue, index);

  @override
  Future<void> skipNext() => Media3PlaybackBridge.skipNext();

  @override
  Future<void> skipPrevious() => Media3PlaybackBridge.skipPrevious();

  @override
  Future<void> setTrack(int index) => Media3PlaybackBridge.setTrack(index);

  // ── Queue mutations ───────────────────────────────────────────────────────

  @override
  Future<void> insertNext(LocalSong song) =>
      Media3PlaybackBridge.insertNext(song);

  @override
  Future<void> appendToQueue(LocalSong song) =>
      Media3PlaybackBridge.appendToQueue(song);

  @override
  Future<void> removeFromQueue(int index) =>
      Media3PlaybackBridge.removeFromQueue(index);

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      Media3PlaybackBridge.reorderQueue(oldIndex, newIndex);

  // ── Mode ──────────────────────────────────────────────────────────────────

  @override
  Future<void> setRepeatMode(String mode) =>
      Media3PlaybackBridge.setRepeatMode(mode);

  @override
  Future<void> setShuffleMode(bool enabled) =>
      Media3PlaybackBridge.setShuffleMode(enabled);

  // ── Playback parameters ───────────────────────────────────────────────────

  @override
  Future<void> setVolume(double volume) =>
      Media3PlaybackBridge.setVolume(volume);

  @override
  Future<void> setSpeed(double speed) => Media3PlaybackBridge.setSpeed(speed);

  @override
  Future<void> setPitch(double pitch) => Media3PlaybackBridge.setPitch(pitch);

  // ── DSP effects ───────────────────────────────────────────────────────────

  @override
  Future<void> setBassBoost(int strength) =>
      Media3PlaybackBridge.setBassBoostStrength(strength);

  @override
  Future<void> setBassBoostEnabled(bool enabled) =>
      Media3PlaybackBridge.setBassBoostEnabled(enabled);

  @override
  Future<void> setVirtualizerEnabled(bool enabled) =>
      Media3PlaybackBridge.setVirtualizerEnabled(enabled);

  @override
  Future<void> setVirtualizerStrength(int strength) =>
      Media3PlaybackBridge.setVirtualizerStrength(strength);

  @override
  Future<void> setReverbPreset(int preset) =>
      Media3PlaybackBridge.setReverbPreset(preset);

  @override
  Future<void> setEqualizerEnabled(bool enabled) =>
      Media3PlaybackBridge.setEqualizerEnabled(enabled);

  @override
  Future<void> setEqualizerBandGain(int band, double gainDb) =>
      Media3PlaybackBridge.setEqualizerBandGain(band, gainDb);

  @override
  Future<void> setLoudnessEnabled(bool enabled) =>
      Media3PlaybackBridge.setLoudnessEnabled(enabled);

  @override
  Future<void> setLoudnessTargetGain(double gainMb) =>
      Media3PlaybackBridge.setLoudnessTargetGain(gainMb);

  @override
  Future<void> setCrossfadeDuration(double seconds) =>
      Media3PlaybackBridge.setCrossfadeDuration(seconds);

  @override
  Future<EngineEqualizerParameters?> getEqualizerParameters() async {
    try {
      final raw = await Media3PlaybackBridge.getEqualizerParameters();
      return EngineEqualizerParameters(
        minDecibels: raw.minDecibels,
        maxDecibels: raw.maxDecibels,
        bandCount:   raw.bands.length,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getEffectSupport() =>
      Media3PlaybackBridge.getEffectSupport();

  // ── Capabilities ─────────────────────────────────────────────────────────

  @override
  Future<void> setSkipSilence(bool enabled) =>
      Media3PlaybackBridge.setSkipSilence(enabled);

  @override
  Future<void> setStereoWidening({
    required bool enabled,
    required double strength,
  }) =>
      Media3PlaybackBridge.setStereoWidening(
        enabled:  enabled,
        strength: strength,
      );

  @override
  Future<Map<String, dynamic>?> getPlaybackStats() =>
      Media3PlaybackBridge.getPlaybackStats();

  // ── Audio format ─────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> getAudioFormat() =>
      Media3PlaybackBridge.getAudioFormat();

  // ── Sleep timer ───────────────────────────────────────────────────────────

  @override
  Future<void> setSleepTimer(int durationMs) =>
      Media3PlaybackBridge.setSleepTimer(durationMs);

  @override
  Future<void> setSleepTimerEndOfSong() =>
      Media3PlaybackBridge.setSleepTimerEndOfSong();

  @override
  Future<void> cancelSleepTimer() => Media3PlaybackBridge.cancelSleepTimer();

  // ── State snapshot ────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> getPlaybackSnapshot() =>
      Media3PlaybackBridge.getPlaybackSnapshot();

  // ── Streams ───────────────────────────────────────────────────────────────

  @override
  Stream<Map<dynamic, dynamic>> get playbackStateStream =>
      Media3PlaybackBridge.playbackStateStream;

  @override
  Stream<Duration> get positionStream => Media3PlaybackBridge.positionStream;

  @override
  Stream<Duration> get durationStream => Media3PlaybackBridge.durationStream;

  @override
  Stream<Map<dynamic, dynamic>?> get currentTrackStream =>
      Media3PlaybackBridge.currentTrackStream;

  @override
  Stream<List<dynamic>> get queueStream => Media3PlaybackBridge.queueStream;

  @override
  Stream<bool> get bufferingStateStream =>
      Media3PlaybackBridge.bufferingStateStream;

  @override
  Stream<bool> get shuffleModeStream => Media3PlaybackBridge.shuffleModeStream;

  @override
  Stream<String> get repeatModeStream => Media3PlaybackBridge.repeatModeStream;

  @override
  Stream<Map<dynamic, dynamic>> get sleepTimerStream =>
      Media3PlaybackBridge.sleepTimerStream;

  @override
  Stream<int> get audioSessionIdStream =>
      Media3PlaybackBridge.audioSessionIdStream;

  @override
  Stream<Map<dynamic, dynamic>> get audioFormatStream =>
      Media3PlaybackBridge.audioFormatStream;

  @override
  Stream<bool> get skipSilenceStream => Media3PlaybackBridge.skipSilenceStream;

  @override
  Stream<Map<dynamic, dynamic>> get stereoWideningStream =>
      Media3PlaybackBridge.stereoWideningStream;

  bool get isInitialized => _initialized;
}
