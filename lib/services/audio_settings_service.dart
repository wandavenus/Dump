import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_service.dart';
import 'log_service.dart';

class AudioSettingsService {
  AudioSettingsService._();

  static final ValueNotifier<bool> gaplessPlayback = ValueNotifier(false);
  static final ValueNotifier<bool> audioNormalize = ValueNotifier(false);
  static final ValueNotifier<double> crossfadeDuration = ValueNotifier(0.0);
  static final ValueNotifier<double> pitchShift = ValueNotifier(0.0);
  static final ValueNotifier<bool> spatialAudio = ValueNotifier(false);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    gaplessPlayback.value = prefs.getBool('gapless') ?? false;
    audioNormalize.value = prefs.getBool('normalize') ?? false;
    crossfadeDuration.value = prefs.getDouble('crossfade') ?? 0.0;
    pitchShift.value = prefs.getDouble('pitch') ?? 0.0;
    spatialAudio.value = prefs.getBool('spatial') ?? false;

    _applyNormalize(audioNormalize.value);
    _applyPitch(pitchShift.value);
    LogService.log('AudioSettings', 'Initialized');
  }

  // ─── Gapless ───────────────────────────────────────────────────────────────
  static Future<void> setGapless(bool value) async {
    gaplessPlayback.value = value;
    (await SharedPreferences.getInstance()).setBool('gapless', value);
    LogService.log('AudioSettings', 'Gapless: $value');
  }

  // ─── Normalize ─────────────────────────────────────────────────────────────
  static Future<void> setNormalize(bool value) async {
    audioNormalize.value = value;
    (await SharedPreferences.getInstance()).setBool('normalize', value);
    _applyNormalize(value);
    LogService.log('AudioSettings', 'Normalize: $value');
  }

  static void _applyNormalize(bool enabled) {
    try {
      AudioService.player.setVolume(enabled ? 0.82 : 1.0);
    } catch (_) {}
  }

  // ─── Crossfade ─────────────────────────────────────────────────────────────
  static Future<void> setCrossfade(double seconds) async {
    crossfadeDuration.value = seconds;
    (await SharedPreferences.getInstance()).setDouble('crossfade', seconds);
    LogService.log('AudioSettings', 'Crossfade: ${seconds}s');
  }

  // ─── Pitch Shift ───────────────────────────────────────────────────────────
  static Future<void> setPitch(double semitones) async {
    pitchShift.value = semitones;
    (await SharedPreferences.getInstance()).setDouble('pitch', semitones);
    _applyPitch(semitones);
    LogService.log('AudioSettings', 'Pitch: ${semitones} semitones');
  }

  static void _applyPitch(double semitones) {
    try {
      if (kIsWeb) return;
      final factor = math.pow(2.0, semitones / 12.0).toDouble();
      AudioService.player.setPitch(factor);
    } catch (_) {}
  }

  // ─── Spatial Audio ─────────────────────────────────────────────────────────
  static Future<void> setSpatial(bool value) async {
    spatialAudio.value = value;
    (await SharedPreferences.getInstance()).setBool('spatial', value);
    LogService.log('AudioSettings', 'Spatial: $value');
  }

  static void applyAll() {
    _applyNormalize(audioNormalize.value);
    _applyPitch(pitchShift.value);
  }
}
