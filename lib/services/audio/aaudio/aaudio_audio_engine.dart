import 'dart:async';

import '../../../models/local_song.dart';
import '../audio_engine.dart';
import 'aaudio_playback_bridge.dart';

class AAudioAudioEngine implements AudioEngine {
  final _playbackState = StreamController<Map<dynamic, dynamic>>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _currentTrack = StreamController<Map<dynamic, dynamic>?>.broadcast();
  final _queue = StreamController<List<dynamic>>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _shuffle = StreamController<bool>.broadcast();
  final _repeat = StreamController<String>.broadcast();
  final _sleep = StreamController<Map<dynamic, dynamic>>.broadcast();
  final _session = StreamController<int>.broadcast();
  final _format = StreamController<Map<dynamic, dynamic>>.broadcast();
  final _stereo = StreamController<Map<dynamic, dynamic>>.broadcast();

  StreamSubscription<Map<dynamic, dynamic>>? _sub;
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  AudioEngineState _state = AudioEngineState.idle;

  @override
  AudioEngineType get type => AudioEngineType.aaudio;
  @override
  Duration get currentPosition => _currentPosition;
  @override
  Duration get duration => _currentDuration;
  @override
  AudioEngineState get state => _state;
  @override
  Stream<Map<dynamic, dynamic>> get playbackStateStream => _playbackState.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<Map<dynamic, dynamic>?> get currentTrackStream => _currentTrack.stream;
  @override
  Stream<List<dynamic>> get queueStream => _queue.stream;
  @override
  Stream<bool> get bufferingStateStream => _buffering.stream;
  @override
  Stream<bool> get shuffleModeStream => _shuffle.stream;
  @override
  Stream<String> get repeatModeStream => _repeat.stream;
  @override
  Stream<Map<dynamic, dynamic>> get sleepTimerStream => _sleep.stream;
  @override
  Stream<int> get audioSessionIdStream => _session.stream;
  @override
  Stream<Map<dynamic, dynamic>> get audioFormatStream => _format.stream;
  @override
  Stream<Map<dynamic, dynamic>> get stereoWideningStream => _stereo.stream;

  @override
  Future<void> initialize() async {
    await AAudioPlaybackBridge.initialize();
    _sub ??= AAudioPlaybackBridge.events.listen(_handleEvent);
  }

  void _handleEvent(Map<dynamic, dynamic> event) {
    switch (event['type']) {
      case 'state':
        final state = event['state']?.toString() ?? 'idle';
        _state = switch (state) {
          'playing' => AudioEngineState.playing,
          'paused' => AudioEngineState.paused,
          'stopped' => AudioEngineState.stopped,
          'buffering' => AudioEngineState.buffering,
          'error' => AudioEngineState.error,
          _ => AudioEngineState.idle,
        };
        _playbackState.add({'playing': _state == AudioEngineState.playing, 'processingState': state});
      case 'position':
        _currentPosition = AAudioPlaybackBridge.durationFrom(event['position']);
        _position.add(_currentPosition);
      case 'duration':
        _currentDuration = AAudioPlaybackBridge.durationFrom(event['duration']);
        _duration.add(_currentDuration);
      case 'track':
        _currentTrack.add(event['track'] as Map<dynamic, dynamic>?);
      case 'queue':
        _queue.add(event['queue'] as List<dynamic>? ?? const []);
      case 'format':
        _format.add(event);
      case 'buffering':
        _buffering.add(event['buffering'] == true);
    }
  }

  @override
  Future<void> play() => AAudioPlaybackBridge.play();
  @override
  Future<void> pause() => AAudioPlaybackBridge.pause();
  @override
  Future<void> stop() => AAudioPlaybackBridge.stop();
  @override
  Future<void> seek(Duration position) => AAudioPlaybackBridge.seek(position);
  @override
  Future<void> setVolume(double volume) => AAudioPlaybackBridge.setVolume(volume);
  @override
  Future<void> setQueue(List<LocalSong> queue, int index) => AAudioPlaybackBridge.setQueue(queue, index);
  @override
  Future<void> setTrack(int index) => AAudioPlaybackBridge.setTrack(index);
  @override
  Future<void> skipNext() => AAudioPlaybackBridge.skipNext();
  @override
  Future<void> skipPrevious() => AAudioPlaybackBridge.skipPrevious();
  @override
  Future<void> setRepeatMode(String mode) async => _repeat.add(mode);
  @override
  Future<void> setShuffleMode(bool enabled) async => _shuffle.add(enabled);

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await AAudioPlaybackBridge.dispose();
  }
}
