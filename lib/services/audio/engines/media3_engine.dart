import 'dart:async';

import '../../../models/local_song.dart';
import '../engine_abstraction.dart';
import '../media3/media3_playback_bridge.dart';

/// Engine yang membungkus implementasi Media3/ExoPlayer yang sudah ada.
/// Seluruh logika DSP, crossfade, antrian, dll. tetap di native Kotlin.
/// Kelas ini hanya meneruskan perintah dan stream ke Media3PlaybackBridge.
class Media3Engine implements AbstractAudioEngine {
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> dispose() async {
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

  // ── Parameters ────────────────────────────────────────────────────────────

  @override
  Future<void> setVolume(double volume) =>
      Media3PlaybackBridge.setVolume(volume);

  @override
  Future<void> setSpeed(double speed) =>
      Media3PlaybackBridge.setSpeed(speed);

  @override
  Future<void> setPitch(double pitch) =>
      Media3PlaybackBridge.setPitch(pitch);

  // ── Sleep timer ───────────────────────────────────────────────────────────

  @override
  Future<void> setSleepTimer(int durationMs) =>
      Media3PlaybackBridge.setSleepTimer(durationMs);

  @override
  Future<void> setSleepTimerEndOfSong() =>
      Media3PlaybackBridge.setSleepTimerEndOfSong();

  @override
  Future<void> cancelSleepTimer() =>
      Media3PlaybackBridge.cancelSleepTimer();

  // ── State snapshot ────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> getPlaybackSnapshot() =>
      Media3PlaybackBridge.getPlaybackSnapshot();

  // ── Streams ───────────────────────────────────────────────────────────────

  @override
  Stream<Map<dynamic, dynamic>> get playbackStateStream =>
      Media3PlaybackBridge.playbackStateStream;

  @override
  Stream<Duration> get positionStream =>
      Media3PlaybackBridge.positionStream;

  @override
  Stream<Duration> get durationStream =>
      Media3PlaybackBridge.durationStream;

  @override
  Stream<Map<dynamic, dynamic>?> get currentTrackStream =>
      Media3PlaybackBridge.currentTrackStream;

  @override
  Stream<List<dynamic>> get queueStream =>
      Media3PlaybackBridge.queueStream;

  @override
  Stream<bool> get bufferingStateStream =>
      Media3PlaybackBridge.bufferingStateStream;

  @override
  Stream<bool> get shuffleModeStream =>
      Media3PlaybackBridge.shuffleModeStream;

  @override
  Stream<String> get repeatModeStream =>
      Media3PlaybackBridge.repeatModeStream;

  @override
  Stream<Map<dynamic, dynamic>> get sleepTimerStream =>
      Media3PlaybackBridge.sleepTimerStream;

  @override
  Stream<int> get audioSessionIdStream =>
      Media3PlaybackBridge.audioSessionIdStream;

  bool get isInitialized => _initialized;
}
