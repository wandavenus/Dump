import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_song.dart';
import '../log_service.dart';
import 'aaudio/aaudio_audio_engine.dart';
import 'audio_engine.dart';
import 'media3/media3_audio_engine.dart';

class AudioEngineManager {
  AudioEngineManager._();

  static const String preferenceKey = 'audio_engine_type';
  static final ValueNotifier<AudioEngineType> selectedEngine = ValueNotifier<AudioEngineType>(AudioEngineType.media3);
  static AudioEngine? _engine;
  static List<LocalSong> _lastQueue = const [];
  static int _lastIndex = 0;
  static double _lastVolume = 1.0;
  static bool _initialized = false;

  static AudioEngine get engine => _engine ??= Media3AudioEngine();

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final preferred = AudioEngineType.fromId(prefs.getString(preferenceKey));
    await _switchTo(preferred, persist: false);
  }

  static Future<void> setPreferredEngine(AudioEngineType type) async {
    await _switchTo(type, persist: true);
  }

  static Future<void> _switchTo(AudioEngineType type, {required bool persist}) async {
    if (_engine?.type == type) return;
    final old = _engine;
    final next = _create(type);
    try {
      await old?.stop();
      await old?.dispose();
      await next.initialize();
      _engine = next;
      selectedEngine.value = type;
      if (persist) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(preferenceKey, type.id);
      }
      if (_lastQueue.isNotEmpty) await next.setQueue(_lastQueue, _lastIndex);
      await next.setVolume(_lastVolume);
      LogService.log('AudioEngineManager', 'Using ${type.label}');
    } catch (e) {
      LogService.log('AudioEngineManager', '${type.label} init failed; falling back to Native Media3: $e');
      await next.dispose().catchError((_) {});
      final fallback = Media3AudioEngine();
      await fallback.initialize();
      _engine = fallback;
      selectedEngine.value = AudioEngineType.media3;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(preferenceKey, AudioEngineType.media3.id);
    }
  }

  static AudioEngine _create(AudioEngineType type) => switch (type) {
    AudioEngineType.media3 => Media3AudioEngine(),
    AudioEngineType.aaudio => AAudioAudioEngine(),
  };

  static void rememberQueue(List<LocalSong> queue, int index) {
    _lastQueue = List<LocalSong>.unmodifiable(queue);
    _lastIndex = index;
  }

  static void rememberTrackIndex(int index) => _lastIndex = index;
  static void rememberVolume(double volume) => _lastVolume = volume;
}
