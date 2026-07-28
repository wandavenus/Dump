import '../../../models/local_song.dart';
import 'playback_engine_type.dart';

abstract interface class AbstractAudioEngine {
  PlaybackEngineType get type;

  Stream<Map<dynamic, dynamic>> get playbackStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<Map<dynamic, dynamic>?> get currentTrackStream;
  Stream<List<dynamic>> get queueStream;
  Stream<bool> get bufferingStateStream;
  Stream<bool> get shuffleModeStream;
  Stream<String> get repeatModeStream;
  Stream<Map<dynamic, dynamic>> get sleepTimerStream;
  Stream<int> get audioSessionIdStream;
  Stream<Map<dynamic, dynamic>> get audioFormatStream;

  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> release();
  Future<void> seek(Duration position);
  Future<void> skipNext();
  Future<void> skipPrevious();
  Future<void> setTrack(int index);
  Future<void> setQueue(List<LocalSong> queue, int index);
  Future<void> insertNext(LocalSong song);
  Future<void> appendToQueue(LocalSong song);
  Future<void> removeFromQueue(int index);
  Future<void> reorderQueue(int oldIndex, int newIndex);
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> setPitch(double pitch);
  Future<void> setRepeatMode(String mode);
  Future<void> setShuffleMode(bool enabled);
  Future<void> setSleepTimer(int durationMs);
  Future<void> setSleepTimerEndOfSong();
  Future<void> cancelSleepTimer();
  Future<Map<String, dynamic>?> getPlaybackSnapshot();
  Future<void> restoreSnapshot(Map<String, dynamic> snapshot);
}
