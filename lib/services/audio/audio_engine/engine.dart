part of '../audio_engine.dart';

/// Low-level audio hardware facade.
///
/// [DualPlayerManager] owns player lifecycle.  [AudioEngine] exposes a
/// stable [player] getter, keeps DSP references in sync via the
/// [_onPrimaryChanged] callback, and owns all native-effect channel calls.
class AudioEngine {
  AudioEngine._();

  static const MethodChannel _effectsChannel =
      MethodChannel('musicplayer/audio_effects');

  // ── Player references (kept in sync via _onPrimaryChanged) ─────────────────

  static AudioPlayer?             _player;
  static AndroidEqualizer?        _equalizer;
  static AndroidLoudnessEnhancer? _loudnessEnhancer;
  static StreamSubscription<int?>? _sessionSub;

  static bool _initialized = false;

  // Effect-support flags read from native on Android 11+.
  static bool _virtualizerSupported = false;
  static bool _bassBoostSupported   = false;
  static bool _reverbSupported      = false;

  // ── Public getters ──────────────────────────────────────────────────────────

  static AudioPlayer get player {
    assert(_initialized, 'AudioEngine.initialize() must be called first');
    return _player!;
  }

  static AndroidEqualizer?        get equalizer       => _equalizer;
  static AndroidLoudnessEnhancer? get loudnessEnhancer => _loudnessEnhancer;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get virtualizerSupported => _virtualizerSupported;
  static bool get bassBoostSupported   => _bassBoostSupported;
  static bool get reverbSupported      => _reverbSupported;

  // ── Initialization ─────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Register callbacks BEFORE DualPlayerManager.initialize() so the
    // first onPrimaryChanged fires with the callbacks already set.
    DualPlayerManager.onPrimaryChanged     = _onPrimaryChanged;
    DualPlayerManager.onSecondarySessionId = attachEffectsToSession;

    await DualPlayerManager.initialize();

    // Restore stored audio output mode.
    final prefs   = await SharedPreferences.getInstance();
    final modeIdx = prefs.getInt('audioOutputMode') ?? 0;
    final mode    = AudioOutputMode.values[modeIdx.clamp(0, 2)];
    if (mode != AudioOutputMode.auto) applyOutputModeNow(mode);

    LogService.log(
      'AudioEngine',
      isAndroid
          ? 'Initialized (Android DSP via DualPlayerManager)'
          : 'Initialized (web / non-Android)',
    );
  }

  // ── Primary-player change callback ─────────────────────────────────────────

  /// Called by [DualPlayerManager] whenever [primaryPlayer] changes
  /// (at init and on every promote).
  static void _onPrimaryChanged() {
    _player           = DualPlayerManager.primaryPlayer;
    _equalizer        = DualPlayerManager.primaryEqualizer;
    _loudnessEnhancer = DualPlayerManager.primaryLoudness;

    // Re-subscribe to the new primary's Android audio-session ID.
    _sessionSub?.cancel();
    if (isAndroid) {
      _sessionSub = _player!.androidAudioSessionIdStream
          .where((id) => id != null)
          .distinct()
          .listen((id) => _attachNativeEffects(id!));
    }

    LogService.verbose('AudioEngine', 'Active player reference updated');
  }

  // ── Native effect attachment ────────────────────────────────────────────────

  /// Called for BOTH primary (via [_onPrimaryChanged] listener) and
  /// secondary (via [DualPlayerManager.onSecondarySessionId]) so that
  /// native effects are attached before each player ever becomes primary.
  static Future<void> attachEffectsToSession(int sessionId) =>
      _attachNativeEffects(sessionId);

  static Future<void> _attachNativeEffects(int sessionId) async {
    try {
      final result = await _effectsChannel.invokeMapMethod<String, dynamic>(
        'attachEffects',
        {'sessionId': sessionId},
      );
      _virtualizerSupported = result?['virtualizerSupported'] as bool? ?? false;
      _bassBoostSupported   = result?['bassBoostSupported']   as bool? ?? false;
      _reverbSupported      = result?['reverbSupported']      as bool? ?? false;
      LogService.log(
        'AudioEngine',
        'Native effects attached (session $sessionId) — '
        'virt=$_virtualizerSupported, bass=$_bassBoostSupported, '
        'reverb=$_reverbSupported',
      );
    } catch (e) {
      LogService.warn('AudioEngine', 'attachEffects: $e');
    }
  }

  // ── Native effect controls (called by AudioEffectsService) ─────────────────

  static Future<void> setSpatialEnabled(
      bool enabled, {int strength = 1000}) async {
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

  // ── Audio output mode ──────────────────────────────────────────────────────

  static Future<void> setAudioOutputMode(AudioOutputMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('audioOutputMode', mode.index);
    if (isAndroid) applyOutputModeNow(mode);
    LogService.log('AudioEngine', 'Output mode: ${mode.name}');
  }

  static Future<AudioOutputMode> getAudioOutputMode() async {
    final prefs = await SharedPreferences.getInstance();
    final idx   = prefs.getInt('audioOutputMode') ?? 0;
    return AudioOutputMode.values[idx.clamp(0, 2)];
  }

  /// Applies output mode NOW via the native channel (no prefs write).
  static void applyOutputModeNow(AudioOutputMode mode) {
    try {
      _effectsChannel
          .invokeMethod('setAudioOutputMode', {'mode': mode.index});
    } catch (e) {
      LogService.warn('AudioEngine', 'setAudioOutputMode: $e');
    }
  }

  // ── Normalize (LoudnessEnhancer) ──────────────────────────────────────────

  /// [targetGainMb] is in millibels (0 = neutral).
  static void applyNormalize({
    required bool enabled,
    double targetGainMb = 0.0,
  }) {
    final enhancer = _loudnessEnhancer;
    if (enhancer == null) {
      // Non-Android fallback: approximate via player volume.
      try { _player?.setVolume(enabled ? 0.88 : 1.0); } catch (e) {
        LogService.warn('AudioEngine', 'fallback volume: $e');
      }
      return;
    }
    try {
      if (enabled) {
        enhancer.setTargetGain(targetGainMb);
        enhancer.setEnabled(true);
      } else {
        enhancer.setTargetGain(0.0);
        enhancer.setEnabled(false);
      }
    } catch (e) {
      LogService.warn('AudioEngine', 'applyNormalize: $e');
    }
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    _sessionSub?.cancel();
    _sessionSub       = null;
    await DualPlayerManager.dispose();
    _player           = null;
    _equalizer        = null;
    _loudnessEnhancer = null;
    _initialized      = false;
    LogService.log('AudioEngine', 'Disposed');
  }
}
