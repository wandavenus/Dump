part of '../audio_engine.dart';

/// Thin settings facade — no longer owns any player references.
///
/// All DSP (EQ, loudness, bass, virtualizer, reverb, speed, pitch, crossfade)
/// is handled natively by `Media3PlaybackService.kt` or by the active
/// [AbstractAudioEngine] implementation. AudioEngine now:
///   • Stores device-capability flags for UI (effect support booleans)
///   • Routes loudness / ReplayGain changes via [AudioEngineManager]
///   • Provides [attachEffectsToSession] as a no-op (kept for call-site compat)
///
/// No layer in this file may reference Media3PlaybackBridge directly.
/// All engine calls go through [AudioEngineManager].
class AudioEngine {
  AudioEngine._();

  // ── Effect-support flags (queried from active engine, exposed to UI) ────────
  static bool _virtualizerSupported = false;
  static bool _bassBoostSupported = false;
  static bool _reverbSupported = false;

  static bool _initialized = false;
  static int _lastSessionId = -1;

  // ── Public getters ─────────────────────────────────────────────────────────

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get virtualizerSupported => _virtualizerSupported;
  static bool get bassBoostSupported => _bassBoostSupported;
  static bool get reverbSupported => _reverbSupported;

  // ── Initialization ─────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Query effect support from the active engine (non-blocking).
    unawaited(queryEffectSupport());

    LogService.log('AudioEngine', 'Initialized (DSP via AudioEngineManager)');
  }

  // ── Effect-support query ───────────────────────────────────────────────────

  /// Queries the active engine for device-level effect support flags.
  /// Called on init and whenever the audio session changes.
  static Future<void> queryEffectSupport() async {
    if (!isAndroid) return;
    try {
      final result = await AudioEngineManager.getEffectSupport();
      if (result == null) return;
      _virtualizerSupported = result['virtualizerSupported'] as bool? ?? false;
      _bassBoostSupported = result['bassBoostSupported'] as bool? ?? false;
      _reverbSupported = result['reverbSupported'] as bool? ?? false;
      LogService.log(
        'AudioEngine',
        'Effect support — virt=$_virtualizerSupported, '
            'bass=$_bassBoostSupported, reverb=$_reverbSupported',
      );
    } catch (e) {
      LogService.warn('AudioEngine', 'queryEffectSupport: $e');
    }
  }

  // ── attachEffectsToSession — kept for AudioService call-site compat ─────────
  //
  // Audio session changes are now handled internally by Media3PlaybackService.
  // When ExoPlayer's audioSessionId changes it calls attachEffects() directly.
  // This Dart method is a no-op but we re-query effect support here so that
  // UI capability flags stay fresh after a session ID rotation.

  static Future<void> attachEffectsToSession(int sessionId) async {
    if (!isAndroid || sessionId <= 0) return;
    if (_lastSessionId == sessionId) return;
    _lastSessionId = sessionId;
    await queryEffectSupport();
  }

  // ── Normalize / ReplayGain ─────────────────────────────────────────────────

  /// Applies loudness normalization (LoudnessEnhancer) via the active engine.
  ///
  /// [targetGainMb] is in millibels (100 mb = 1 dB).
  static void applyNormalize({
    required bool enabled,
    double targetGainMb = 0.0,
  }) {
    if (kIsWeb) return;
    // Clamp to ±2400 mb (±24 dB) matching LoudnessEnhancer limits on Android.
    final clamped = targetGainMb.clamp(-2400.0, 2400.0);
    unawaited(AudioEngineManager.setLoudnessEnabled(enabled));
    unawaited(
      AudioEngineManager.setLoudnessTargetGain(enabled ? clamped : 0.0),
    );
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    _virtualizerSupported = false;
    _bassBoostSupported = false;
    _reverbSupported = false;
    _initialized = false;
    _lastSessionId = -1;
    LogService.log('AudioEngine', 'Disposed');
  }
}
