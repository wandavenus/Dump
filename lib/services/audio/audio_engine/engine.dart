part of '../audio_engine.dart';

/// Thin settings facade — no longer owns any just_audio player references.
///
/// All DSP (EQ, loudness, bass, virtualizer, reverb, speed, pitch, crossfade)
/// is handled natively by `Media3PlaybackService.kt`.  AudioEngine now:
///   • Stores device-capability flags for UI (effect support booleans)
///   • Routes loudness / ReplayGain changes to native via [Media3PlaybackBridge]
///   • Provides [attachEffectsToSession] as a no-op (kept for call-site compat)
class AudioEngine {
  AudioEngine._();

  // ── Effect-support flags (queried from native, exposed to UI) ──────────────
  static bool _virtualizerSupported = false;
  static bool _bassBoostSupported   = false;
  static bool _reverbSupported      = false;

  static bool _initialized = false;
  static int _lastSessionId = -1;
  // ── Public getters ─────────────────────────────────────────────────────────

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get virtualizerSupported => _virtualizerSupported;
  static bool get bassBoostSupported   => _bassBoostSupported;
  static bool get reverbSupported      => _reverbSupported;

  // ── Initialization ─────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Query effect support from native (non-blocking — runs after first session).
    unawaited(queryEffectSupport());

    LogService.log('AudioEngine', 'Initialized (native DSP via Media3PlaybackService)');
  }

  // ── Effect-support query ───────────────────────────────────────────────────

  /// Queries native for device-level effect support flags.
  /// Called on init and whenever the audio session changes.
  static Future<void> queryEffectSupport() async {
    if (!isAndroid) return;
    try {
      final result = await Media3PlaybackBridge.getEffectSupport();
      if (result == null) return;
      _virtualizerSupported = result['virtualizerSupported'] as bool? ?? false;
      _bassBoostSupported   = result['bassBoostSupported']   as bool? ?? false;
      _reverbSupported      = result['reverbSupported']      as bool? ?? false;
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

  /// Applies loudness normalization (LoudnessEnhancer) on the native side.
  ///
  /// [targetGainMb] is in millibels (100 mb = 1 dB).
  static void applyNormalize({
    required bool enabled,
    double targetGainMb = 0.0,
  }) {
    if (kIsWeb) return;
    // Clamp to ±2400 mb (±24 dB) matching LoudnessEnhancer limits on Android.
    final clamped = targetGainMb.clamp(-2400.0, 2400.0);
    unawaited(Media3PlaybackBridge.setLoudnessEnabled(enabled));
    unawaited(Media3PlaybackBridge.setLoudnessTargetGain(enabled ? clamped : 0.0));
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    _virtualizerSupported = false;
    _bassBoostSupported   = false;
    _reverbSupported      = false;
    _initialized          = false;
    LogService.log('AudioEngine', 'Disposed');
  }
}
