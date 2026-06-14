part of '../audio_engine.dart';

/// Creates the [AudioPlayer] with Android DSP pipeline.
/// Exposes native audio effects via MethodChannel.
class AudioEngine {
  AudioEngine._();

  static const MethodChannel _effectsChannel =
      MethodChannel('musicplayer/audio_effects');

  static AudioPlayer? _player;
  static AndroidEqualizer? _equalizer;
  static AndroidLoudnessEnhancer? _loudnessEnhancer;
  static bool _initialized = false;
  static double _preampVolume = 1.0;
  static double _trackVolume = 1.0;
  static double _fadeVolume = 1.0;
  static bool _limiterEnabled = true;
  static double _limiterCeiling = 1.0;

  // Effect support flags (queried from native on Android 11+)
  static bool _virtualizerSupported = false;
  static bool _bassBoostSupported   = false;
  static bool _reverbSupported      = false;

  static AudioPlayer get player {
    assert(_initialized, 'AudioEngine.initialize() must be called first');
    return _player!;
  }

  static AndroidEqualizer? get equalizer => _equalizer;
  static AndroidLoudnessEnhancer? get loudnessEnhancer => _loudnessEnhancer;
  static double get effectiveVolume =>
      (_preampVolume.clamp(0.0, 1.0) * _trackVolume * _fadeVolume)
          .clamp(0.0, _limiterEnabled ? _limiterCeiling : 1.0)
          .toDouble();

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get virtualizerSupported => _virtualizerSupported;
  static bool get bassBoostSupported   => _bassBoostSupported;
  static bool get reverbSupported      => _reverbSupported;

  // ── Initialization ─────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (isAndroid) {
      _equalizer       = AndroidEqualizer();
      _loudnessEnhancer = AndroidLoudnessEnhancer();
      _player = AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: [_loudnessEnhancer!, _equalizer!],
        ),
      );

      // Listen for audio session ID to attach native effects
      player.androidAudioSessionIdStream
          .where((id) => id != null)
          .distinct()
          .listen((id) => _attachNativeEffects(id!));

      // Apply stored audio output mode
      final prefs = await SharedPreferences.getInstance();
      final modeIdx = prefs.getInt('audioOutputMode') ?? 0;
      final mode = AudioOutputMode.values[modeIdx.clamp(0, 2).toInt()];
      if (mode != AudioOutputMode.auto) {
        _applyOutputMode(mode);
      }

      LogService.log('AudioEngine', 'Android DSP pipeline pronta');
    } else {
      _player = AudioPlayer();
      LogService.log('AudioEngine', 'Initialized (web / non-Android)');
    }
  }

  // ── Native effect attachment ────────────────────────────────────────────────

  static Future<void> _attachNativeEffects(int sessionId) async {
    try {
      final result = await _effectsChannel.invokeMapMethod<String, dynamic>(
        'attachEffects',
        {'sessionId': sessionId},
      );
      // Parse support flags returned by native code
      _virtualizerSupported = result?['virtualizerSupported'] as bool? ?? false;
      _bassBoostSupported   = result?['bassBoostSupported']   as bool? ?? false;
      _reverbSupported      = result?['reverbSupported']      as bool? ?? false;
      LogService.log(
        'AudioEngine',
        'Native effects attached (session $sessionId) — '
        'virt=$_virtualizerSupported, bass=$_bassBoostSupported, reverb=$_reverbSupported',
      );
    } catch (e) {
      LogService.warn('AudioEngine', 'attachEffects: $e');
    }
  }

  // ── Native effect controls (called by AudioEffectsService) ─────────────────

  static Future<void> setSpatialEnabled(bool enabled, {int strength = 1000}) async {
    if (!isAndroid) return;
    try {
      await _effectsChannel.invokeMethod('setSpatialEnabled', {
        'enabled':  enabled,
        'strength': strength.clamp(0, 1000).toInt(),
      });
    } catch (e) {
      LogService.warn('AudioEngine', 'setSpatialEnabled: $e');
    }
  }

  static Future<void> setBassBoost(int strength) async {
    if (!isAndroid) return;
    try {
      await _effectsChannel
          .invokeMethod('setBassBoost', {'strength': strength.clamp(0, 1000).toInt()});
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

  // ── Audio output mode ──────────────────────────────────────────────────────

  static Future<void> setAudioOutputMode(AudioOutputMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('audioOutputMode', mode.index);
    if (isAndroid) _applyOutputMode(mode);
    LogService.log('AudioEngine', 'Output mode: ${mode.name}');
  }

  static Future<AudioOutputMode> getAudioOutputMode() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('audioOutputMode') ?? 0;
    return AudioOutputMode.values[idx.clamp(0, 2).toInt()];
  }

  static void _applyOutputMode(AudioOutputMode mode) {
    try {
      _effectsChannel
          .invokeMethod('setAudioOutputMode', {'mode': mode.index});
    } catch (e) {
      LogService.warn('AudioEngine', 'setAudioOutputMode: $e');
    }
  }

  // ── Normalize (LoudnessEnhancer) ──────────────────────────────────────────

  /// targetGain in millibels (0 = neutral). Uses a conservative gain so the
  /// Android LoudnessEnhancer behaves as gentle levelling, not ReplayGain.
  static void applyNormalize({
    required bool enabled,
    double targetGainMb = 25.0,
    double preamp = 1.0,
  }) {
    final preampGainMb = preamp > 1.0
        ? (preamp.clamp(1.0, 2.0).toDouble() - 1.0) * 600.0
        : 0.0;
    final requestedGainMb = (enabled ? targetGainMb : 0.0) + preampGainMb;
    final enhancer = _loudnessEnhancer;
    if (enhancer == null) {
      _applyEffectiveVolume();
      return;
    }
    try {
      if (requestedGainMb > 0.0) {
        enhancer.setTargetGain(requestedGainMb);
        enhancer.setEnabled(true);
      } else {
        enhancer.setTargetGain(0.0);
        enhancer.setEnabled(false);
      }
    } catch (e) {
      LogService.warn('AudioEngine', 'applyNormalize: $e');
    }
  }

  // ── Volume stack ──────────────────────────────────────────────────────────

  static void setPreampVolume(double value) {
    _preampVolume = value.clamp(0.0, 2.0).toDouble();
    _applyEffectiveVolume();
  }

  static void setTrackVolume(double value) {
    _trackVolume = value.clamp(0.0, 1.0).toDouble();
    _applyEffectiveVolume();
  }

  static void setFadeVolume(double value) {
    _fadeVolume = value.clamp(0.0, 1.0).toDouble();
    _applyEffectiveVolume();
  }

  static void setLimiter({required bool enabled, double ceiling = 1.0}) {
    _limiterEnabled = enabled;
    _limiterCeiling = ceiling.clamp(0.1, 1.0).toDouble();
    _applyEffectiveVolume();
  }

  static void _applyEffectiveVolume() {
    try {
      _player?.setVolume(effectiveVolume);
    } catch (error) {
      LogService.warn('AudioEngine', 'set effective volume: $error');
    }
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    await _player?.dispose();
    _player         = null;
    _equalizer      = null;
    _loudnessEnhancer = null;
    _initialized    = false;
    _preampVolume = 1.0;
    _trackVolume = 1.0;
    _fadeVolume = 1.0;
    _limiterEnabled = true;
    _limiterCeiling = 1.0;
  }
}
