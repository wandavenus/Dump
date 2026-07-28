import '../../../models/local_song.dart';
import '../aaudio/aaudio_playback_bridge.dart';
import 'abstract_audio_engine.dart';
import 'playback_engine_type.dart';

class AAudioEngine implements AbstractAudioEngine {
  @override
  PlaybackEngineType get type => PlaybackEngineType.aaudio;
  @override
  Stream<Map<dynamic, dynamic>> get playbackStateStream => AAudioPlaybackBridge.playbackStateStream;
  @override
  Stream<Duration> get positionStream => AAudioPlaybackBridge.positionStream;
  @override
  Stream<Duration> get durationStream => AAudioPlaybackBridge.durationStream;
  @override
  Stream<Map<dynamic, dynamic>?> get currentTrackStream => AAudioPlaybackBridge.currentTrackStream;
  @override
  Stream<List<dynamic>> get queueStream => AAudioPlaybackBridge.queueStream;
  @override
  Stream<bool> get bufferingStateStream => AAudioPlaybackBridge.bufferingStateStream;
  @override
  Stream<bool> get shuffleModeStream => AAudioPlaybackBridge.shuffleModeStream;
  @override
  Stream<String> get repeatModeStream => AAudioPlaybackBridge.repeatModeStream;
  @override
  Stream<Map<dynamic, dynamic>> get sleepTimerStream => AAudioPlaybackBridge.sleepTimerStream;
  @override
  Stream<int> get audioSessionIdStream => AAudioPlaybackBridge.audioSessionIdStream;
  @override
  Stream<Map<dynamic, dynamic>> get audioFormatStream => AAudioPlaybackBridge.audioFormatStream;
  @override
  Future<void> initialize() => AAudioPlaybackBridge.initialize();
  @override
  Future<void> play() => AAudioPlaybackBridge.play();
  @override
  Future<void> pause() => AAudioPlaybackBridge.pause();
  @override
  Future<void> stop() => AAudioPlaybackBridge.stop();
  @override
  Future<void> release() => AAudioPlaybackBridge.release();
  @override
  Future<void> seek(Duration p) => AAudioPlaybackBridge.seek(p);
  @override
  Future<void> skipNext() => AAudioPlaybackBridge.skipNext();
  @override
  Future<void> skipPrevious() => AAudioPlaybackBridge.skipPrevious();
  @override
  Future<void> setTrack(int i) => AAudioPlaybackBridge.setTrack(i);
  @override
  Future<void> setQueue(List<LocalSong> q, int i) => AAudioPlaybackBridge.setQueue(q, i);
  @override
  Future<void> insertNext(LocalSong s) => AAudioPlaybackBridge.insertNext(s);
  @override
  Future<void> appendToQueue(LocalSong s) => AAudioPlaybackBridge.appendToQueue(s);
  @override
  Future<void> removeFromQueue(int i) => AAudioPlaybackBridge.removeFromQueue(i);
  @override
  Future<void> reorderQueue(int o, int n) => AAudioPlaybackBridge.reorderQueue(o, n);
  @override
  Future<void> setVolume(double v) => AAudioPlaybackBridge.setVolume(v);
  @override
  Future<void> setSpeed(double v) => AAudioPlaybackBridge.setSpeed(v);
  @override
  Future<void> setPitch(double v) => AAudioPlaybackBridge.setPitch(v);
  @override
  Future<void> setRepeatMode(String m) => AAudioPlaybackBridge.setRepeatMode(m);
  @override
  Future<void> setShuffleMode(bool e) => AAudioPlaybackBridge.setShuffleMode(e);
  @override
  Future<void> setSleepTimer(int ms) => AAudioPlaybackBridge.setSleepTimer(ms);
  @override
  Future<void> setSleepTimerEndOfSong() => AAudioPlaybackBridge.setSleepTimerEndOfSong();
  @override
  Future<void> cancelSleepTimer() => AAudioPlaybackBridge.cancelSleepTimer();
  @override
  Future<Map<String, dynamic>?> getPlaybackSnapshot() => AAudioPlaybackBridge.getPlaybackSnapshot();

  @override
  Future<void> restoreSnapshot(Map<String, dynamic> s) async {
    final queue = (s['queue'] as List<dynamic>? ?? const [])
        .whereType<Map<dynamic, dynamic>>().map(LocalSong.fromMap).toList();
    final index = (s['currentIndex'] as num?)?.toInt() ?? 0;
    if (queue.isNotEmpty) await setQueue(queue, index.clamp(0, queue.length - 1));
    await setRepeatMode(s['repeatMode'] as String? ?? 'off');
    await setShuffleMode(s['shuffleEnabled'] as bool? ?? false);
    await setVolume((s['volume'] as num?)?.toDouble() ?? 1.0);
    await setSpeed((s['speed'] as num?)?.toDouble() ?? 1.0);
    await setPitch((s['pitch'] as num?)?.toDouble() ?? 1.0);
    await seek(Duration(milliseconds: (s['positionMs'] as num?)?.toInt() ?? 0));
    if (s['isPlaying'] == true) await play();
  }
}
