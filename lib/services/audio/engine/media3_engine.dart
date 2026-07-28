import '../../../models/local_song.dart';
import '../media3/media3_playback_bridge.dart';
import 'abstract_audio_engine.dart';
import 'playback_engine_type.dart';

class Media3Engine implements AbstractAudioEngine {
  @override
  PlaybackEngineType get type => PlaybackEngineType.media3;
  @override
  Stream<Map<dynamic, dynamic>> get playbackStateStream => Media3PlaybackBridge.playbackStateStream;
  @override
  Stream<Duration> get positionStream => Media3PlaybackBridge.positionStream;
  @override
  Stream<Duration> get durationStream => Media3PlaybackBridge.durationStream;
  @override
  Stream<Map<dynamic, dynamic>?> get currentTrackStream => Media3PlaybackBridge.currentTrackStream;
  @override
  Stream<List<dynamic>> get queueStream => Media3PlaybackBridge.queueStream;
  @override
  Stream<bool> get bufferingStateStream => Media3PlaybackBridge.bufferingStateStream;
  @override
  Stream<bool> get shuffleModeStream => Media3PlaybackBridge.shuffleModeStream;
  @override
  Stream<String> get repeatModeStream => Media3PlaybackBridge.repeatModeStream;
  @override
  Stream<Map<dynamic, dynamic>> get sleepTimerStream => Media3PlaybackBridge.sleepTimerStream;
  @override
  Stream<int> get audioSessionIdStream => Media3PlaybackBridge.audioSessionIdStream;
  @override
  Stream<Map<dynamic, dynamic>> get audioFormatStream => Media3PlaybackBridge.audioFormatStream;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> play() => Media3PlaybackBridge.play();
  @override
  Future<void> pause() => Media3PlaybackBridge.pause();
  @override
  Future<void> stop() => Media3PlaybackBridge.stop();
  @override
  Future<void> release() => Media3PlaybackBridge.release();
  @override
  Future<void> seek(Duration p) => Media3PlaybackBridge.seek(p);
  @override
  Future<void> skipNext() => Media3PlaybackBridge.skipNext();
  @override
  Future<void> skipPrevious() => Media3PlaybackBridge.skipPrevious();
  @override
  Future<void> setTrack(int i) => Media3PlaybackBridge.setTrack(i);
  @override
  Future<void> setQueue(List<LocalSong> q, int i) => Media3PlaybackBridge.setQueue(q, i);
  @override
  Future<void> insertNext(LocalSong s) => Media3PlaybackBridge.insertNext(s);
  @override
  Future<void> appendToQueue(LocalSong s) => Media3PlaybackBridge.appendToQueue(s);
  @override
  Future<void> removeFromQueue(int i) => Media3PlaybackBridge.removeFromQueue(i);
  @override
  Future<void> reorderQueue(int o, int n) => Media3PlaybackBridge.reorderQueue(o, n);
  @override
  Future<void> setVolume(double v) => Media3PlaybackBridge.setVolume(v);
  @override
  Future<void> setSpeed(double v) => Media3PlaybackBridge.setSpeed(v);
  @override
  Future<void> setPitch(double v) => Media3PlaybackBridge.setPitch(v);
  @override
  Future<void> setRepeatMode(String m) => Media3PlaybackBridge.setRepeatMode(m);
  @override
  Future<void> setShuffleMode(bool e) => Media3PlaybackBridge.setShuffleMode(e);
  @override
  Future<void> setSleepTimer(int ms) => Media3PlaybackBridge.setSleepTimer(ms);
  @override
  Future<void> setSleepTimerEndOfSong() => Media3PlaybackBridge.setSleepTimerEndOfSong();
  @override
  Future<void> cancelSleepTimer() => Media3PlaybackBridge.cancelSleepTimer();
  @override
  Future<Map<String, dynamic>?> getPlaybackSnapshot() => Media3PlaybackBridge.getPlaybackSnapshot();

  @override
  Future<void> restoreSnapshot(Map<String, dynamic> s) async {
    final rawQueue = s['queue'] as List<dynamic>? ?? const [];
    final queue = rawQueue.whereType<Map<dynamic, dynamic>>().map(LocalSong.fromMap).toList();
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
