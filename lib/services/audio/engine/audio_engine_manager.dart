import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../log_service.dart';
import 'aaudio_engine.dart';
import 'abstract_audio_engine.dart';
import 'media3_engine.dart';
import 'playback_engine_type.dart';

class AudioEngineManager {
  AudioEngineManager._();
  static final instance = AudioEngineManager._();
  static const _preferenceKey = 'playback_engine';

  AbstractAudioEngine _active = Media3Engine();
  bool _switching = false;
  final _type = StreamController<PlaybackEngineType>.broadcast();
  final _playback = StreamController<Map<dynamic, dynamic>>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _track = StreamController<Map<dynamic, dynamic>?>.broadcast();
  final _queue = StreamController<List<dynamic>>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _shuffle = StreamController<bool>.broadcast();
  final _repeat = StreamController<String>.broadcast();
  final _sleep = StreamController<Map<dynamic, dynamic>>.broadcast();
  final _session = StreamController<int>.broadcast();
  final _format = StreamController<Map<dynamic, dynamic>>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  AbstractAudioEngine get active => _active;
  PlaybackEngineType get activeType => _active.type;
  Stream<PlaybackEngineType> get activeTypeStream => _type.stream;
  Stream<Map<dynamic, dynamic>> get playbackStateStream => _playback.stream;
  Stream<Duration> get positionStream => _position.stream;
  Stream<Duration> get durationStream => _duration.stream;
  Stream<Map<dynamic, dynamic>?> get currentTrackStream => _track.stream;
  Stream<List<dynamic>> get queueStream => _queue.stream;
  Stream<bool> get bufferingStateStream => _buffering.stream;
  Stream<bool> get shuffleModeStream => _shuffle.stream;
  Stream<String> get repeatModeStream => _repeat.stream;
  Stream<Map<dynamic, dynamic>> get sleepTimerStream => _sleep.stream;
  Stream<int> get audioSessionIdStream => _session.stream;
  Stream<Map<dynamic, dynamic>> get audioFormatStream => _format.stream;

  Future<void> initialize() async {
    await _active.initialize();
    _bind(_active);
    final prefs = await SharedPreferences.getInstance();
    final persisted = PlaybackEngineType.fromId(prefs.getString(_preferenceKey));
    if (persisted != PlaybackEngineType.media3) await switchEngine(persisted);
  }

  Future<void> switchEngine(PlaybackEngineType target) async {
    if (_switching || target == _active.type) return;
    _switching = true;
    final previous = _active;
    Map<String, dynamic>? snapshot;
    try {
      snapshot = await previous.getPlaybackSnapshot();
      await previous.pause();
      final next = _create(target);
      await next.initialize();
      if (snapshot != null) await next.restoreSnapshot(snapshot);
      await previous.release();
      _active = next;
      await _bind(next);
      _type.add(target);
      await (await SharedPreferences.getInstance()).setString(_preferenceKey, target.id);
      LogService.log('AudioEngineManager', 'Active engine: ${target.id}');
    } on Exception catch (error, stack) {
      LogService.log('AudioEngineManager', 'Switch to ${target.id} failed; reverting to Media3: $error\n$stack', level: LogLevel.warning);
      final fallback = previous.type == PlaybackEngineType.media3 ? previous : Media3Engine();
      await fallback.initialize();
      if (snapshot != null) await fallback.restoreSnapshot(snapshot);
      _active = fallback;
      await _bind(fallback);
      _type.add(PlaybackEngineType.media3);
      await (await SharedPreferences.getInstance()).setString(_preferenceKey, PlaybackEngineType.media3.id);
    } finally {
      _switching = false;
    }
  }

  AbstractAudioEngine _create(PlaybackEngineType type) => switch (type) {
    PlaybackEngineType.media3 => Media3Engine(),
    PlaybackEngineType.aaudio => AAudioEngine(),
  };

  Future<void> _bind(AbstractAudioEngine engine) async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions
      ..clear()
      ..addAll([
        engine.playbackStateStream.listen(_playback.add),
        engine.positionStream.listen(_position.add),
        engine.durationStream.listen(_duration.add),
        engine.currentTrackStream.listen(_track.add),
        engine.queueStream.listen(_queue.add),
        engine.bufferingStateStream.listen(_buffering.add),
        engine.shuffleModeStream.listen(_shuffle.add),
        engine.repeatModeStream.listen(_repeat.add),
        engine.sleepTimerStream.listen(_sleep.add),
        engine.audioSessionIdStream.listen(_session.add),
        engine.audioFormatStream.listen(_format.add),
      ]);
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _active.release();
  }
}
