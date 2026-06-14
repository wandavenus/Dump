import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../log_service.dart';
import 'audio_engine.dart';

/// Manages all DSP / playback-quality settings and persists them.
///
/// Feature map:
///   • Loudness normalize   → AndroidLoudnessEnhancer (Android) / volume (web)
///   • Equalizer            → AndroidEqualizer (Android only)
///   • Bass boost           → Android BassBoost native effect
///   • Reverb               → Android PresetReverb native effect
///   • Spatial audio        → Android Virtualizer native effect
///   • Pitch shift          → just_audio setPitch()
///   • Playback speed       → just_audio setSpeed()
///   • Crossfade            → CrossfadeController
///   • Gapless              → ConcatenatingAudioSource (always active)
class AudioEffectsService {
  AudioEffectsService._();

  // ── Value notifiers (UI listens to these) ──────────────────────────────────

  static final ValueNotifier<bool> gaplessPlayback = ValueNotifier(true);
  static final ValueNotifier<bool> audioNormalize = ValueNotifier(false);
  static final ValueNotifier<double> crossfadeDuration = ValueNotifier(0.0);
  static final ValueNotifier<double> pitchShift = ValueNotifier(0.0);
  static final ValueNotifier<bool> spatialAudio = ValueNotifier(false);
  static final ValueNotifier<int> bassBoost = ValueNotifier(0);
  static final ValueNotifier<int> reverbPreset = ValueNotifier(0);
  static final ValueNotifier<double> playbackSpeed = ValueNotifier(1.0);
  static final ValueNotifier<bool> equalizerEnabled = ValueNotifier(false);

  // ── Reverb preset labels ───────────────────────────────────────────────────

  static const List<String> reverbPresetNames = [
    'Off',
    'Small Room',
    'Medium Room',
    'Large Room',
    'Medium Hall',
    'Large Hall',
    'Plate',
  ];

  // ── Init ───────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    gaplessPlayback.value = prefs.getBool('gapless') ?? true;
    audioNormalize.value = prefs.getBool('normalize') ?? false;
    crossfadeDuration.value = prefs.getDouble('crossfade') ?? 0.0;
    pitchShift.value = prefs.getDouble('pitch') ?? 0.0;
    spatialAudio.value = prefs.getBool('spatial') ?? false;
    bassBoost.value = prefs.getInt('bassBoost') ?? 0;
    reverbPreset.value = prefs.getInt('reverb') ?? 0;
    playbackSpeed.value = prefs.getDouble('speed') ?? 1.0;
    equalizerEnabled.value = prefs.getBool('eqEnabled') ?? false;

    applyAll();
    LogService.log('AudioEffects', 'Initialized');
  }

  static void applyAll() {
    _applyNormalize(audioNormalize.value);
    _applyPitch(pitchShift.value);
    _applySpeed(playbackSpeed.value);
    AudioEngine.setBassBoost(bassBoost.value);
    AudioEngine.setReverb(reverbPreset.value);
    if (spatialAudio.value) {
      AudioEngine.setSpatialEnabled(true);
    }
    if (equalizerEnabled.value) {
      AudioEngine.equalizer?.setEnabled(true);
    }
  }

  // ── Gapless ────────────────────────────────────────────────────────────────

  static Future<void> setGapless(bool value) async {
    gaplessPlayback.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gapless', value);
    LogService.log('AudioEffects', 'Gapless: $value');
  }

  // ── Normalize (Loudness) ───────────────────────────────────────────────────

  static Future<void> setNormalize(bool value) async {
    audioNormalize.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('normalize', value);
    _applyNormalize(value);
    LogService.log('AudioEffects', 'Normalize: $value');
  }

  static void _applyNormalize(bool enabled) {
    final enhancer = AudioEngine.loudnessEnhancer;
    if (enhancer != null) {
      // AndroidLoudnessEnhancer: targetGain in dB millibels (0 = neutral,
      // negative = reduce, positive = boost).  For normalization we boost
      // quiet tracks slightly.
      enhancer.setEnabled(enabled);
      if (enabled) {
        enhancer.setTargetGain(300); // +3 dB gentle normalize
      } else {
        enhancer.setTargetGain(0);
      }
    } else {
      // Web / non-Android fallback: volume approximation
      try {
        AudioEngine.player.setVolume(enabled ? 0.88 : 1.0);
      } catch (_) {}
    }
  }

  // ── Equalizer ─────────────────────────────────────────────────────────────

  static Future<void> setEqualizerEnabled(bool value) async {
    equalizerEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('eqEnabled', value);
    try {
      await AudioEngine.equalizer?.setEnabled(value);
    } catch (_) {}
    LogService.log('AudioEffects', 'EQ enabled: $value');
  }

  static Future<AndroidEqualizerParameters?> getEqualizerParameters() async {
    try {
      return await AudioEngine.equalizer?.parameters;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setEqualizerBandGain(
      int bandIndex, double gainDb) async {
    try {
      final params = await AudioEngine.equalizer?.parameters;
      if (params == null) return;
      final band = params.bands[bandIndex];
      await band.setGain(gainDb);
      _saveEqBand(bandIndex, gainDb);
    } catch (e) {
      LogService.warn('AudioEffects', 'setEqBand: $e');
    }
  }

  /// Built-in EQ presets (gain in dB per band: 60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz).
  static const List<Map<String, dynamic>> eqPresets = [
    {'name': 'Normal',    'gains': [0.0, 0.0, 0.0, 0.0, 0.0]},
    {'name': 'Classical', 'gains': [5.0, 3.0, 0.0, 3.0, 4.0]},
    {'name': 'Dance',     'gains': [6.0, 0.0, 2.0, 4.0, 1.0]},
    {'name': 'Flat',      'gains': [0.0, 0.0, 0.0, 0.0, 0.0]},
    {'name': 'Folk',      'gains': [3.0, 0.0, 0.0, 2.0, -1.0]},
    {'name': 'Heavy Metal', 'gains': [4.0, 1.0, 9.0, 3.0, 0.0]},
    {'name': 'Hip-Hop',   'gains': [5.0, 4.0, 1.0, 1.0, 3.0]},
    {'name': 'Jazz',      'gains': [4.0, 2.0, -2.0, 2.0, 5.0]},
    {'name': 'Pop',       'gains': [-1.0, 2.0, 5.0, 1.0, -2.0]},
    {'name': 'Rock',      'gains': [5.0, 3.0, -1.0, 3.0, 5.0]},
  ];

  static Future<void> applyEqPreset(int presetIndex) async {
    if (presetIndex < 0 || presetIndex >= eqPresets.length) return;
    final gains = eqPresets[presetIndex]['gains'] as List<double>;
    final eq = AudioEngine.equalizer;
    if (eq == null) return;
    try {
      final params = await eq.parameters;
      for (var i = 0; i < params.bands.length && i < gains.length; i++) {
        final clamped = gains[i]
            .clamp(params.minDecibels, params.maxDecibels);
        await params.bands[i].setGain(clamped);
        _saveEqBand(i, clamped);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('eqPreset', presetIndex);
      LogService.log('AudioEffects', 'EQ preset: ${eqPresets[presetIndex]['name']}');
    } catch (e) {
      LogService.warn('AudioEffects', 'applyEqPreset: $e');
    }
  }

  static Future<void> restoreEqualizerBands() async {
    final prefs = await SharedPreferences.getInstance();
    final eq = AudioEngine.equalizer;
    if (eq == null) return;
    try {
      final params = await eq.parameters;
      for (var i = 0; i < params.bands.length; i++) {
        final gain = prefs.getDouble('eqBand_$i');
        if (gain != null) {
          await params.bands[i].setGain(gain);
        }
      }
    } catch (_) {}
  }

  static Future<void> _saveEqBand(int bandIndex, double gainDb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('eqBand_$bandIndex', gainDb);
  }

  // ── Crossfade ──────────────────────────────────────────────────────────────

  static Future<void> setCrossfade(double seconds) async {
    crossfadeDuration.value = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('crossfade', seconds);
    LogService.log('AudioEffects', 'Crossfade: ${seconds}s');
  }

  // ── Pitch Shift ───────────────────────────────────────────────────────────

  static Future<void> setPitch(double semitones) async {
    pitchShift.value = semitones;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pitch', semitones);
    _applyPitch(semitones);
    LogService.log('AudioEffects', 'Pitch: $semitones semitones');
  }

  static void _applyPitch(double semitones) {
    if (kIsWeb) return;
    try {
      final factor = math.pow(2.0, semitones / 12.0).toDouble();
      AudioEngine.player.setPitch(factor);
    } catch (_) {}
  }

  // ── Playback Speed ────────────────────────────────────────────────────────

  static Future<void> setSpeed(double speed) async {
    final clamped = speed.clamp(0.25, 3.0);
    playbackSpeed.value = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speed', clamped);
    _applySpeed(clamped);
    LogService.log('AudioEffects', 'Speed: ${clamped}x');
  }

  static void _applySpeed(double speed) {
    try {
      AudioEngine.player.setSpeed(speed);
    } catch (_) {}
  }

  // ── Bass Boost ────────────────────────────────────────────────────────────

  static Future<void> setBassBoost(int strength) async {
    bassBoost.value = strength.clamp(0, 1000);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bassBoost', bassBoost.value);
    await AudioEngine.setBassBoost(bassBoost.value);
    LogService.log('AudioEffects', 'BassBoost: ${bassBoost.value}');
  }

  // ── Reverb ────────────────────────────────────────────────────────────────

  static Future<void> setReverb(int preset) async {
    reverbPreset.value = preset.clamp(0, reverbPresetNames.length - 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reverb', reverbPreset.value);
    await AudioEngine.setReverb(reverbPreset.value);
    LogService.log(
        'AudioEffects', 'Reverb: ${reverbPresetNames[reverbPreset.value]}');
  }

  // ── Spatial Audio (Android Virtualizer) ──────────────────────────────────

  static Future<void> setSpatial(bool value) async {
    spatialAudio.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('spatial', value);
    await AudioEngine.setSpatialEnabled(value);
    LogService.log('AudioEffects', 'Spatial: $value');
  }
}
