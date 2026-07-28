import 'package:flutter/services.dart';

import '../../../models/local_song.dart';
import '../../../utils/safe_num.dart';

class AAudioPlaybackBridge {
  AAudioPlaybackBridge._();

  static const _commands = MethodChannel('musicplayer/aaudio_playback');
  static const _prefix = 'musicplayer/aaudio_';

  static Stream<T> _events<T>(String name) =>
      EventChannel('$_prefix$name').receiveBroadcastStream().whereType<T>().asBroadcastStream();

  static final playbackStateStream = _events<Map<dynamic, dynamic>>('playbackState');
  static final positionStream = _events<num>('position')
      .map((value) => Duration(milliseconds: value.toIntOrElse(0))).asBroadcastStream();
  static final durationStream = _events<num>('duration')
      .map((value) => Duration(milliseconds: value.toIntOrElse(0))).asBroadcastStream();
  static final currentTrackStream = EventChannel('${_prefix}currentTrack')
      .receiveBroadcastStream().where((event) => event == null || event is Map)
      .cast<Map<dynamic, dynamic>?>().asBroadcastStream();
  static final queueStream = _events<List<dynamic>>('queue');
  static final bufferingStateStream = _events<bool>('bufferingState');
  static final shuffleModeStream = _events<bool>('shuffleMode');
  static final repeatModeStream = _events<String>('repeatMode');
  static final sleepTimerStream = _events<Map<dynamic, dynamic>>('sleepTimer');
  static final audioSessionIdStream = _events<num>('audioSessionId').map((v) => v.toInt()).asBroadcastStream();
  static final audioFormatStream = _events<Map<dynamic, dynamic>>('audioFormat');

  static Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        return await _commands.invokeMethod<T>(method, args);
      } on PlatformException catch (error) {
        if (error.code != 'not_ready' || attempt == 4) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 200 * (1 << attempt)));
      }
    }
    return null;
  }

  static Future<void> initialize() => _invoke<void>('initialize');
  static Future<void> play() => _invoke<void>('play');
  static Future<void> pause() => _invoke<void>('pause');
  static Future<void> stop() => _invoke<void>('stop');
  static Future<void> release() => _invoke<void>('release');
  static Future<void> seek(Duration p) => _invoke<void>('seek', {'position': p.inMilliseconds});
  static Future<void> skipNext() => _invoke<void>('skipNext');
  static Future<void> skipPrevious() => _invoke<void>('skipPrevious');
  static Future<void> setTrack(int i) => _invoke<void>('setTrack', {'index': i});
  static Future<void> setQueue(List<LocalSong> q, int i) => _invoke<void>('setQueue', {'queue': q.map((s) => s.toMap()).toList(), 'index': i});
  static Future<void> insertNext(LocalSong s) => _invoke<void>('insertNext', {'song': s.toMap()});
  static Future<void> appendToQueue(LocalSong s) => _invoke<void>('appendToQueue', {'song': s.toMap()});
  static Future<void> removeFromQueue(int i) => _invoke<void>('removeFromQueue', {'index': i});
  static Future<void> reorderQueue(int o, int n) => _invoke<void>('reorderQueue', {'oldIndex': o, 'newIndex': n});
  static Future<void> setVolume(double v) => _invoke<void>('setVolume', {'volume': v});
  static Future<void> setSpeed(double v) => _invoke<void>('setSpeed', {'speed': v});
  static Future<void> setPitch(double v) => _invoke<void>('setPitch', {'pitch': v});
  static Future<void> setRepeatMode(String m) => _invoke<void>('setRepeatMode', {'mode': m});
  static Future<void> setShuffleMode(bool e) => _invoke<void>('setShuffleMode', {'enabled': e});
  static Future<void> setSleepTimer(int ms) => _invoke<void>('setSleepTimer', {'durationMs': ms});
  static Future<void> setSleepTimerEndOfSong() => _invoke<void>('setSleepTimerEndOfSong');
  static Future<void> cancelSleepTimer() => _invoke<void>('cancelSleepTimer');
  static Future<Map<String, dynamic>?> getPlaybackSnapshot() async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getPlaybackSnapshot');
    return raw?.map((key, value) => MapEntry(key.toString(), value));
  }
}
