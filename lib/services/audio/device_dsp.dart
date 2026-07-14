import 'dart:async';

import 'package:flutter/foundation.dart';

import '../log_service.dart';
import 'audio_effects_service.dart';
import 'playback_manager.dart';

// ─── DeviceDsp ────────────────────────────────────────────────────────────────

/// Device-level DSP capability inspector and loudness routing helper.
///
/// Responsibilities:
///   • Stores hardware-capability flags for the UI (effect support booleans)
///   • Routes loudness / ReplayGain changes via [PlaybackManager]
///   • Re-queries effect support when the audio session rotates
///
/// No layer in this file may reference [Media3PlaybackBridge] directly.
/// All playback calls go through [PlaybackManager].
class DeviceDsp {
  DeviceDsp._();

  // ── Effect-support flags (queried from native, exposed to UI) ─────────────
  static bool _virtualizerSupported = false;
  static bool _bassBoostSupported   = false;

  static bool _initialized = false;
  static int _lastSessionId = -1;

  // ── Public getters ─────────────────────────────────────────────────────────

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get virtualizerSupported => _virtualizerSupported;
  static bool get bassBoostSupported   => _bassBoostSupported;

  // ── Initialization ─────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Query effect support from native (non-blocking).
    unawaited(queryEffectSupport());

    LogService.log('DeviceDsp', 'Initialized');
  }

  // ── Effect-support query ───────────────────────────────────────────────────

  /// Queries native for device-level effect support flags.
  /// Called on init and whenever the audio session ID changes.
  static Future<void> queryEffectSupport() async {
    if (!isAndroid) return;
    try {
      final result = await PlaybackManager.getEffectSupport();
      if (result == null) return;
      _virtualizerSupported = result['virtualizerSupported'] as bool? ?? false;
      _bassBoostSupported   = result['bassBoostSupported']   as bool? ?? false;
      LogService.log(
        'DeviceDsp',
        'Effect support — virt=$_virtualizerSupported, '
        'bass=$_bassBoostSupported',
      );
    } catch (e) {
      LogService.warn('DeviceDsp', 'queryEffectSupport: $e');
    }
  }

  // ── attachEffectsToSession ─────────────────────────────────────────────────
  //
  // Audio session changes are now handled internally by Media3PlaybackService.
  // When ExoPlayer's audioSessionId changes it calls attachEffects() directly.
  // This Dart method re-queries effect support so that UI capability flags stay
  // fresh after a session ID rotation.

  static Future<void> attachEffectsToSession(int sessionId) async {
    if (!isAndroid || sessionId <= 0) return;
    if (_lastSessionId == sessionId) return;
    _lastSessionId = sessionId;
    await queryEffectSupport();
  }

  // ── Normalize / ReplayGain ─────────────────────────────────────────────────

  /// Applies loudness normalization (system LoudnessEnhancer, AudioFlinger
  /// layer) via [PlaybackManager].
  ///
  /// [targetGainMb] is in millibels (100 mb = 1 dB).
  ///
  /// Reverse mutual-exclusion interlock: the system LoudnessEnhancer and the
  /// native EBU R128 Loudness Norm processor apply gain in series on the same
  /// signal path. Enabling this while native Loudness Norm is active would
  /// double-boost and risk clipping (see AudioEffectsService.
  /// setLoudnessNormEnabled for the forward direction of this interlock), so
  /// enabling the system LoudnessEnhancer here disables native Loudness Norm.
  static void applyNormalize({
    required bool enabled,
    double targetGainMb = 0.0,
  }) {
    if (kIsWeb) return;
    // Clamp to ±2400 mb (±24 dB) matching LoudnessEnhancer limits on Android.
    final clamped = targetGainMb.clamp(-2400.0, 2400.0);
    if (enabled && AudioEffectsService.loudnessNormEnabled.value) {
      unawaited(AudioEffectsService.setLoudnessNormEnabled(false));
      LogService.log(
        'DeviceDsp',
        'Native Loudness Norm disabled — system LoudnessEnhancer is now active',
      );
    }
    unawaited(PlaybackManager.setLoudnessEnabled(enabled));
    unawaited(PlaybackManager.setLoudnessTargetGain(enabled ? clamped : 0.0));
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    _virtualizerSupported = false;
    _bassBoostSupported   = false;
    _initialized          = false;
    _lastSessionId        = -1;
    LogService.log('DeviceDsp', 'Disposed');
  }
}
