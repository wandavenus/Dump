import 'package:flutter/services.dart';

import '../../../models/local_song.dart';
import 'media3_audio_player.dart'
    show AndroidEqualizerBand, AndroidEqualizerParameters;

/// Flutter ↔ Android Media3 bridge.
///
/// The UI continues to talk to `AudioService` / `PlayerController` style
/// facades; this class is the native playback edge used when the Media3 engine
/// feature flag is enabled.
class Media3PlaybackBridge {
  Media3PlaybackBridge._();

  static const MethodChannel _commands = MethodChannel(
    'musicplayer/media3_playback',
  );

  static const EventChannel playbackStateEvents = EventChannel(
    'musicplayer/media3_playbackState',
  );
  static const EventChannel positionEvents = EventChannel(
    'musicplayer/media3_position',
  );
  static const EventChannel durationEvents = EventChannel(
    'musicplayer/media3_duration',
  );
  static const EventChannel currentTrackEvents = EventChannel(
    'musicplayer/media3_currentTrack',
  );
  static const EventChannel queueEvents = EventChannel(
    'musicplayer/media3_queue',
  );
  static const EventChannel bufferingStateEvents = EventChannel(
    'musicplayer/media3_bufferingState',
  );
  static const EventChannel audioSessionIdEvents = EventChannel(
    'musicplayer/media3_audioSessionId',
  );

  static Stream<Map<dynamic, dynamic>> get playbackStateStream =>
      playbackStateEvents
          .receiveBroadcastStream()
          .where((e) => e is Map)
          .cast<Map<dynamic, dynamic>>();
  static Stream<Duration> get positionStream => positionEvents
      .receiveBroadcastStream()
      .where((e) => e is num)
      .map((e) => Duration(milliseconds: (e as num).toInt()));
  static Stream<Duration> get durationStream => durationEvents
      .receiveBroadcastStream()
      .where((e) => e is num)
      .map((e) => Duration(milliseconds: (e as num).toInt()));
  static Stream<Map<dynamic, dynamic>?> get currentTrackStream =>
      currentTrackEvents
          .receiveBroadcastStream()
          .where((e) => e == null || e is Map)
          .cast<Map<dynamic, dynamic>?>();
  static Stream<List<dynamic>> get queueStream => queueEvents
      .receiveBroadcastStream()
      .where((e) => e is List)
      .cast<List<dynamic>>();
  static Stream<bool> get bufferingStateStream => bufferingStateEvents
      .receiveBroadcastStream()
      .where((e) => e is bool)
      .cast<bool>();
  static Stream<int> get audioSessionIdStream => audioSessionIdEvents
      .receiveBroadcastStream()
      .where((e) => e is num)
      .map((e) => (e as num).toInt());

  static Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _commands.invokeMethod<T>(method, arguments);
      } on PlatformException catch (error) {
        if (error.code != 'not_ready' || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
      }
    }
    return null;
  }

  static Future<void> play() => _invoke<void>('play');
  static Future<void> pause() => _invoke<void>('pause');
  static Future<void> stop() => _invoke<void>('stop');
  static Future<void> seek(Duration position) =>
      _invoke<void>('seek', {'position': position.inMilliseconds});
  static Future<void> skipNext() => _invoke<void>('skipNext');
  static Future<void> skipPrevious() => _invoke<void>('skipPrevious');
  static Future<void> setTrack(int index) =>
      _invoke<void>('setTrack', {'index': index});
  static Future<void> setQueue(List<LocalSong> queue, int index) =>
      _invoke<void>('setQueue', {
        'queue': queue.map((s) => s.toMap()).toList(),
        'index': index,
      });
  static Future<void> setRepeatMode(String mode) =>
      _invoke<void>('setRepeatMode', {'mode': mode});
  static Future<void> setShuffleMode(bool enabled) =>
      _invoke<void>('setShuffleMode', {'enabled': enabled});
  static Future<void> setVolume(double volume) =>
      _invoke<void>('setVolume', {'volume': volume});
  static Future<void> setSpeed(double speed) =>
      _invoke<void>('setSpeed', {'speed': speed});
  static Future<void> setPitch(double pitch) =>
      _invoke<void>('setPitch', {'pitch': pitch});
  static Future<void> setEqualizerEnabled(bool enabled) =>
      _invoke<void>('setEqualizerEnabled', {'enabled': enabled});
  static Future<void> setEqualizerBandGain(int band, double gainDb) =>
      _invoke<void>('setEqualizerBandGain', {'band': band, 'gainDb': gainDb});
  static Future<void> setLoudnessTargetGain(double gainMb) =>
      _invoke<void>('setLoudnessTargetGain', {'gainMb': gainMb});
  static Future<void> setLoudnessEnabled(bool enabled) =>
      _invoke<void>('setLoudnessEnabled', {'enabled': enabled});

  static Future<AndroidEqualizerParameters> getEqualizerParameters() async {
    final rawDynamic = await _invoke<Map<dynamic, dynamic>>(
      'getEqualizerParameters',
    );
    final raw = rawDynamic?.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final bands = (raw?['bands'] as List<dynamic>? ?? const [0, 1, 2, 3, 4])
        .map((band) => AndroidEqualizerBand((band as num).toInt()))
        .toList();
    return AndroidEqualizerParameters(
      minDecibels: (raw?['minDecibels'] as num?)?.toDouble() ?? -15.0,
      maxDecibels: (raw?['maxDecibels'] as num?)?.toDouble() ?? 15.0,
      bands: bands,
    );
  }
}
