import 'dart:async';

import '../../../models/local_song.dart';
import 'media3_playback_bridge.dart';

/// Minimal player API used by the existing Flutter UI, now backed by native
/// Android Media3 instead of legacy Dart player plugins.
enum ProcessingState { idle, loading, buffering, ready, completed }

enum LoopMode { off, all, one }

class PlayerState {
  final bool playing;
  final ProcessingState processingState;

  const PlayerState(this.playing, this.processingState);
}

class AudioSource {
  final LocalSong song;
  const AudioSource(this.song);
}

class AudioPlayer {
  AudioPlayer({Object? audioPipeline}) {
    _stateSub = Media3PlaybackBridge.playbackStateStream.listen((event) {
      _playing = event['playing'] == true;
      _processingState = _parseProcessingState(event['processingState']);
      _playerStateController.add(PlayerState(_playing, _processingState));
    });
    _positionSub = Media3PlaybackBridge.positionStream.listen((value) {
      _position = value;
      _positionController.add(value);
    });
    _durationSub = Media3PlaybackBridge.durationStream.listen((value) {
      _duration = value;
      _durationController.add(value);
    });
    _sessionSub = Media3PlaybackBridge.audioSessionIdStream.listen(_sessionController.add);
  }

  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _sessionController = StreamController<int?>.broadcast();

  StreamSubscription<Map<dynamic, dynamic>>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<int>? _sessionSub;

  bool _playing = false;
  ProcessingState _processingState = ProcessingState.idle;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _volume = 1.0;
  double _speed = 1.0;
  double _pitch = 1.0;

  bool get playing => _playing;
  ProcessingState get processingState => _processingState;
  Duration get position => _position;
  Duration? get duration => _duration;
  double get speed => _speed;
  double get volume => _volume;
  double get pitch => _pitch;

  Stream<PlayerState> get playerStateStream => _playerStateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<int?> get androidAudioSessionIdStream => _sessionController.stream;

  Future<void> setAudioSource(AudioSource source) => setQueue([source.song], 0);

  Future<void> setQueue(List<LocalSong> queue, int index) async {
    _processingState = ProcessingState.loading;
    _playerStateController.add(PlayerState(_playing, _processingState));
    await Media3PlaybackBridge.setQueue(queue, index);
  }

  Future<void> play() => Media3PlaybackBridge.play();
  Future<void> pause() => Media3PlaybackBridge.pause();
  Future<void> stop() => Media3PlaybackBridge.stop();
  Future<void> seek(Duration position) => Media3PlaybackBridge.seek(position);

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await Media3PlaybackBridge.setVolume(_volume);
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.25, 4.0);
    await Media3PlaybackBridge.setSpeed(_speed);
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    await Media3PlaybackBridge.setPitch(_pitch);
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _sessionSub?.cancel();
    await _playerStateController.close();
    await _positionController.close();
    await _durationController.close();
    await _sessionController.close();
  }

  static ProcessingState _parseProcessingState(Object? value) =>
      switch (value) {
        'loading' => ProcessingState.loading,
        'buffering' => ProcessingState.buffering,
        'ready' => ProcessingState.ready,
        'completed' => ProcessingState.completed,
        _ => ProcessingState.idle,
      };
}

class AndroidEqualizer {
  Future<void> setEnabled(bool enabled) async =>
      Media3PlaybackBridge.setEqualizerEnabled(enabled);

  Future<AndroidEqualizerParameters> get parameters async =>
      Media3PlaybackBridge.getEqualizerParameters();
}

class AndroidLoudnessEnhancer {
  Future<void> setTargetGain(double gain) =>
      Media3PlaybackBridge.setLoudnessTargetGain(gain);
  Future<void> setEnabled(bool enabled) =>
      Media3PlaybackBridge.setLoudnessEnabled(enabled);
}

class AndroidEqualizerParameters {
  final double minDecibels;
  final double maxDecibels;
  final List<AndroidEqualizerBand> bands;

  const AndroidEqualizerParameters({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bands,
  });
}

class AndroidEqualizerBand {
  final int index;

  const AndroidEqualizerBand(this.index);

  Future<void> setGain(double gainDb) =>
      Media3PlaybackBridge.setEqualizerBandGain(index, gainDb);
}
