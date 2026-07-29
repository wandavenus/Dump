import 'package:flutter/services.dart';

import '../../../models/local_song.dart';
import '../../../utils/safe_num.dart';

class AAudioPlaybackBridge {
  AAudioPlaybackBridge._();

  static const MethodChannel _commands = MethodChannel('musicplayer/aaudio_playback');
  static const EventChannel _events = EventChannel('musicplayer/aaudio_events');

  static final Stream<Map<dynamic, dynamic>> events = _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .cast<Map<dynamic, dynamic>>()
      .asBroadcastStream();

  static Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) =>
      _commands.invokeMethod<T>(method, args);

  static Future<void> initialize() => _invoke<void>('initialize');
  static Future<void> play() => _invoke<void>('play');
  static Future<void> pause() => _invoke<void>('pause');
  static Future<void> stop() => _invoke<void>('stop');
  static Future<void> dispose() => _invoke<void>('dispose');
  static Future<void> seek(Duration position) =>
      _invoke<void>('seek', {'position': position.inMilliseconds});
  static Future<void> setVolume(double volume) =>
      _invoke<void>('setVolume', {'volume': volume});
  static Future<void> setQueue(List<LocalSong> queue, int index) =>
      _invoke<void>('setQueue', {'queue': queue.map((s) => s.toMap()).toList(), 'index': index});
  static Future<void> setTrack(int index) => _invoke<void>('setTrack', {'index': index});
  static Future<void> skipNext() => _invoke<void>('skipNext');
  static Future<void> skipPrevious() => _invoke<void>('skipPrevious');

  static Duration durationFrom(dynamic value) =>
      Duration(milliseconds: (value as num?)?.toIntOrElse(0) ?? 0);
}
