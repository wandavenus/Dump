import '../../../models/local_song.dart';
import '../audio_engine.dart';
import 'media3_playback_bridge.dart';

class Media3AudioEngine implements AudioEngine {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  AudioEngineState _state = AudioEngineState.idle;

  @override
  AudioEngineType get type => AudioEngineType.media3;
  @override
  Stream<Map<dynamic, dynamic>> get playbackStateStream =>
      Media3PlaybackBridge.playbackStateStream.map((event) {
        final playing = event['playing'] == true;
        final processing = event['processingState']?.toString();
        _state = playing
            ? AudioEngineState.playing
            : switch (processing) {
                'buffering' => AudioEngineState.buffering,
                'ready' => AudioEngineState.paused,
                'idle' => AudioEngineState.idle,
                _ => _state,
              };
        return event;
      });
  @override
  Stream<Duration> get positionStream => Media3PlaybackBridge.positionStream.map((v) => _position = v);
  @override
  Stream<Duration> get durationStream => Media3PlaybackBridge.durationStream.map((v) => _duration = v);
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
  Stream<Map<dynamic, dynamic>> get stereoWideningStream => Media3PlaybackBridge.stereoWideningStream;
  @override
  Duration get currentPosition => _position;
  @override
  Duration get duration => _duration;
  @override
  AudioEngineState get state => _state;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> play() => Media3PlaybackBridge.play();
  @override
  Future<void> pause() => Media3PlaybackBridge.pause();
  @override
  Future<void> stop() => Media3PlaybackBridge.stop();
  @override
  Future<void> seek(Duration position) => Media3PlaybackBridge.seek(position);
  @override
  Future<void> setVolume(double volume) => Media3PlaybackBridge.setVolume(volume);
  @override
  Future<void> dispose() => Media3PlaybackBridge.release();
  @override
  Future<void> skipNext() => Media3PlaybackBridge.skipNext();
  @override
  Future<void> skipPrevious() => Media3PlaybackBridge.skipPrevious();
  @override
  Future<void> setTrack(int index) => Media3PlaybackBridge.setTrack(index);
  @override
  Future<void> setQueue(List<LocalSong> queue, int index) => Media3PlaybackBridge.setQueue(queue, index);
  @override
  Future<void> setRepeatMode(String mode) => Media3PlaybackBridge.setRepeatMode(mode);
  @override
  Future<void> setShuffleMode(bool enabled) => Media3PlaybackBridge.setShuffleMode(enabled);
}
