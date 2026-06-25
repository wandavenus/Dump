/// Thin compatibility shim — delegates everything to [AudioEffectsService].
///
/// All existing code that imports [AudioSettingsService] will continue to
/// work without changes. New code should use [AudioEffectsService] directly.
library;

import 'package:flutter/foundation.dart';

import 'audio/audio_effects_service.dart';

class AudioSettingsService {
  AudioSettingsService._();

  // ── Notifiers (forwarded from AudioEffectsService) ─────────────────────────

  static ValueNotifier<bool> get audioNormalize =>
      AudioEffectsService.audioNormalize;
  static ValueNotifier<double> get crossfadeDuration =>
      AudioEffectsService.crossfadeDuration;
  static ValueNotifier<double> get pitchShift =>
      AudioEffectsService.pitchShift;
  static ValueNotifier<bool> get spatialAudio =>
      AudioEffectsService.spatialAudio;

  // ── Init ───────────────────────────────────────────────────────────────────

  static Future<void> init() => AudioEffectsService.init();

  // ── Setters ────────────────────────────────────────────────────────────────

  static Future<void> setNormalize(bool value) =>
      AudioEffectsService.setNormalize(value);

  static Future<void> setCrossfade(double seconds) =>
      AudioEffectsService.setCrossfade(seconds);

  static Future<void> setPitch(double semitones) =>
      AudioEffectsService.setPitch(semitones);

  static Future<void> setSpatial(bool value) =>
      AudioEffectsService.setSpatial(value);

  static void applyAll() => AudioEffectsService.applyAll();
}
