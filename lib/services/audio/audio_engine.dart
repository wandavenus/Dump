import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../log_service.dart';

/// Creates the [AudioPlayer] with a full Android DSP pipeline
/// (AndroidEqualizer + AndroidLoudnessEnhancer built into just_audio).
/// All services obtain the shared player via [AudioEngine.player].
class AudioEngine {
  AudioEngine._();

  static const MethodChannel _effectsChannel =
      MethodChannel('musicplayer/audio_effects');

  static AudioPlayer? _player;
  static AndroidEqualizer? _equalizer;
  static AndroidLoudnessEnhancer? _loudnessEnhancer;
  static bool _initialized = false;

  static AudioPlayer get player {
    assert(_initialized, 'AudioEngine.initialize() must be called first');
    return _player!;
  }

  static AndroidEqualizer? get equalizer => _equalizer;
  static AndroidLoudnessEnhancer? get loudnessEnhancer => _loudnessEnhancer;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // ── Initialization ─────────────────────────────────────────────────────────

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    if (isAndroid) {
      _equalizer = AndroidEqualizer();
      _loudnessEnhancer = AndroidLoudnessEnhancer();
      _player = AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: [_loudnessEnhancer!, _equalizer!],
        ),
      );
      // When just_audio assigns an audio session, pass it to native effects.
      player.androidAudioSessionIdStream
          .where((id) => id != null)
          .distinct()
          .listen((id) => _attachNativeEffects(id!));
      LogService.log('AudioEngine', 'Android DSP pipeline ready');
    } else {
      _player = AudioPlayer();
      LogService.log('AudioEngine', 'Initialized (web / non-Android)');
    }
  }

  // ── Native effect attachment ────────────────────────────────────────────────

  static Future<void> _attachNativeEffects(int sessionId) async {
    try {
      await _effectsChannel
          .invokeMethod('attachEffects', {'sessionId': sessionId});
      LogService.log('AudioEngine', 'Native effects attached (session $sessionId)');
    } catch (e) {
      LogService.warn('AudioEngine', 'attachEffects: $e');
    }
  }

  // ── Native effect controls (called by AudioEffectsService) ─────────────────

  static Future<void> setSpatialEnabled(bool enabled) async {
    if (!isAndroid) return;
    try {
      await _effectsChannel
          .invokeMethod('setSpatialEnabled', {'enabled': enabled});
    } catch (e) {
      LogService.warn('AudioEngine', 'setSpatialEnabled: $e');
    }
  }

  static Future<void> setBassBoost(int strength) async {
    if (!isAndroid) return;
    try {
      await _effectsChannel
          .invokeMethod('setBassBoost', {'strength': strength.clamp(0, 1000)});
    } catch (e) {
      LogService.warn('AudioEngine', 'setBassBoost: $e');
    }
  }

  static Future<void> setReverb(int preset) async {
    if (!isAndroid) return;
    try {
      await _effectsChannel.invokeMethod('setReverb', {'preset': preset});
    } catch (e) {
      LogService.warn('AudioEngine', 'setReverb: $e');
    }
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
    _equalizer = null;
    _loudnessEnhancer = null;
    _initialized = false;
  }
}
