part of '../audio_effects_service.dart';

/// Central DSP controller.
///
/// Feature map:
///   • LUFS loudness normalize → LoudnessAnalyzer + AndroidLoudnessEnhancer / volume
///   • Equalizer (room)     → AndroidEqualizer presets mapped to room acoustics
///   • Bass boost           → Android BassBoost native effect (both sessions)
///   • Reverb               → Android PresetReverb native effect (both sessions)
///   • Spatial audio        → Android Virtualizer native effect (both sessions)
///   • Pitch shift          → just_audio setPitch() on active player
///   • Playback speed       → just_audio setSpeed() on active player
///   • Crossfade            → CrossfadeController (dual-player volume automation)
///   • Gapless              → Preload on standby + instant swap (always active)
///   • Audio output mode    → AAudio / OpenSL ES / Hi-Res
class AudioEffectsService {
  AudioEffectsService._();

  // ── Value notifiers ────────────────────────────────────────────────────────

  static final ValueNotifier<bool>   gaplessPlayback  = ValueNotifier(true);
  static final ValueNotifier<bool>   audioNormalize   = ValueNotifier(false);
  static final ValueNotifier<double> crossfadeDuration= ValueNotifier(0.0);
  static final ValueNotifier<double> pitchShift       = ValueNotifier(0.0);
  static final ValueNotifier<bool>   spatialAudio     = ValueNotifier(false);
  static final ValueNotifier<int>    spatialStrength  = ValueNotifier(1000);
  static final ValueNotifier<int>    bassBoost        = ValueNotifier(0);
  static final ValueNotifier<int>    reverbPreset     = ValueNotifier(0);
  static final ValueNotifier<double> playbackSpeed    = ValueNotifier(1.0);
  static final ValueNotifier<bool>   equalizerEnabled = ValueNotifier(false);
  static final ValueNotifier<int>    roomPreset       = ValueNotifier(0);
  static final ValueNotifier<int>    audioOutputMode  = ValueNotifier(0);
  static final ValueNotifier<String> lyricsPath       = ValueNotifier('');

  // ── Reverb preset labels ───────────────────────────────────────────────────

  static const List<String> reverbPresetNames = [
    'Off', 'Small Room', 'Medium Room', 'Large Room',
    'Medium Hall', 'Large Hall', 'Plate',
  ];

  // ── Room acoustic presets ──────────────────────────────────────────────────

  static const List<Map<String, dynamic>> roomPresets = [
    {'name': 'Flat',        'reverb': 0, 'gains': <double>[0.0,  0.0,  0.0,  0.0,  0.0 ], 'desc': 'Tanpa efek ruangan'},
    {'name': 'Studio',      'reverb': 0, 'gains': <double>[2.0,  1.0,  0.0, -1.0,  1.0 ], 'desc': 'Rekaman studio profesional'},
    {'name': 'Live Stage',  'reverb': 3, 'gains': <double>[3.0,  0.0,  2.0,  1.0,  2.0 ], 'desc': 'Panggung pertunjukan langsung'},
    {'name': 'Concert Hall','reverb': 5, 'gains': <double>[4.0,  1.0, -1.0,  2.0,  4.0 ], 'desc': 'Aula konser klasik'},
    {'name': 'Cathedral',   'reverb': 6, 'gains': <double>[3.0,  0.0, -2.0,  0.0,  5.0 ], 'desc': 'Gema katedral besar'},
    {'name': 'Club',        'reverb': 2, 'gains': <double>[6.0,  3.0,  1.0,  0.0, -1.0 ], 'desc': 'Club malam dengan bass kuat'},
    {'name': 'Outdoor',     'reverb': 1, 'gains': <double>[1.0,  0.0,  0.0,  2.0,  3.0 ], 'desc': 'Ruang terbuka di luar ruangan'},
    {'name': 'Car',         'reverb': 1, 'gains': <double>[4.0,  2.0,  1.0, -1.0,  0.0 ], 'desc': 'Interior kabin mobil'},
    {'name': 'Bathroom',    'reverb': 2, 'gains': <double>[0.0,  1.0,  3.0,  2.0,  1.0 ], 'desc': 'Ruang kecil dengan dinding keras'},
  ];

  // ── Audio output labels ────────────────────────────────────────────────────

  static const List<String> audioOutputNames = [
    'Auto (AAudio)', 'OpenSL ES', 'Hi-Res Audio',
  ];

  static const List<String> audioOutputDesc = [
    'AAudio — jalur audio default, direkomendasikan untuk Android 8+',
    'OpenSL ES — kompatibel dengan semua versi Android',
    'Hi-Res Audio — aktifkan DAC Hi-Res/Hi-Fi hardware. '
        'Mendukung MIUI 12, Qualcomm, Sony, dan OEM lain. '
        'Perlu headset atau DAC hi-res terhubung.',
  ];

  // ── Init ───────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    gaplessPlayback.value   = prefs.getBool('gapless')         ?? true;
    audioNormalize.value    = prefs.getBool('normalize')        ?? false;
    crossfadeDuration.value = prefs.getDouble('crossfade')      ?? 0.0;
    pitchShift.value        = prefs.getDouble('pitch')          ?? 0.0;
    spatialAudio.value      = prefs.getBool('spatial')          ?? false;
    spatialStrength.value   = prefs.getInt('spatialStr')        ?? 1000;
    bassBoost.value         = prefs.getInt('bassBoost')         ?? 0;
    reverbPreset.value      = prefs.getInt('reverb')            ?? 0;
    playbackSpeed.value     = prefs.getDouble('speed')          ?? 1.0;
    equalizerEnabled.value  = prefs.getBool('eqEnabled')        ?? false;
    roomPreset.value        = prefs.getInt('roomPreset')        ?? 0;
    audioOutputMode.value   = prefs.getInt('audioOutputMode')   ?? 0;
    lyricsPath.value        = prefs.getString('lyricsPath')     ?? '';

    applyAll();
    LogService.log('AudioEffects', 'Initialized');
  }

  /// Apply all current settings to the active player's DSP chain.
  static void applyAll() {
    AudioEngine.applyNormalize(enabled: audioNormalize.value, targetGainMb: 0.0);
    _applyPitch(pitchShift.value);
    _applySpeed(playbackSpeed.value);
    AudioEngine.setBassBoost(bassBoost.value);
    AudioEngine.setReverb(reverbPreset.value);
    if (spatialAudio.value) {
      AudioEngine.setSpatialEnabled(true, strength: spatialStrength.value);
    }
    if (equalizerEnabled.value) {
      AudioEngine.equalizer?.setEnabled(true);
      _applyRoomPresetEq(roomPreset.value);
    }
  }

  /// Reapply pitch, speed, EQ, and normalization after a player handoff.
  /// EQ bands and LoudnessEnhancer live in each slot's DSP pipeline and
  /// persist across handoffs — only the player-level settings need refresh.
  static void reapplyToActivePlayer() {
    _applyPitch(pitchShift.value);
    _applySpeed(playbackSpeed.value);
    unawaited(AudioEngine.restoreEqBandsOnSlot(AudioEngine.activeSlot));
    AudioEngine.applyNormalizeToSlot(
      AudioEngine.activeSlot,
      enabled:      audioNormalize.value,
      targetGainMb: 0.0,
    );
  }

  // ── Gapless ────────────────────────────────────────────────────────────────

  static Future<void> setGapless(bool value) async {
    gaplessPlayback.value = value;
    await _saveBool('gapless', value);
    LogService.log('AudioEffects', 'Gapless: $value');
  }

  // ── Normalize (LUFS-based) ─────────────────────────────────────────────────

  static Future<void> setNormalize(bool value) async {
    audioNormalize.value = value;
    await _saveBool('normalize', value);
    // Base enable/disable on both slots; per-track LUFS gain is applied by
    // AudioService when a track starts or becomes active.
    AudioEngine.applyNormalize(enabled: value, targetGainMb: 0.0);
    LogService.log('AudioEffects', 'Normalize (LUFS): $value');
  }

  // ── Equalizer ─────────────────────────────────────────────────────────────

  static Future<void> setEqualizerEnabled(bool value) async {
    equalizerEnabled.value = value;
    await _saveBool('eqEnabled', value);
    try {
      await AudioEngine.equalizer?.setEnabled(value);
      if (value) _applyRoomPresetEq(roomPreset.value);
    } catch (e) {
      LogService.warn('AudioEffects', 'setEqEnabled: $e');
    }
    LogService.log('AudioEffects', 'EQ enabled: $value');
  }

  static Future<AndroidEqualizerParameters?> getEqualizerParameters() async {
    try {
      return await AudioEngine.equalizer?.parameters;
    } catch (e) {
      LogService.warn('AudioEffects', 'getEqParameters: $e');
      return null;
    }
  }

  static Future<void> setEqualizerBandGain(int bandIndex, double gainDb) async {
    try {
      final params = await AudioEngine.equalizer?.parameters;
      if (params == null) return;
      await params.bands[bandIndex].setGain(gainDb);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('eqBand_$bandIndex', gainDb);
    } catch (e) {
      LogService.warn('AudioEffects', 'setEqBand: $e');
    }
  }

  // ── Room Presets ──────────────────────────────────────────────────────────

  static Future<void> setRoomPreset(int index) async {
    final i = index.clamp(0, roomPresets.length - 1);
    roomPreset.value = i;
    await _saveInt('roomPreset', i);
    final preset = roomPresets[i];
    await setReverb(preset['reverb'] as int);
    if (equalizerEnabled.value) _applyRoomPresetEq(i);
    LogService.log('AudioEffects', 'Room preset: ${preset['name']}');
  }

  static Future<void> _applyRoomPresetEq(int index) async {
    final i     = index.clamp(0, roomPresets.length - 1);
    final gains = roomPresets[i]['gains'] as List<double>;
    final eq    = AudioEngine.equalizer;
    if (eq == null) return;
    try {
      final params = await eq.parameters;
      for (var b = 0; b < params.bands.length && b < gains.length; b++) {
        final clamped = gains[b].clamp(params.minDecibels, params.maxDecibels).toDouble();
        await params.bands[b].setGain(clamped);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('eqBand_$b', clamped);
      }
    } catch (e) {
      LogService.warn('AudioEffects', 'applyRoomPresetEq: $e');
    }
  }

  static Future<void> restoreEqualizerBands() async {
    await AudioEngine.restoreEqBandsOnSlot(AudioEngine.activeSlot);
  }

  static const List<Map<String, dynamic>> eqPresets = [
    {'name': 'Normal',      'gains': <double>[0.0,  0.0,  0.0, 0.0,  0.0 ]},
    {'name': 'Classical',   'gains': <double>[5.0,  3.0,  0.0, 3.0,  4.0 ]},
    {'name': 'Dance',       'gains': <double>[6.0,  0.0,  2.0, 4.0,  1.0 ]},
    {'name': 'Flat',        'gains': <double>[0.0,  0.0,  0.0, 0.0,  0.0 ]},
    {'name': 'Folk',        'gains': <double>[3.0,  0.0,  0.0, 2.0, -1.0 ]},
    {'name': 'Heavy Metal', 'gains': <double>[4.0,  1.0,  9.0, 3.0,  0.0 ]},
    {'name': 'Hip-Hop',     'gains': <double>[5.0,  4.0,  1.0, 1.0,  3.0 ]},
    {'name': 'Jazz',        'gains': <double>[4.0,  2.0, -2.0, 2.0,  5.0 ]},
    {'name': 'Pop',         'gains': <double>[-1.0, 2.0,  5.0, 1.0, -2.0 ]},
    {'name': 'Rock',        'gains': <double>[5.0,  3.0, -1.0, 3.0,  5.0 ]},
  ];

  static Future<void> applyEqPreset(int presetIndex) async {
    if (presetIndex < 0 || presetIndex >= eqPresets.length) return;
    final gains = eqPresets[presetIndex]['gains'] as List<double>;
    final eq    = AudioEngine.equalizer;
    if (eq == null) return;
    try {
      final params = await eq.parameters;
      for (var i = 0; i < params.bands.length && i < gains.length; i++) {
        final clamped = gains[i].clamp(params.minDecibels, params.maxDecibels).toDouble();
        await params.bands[i].setGain(clamped);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('eqBand_$i', clamped);
      }
      await _saveInt('eqPreset', presetIndex);
    } catch (e) {
      LogService.warn('AudioEffects', 'applyEqPreset: $e');
    }
  }

  // ── Crossfade ──────────────────────────────────────────────────────────────

  static Future<void> setCrossfade(double seconds) async {
    crossfadeDuration.value = seconds;
    await _saveDouble('crossfade', seconds);
    LogService.log('AudioEffects', 'Crossfade: ${seconds}s');
  }

  // ── Pitch Shift ───────────────────────────────────────────────────────────

  static Future<void> setPitch(double semitones) async {
    pitchShift.value = semitones;
    await _saveDouble('pitch', semitones);
    _applyPitch(semitones);
    LogService.log('AudioEffects', 'Pitch: $semitones semitones');
  }

  static void _applyPitch(double semitones) {
    if (kIsWeb) return;
    try {
      final factor = math.pow(2.0, semitones / 12.0).toDouble();
      AudioEngine.activePlayer.setPitch(factor);
    } catch (e) {
      LogService.warn('AudioEffects', 'applyPitch: $e');
    }
  }

  // ── Playback Speed ────────────────────────────────────────────────────────

  static Future<void> setSpeed(double speed) async {
    final v = speed.clamp(0.25, 3.0).toDouble();
    playbackSpeed.value = v;
    await _saveDouble('speed', v);
    _applySpeed(v);
    LogService.log('AudioEffects', 'Speed: ${v}x');
  }

  static void _applySpeed(double speed) {
    try {
      AudioEngine.activePlayer.setSpeed(speed);
    } catch (e) {
      LogService.warn('AudioEffects', 'applySpeed: $e');
    }
  }

  // ── Bass Boost ────────────────────────────────────────────────────────────

  static Future<void> setBassBoost(int strength) async {
    bassBoost.value = strength.clamp(0, 1000);
    await _saveInt('bassBoost', bassBoost.value);
    await AudioEngine.setBassBoost(bassBoost.value);
    LogService.log('AudioEffects', 'BassBoost: ${bassBoost.value}');
  }

  // ── Reverb ────────────────────────────────────────────────────────────────

  static Future<void> setReverb(int preset) async {
    reverbPreset.value = preset.clamp(0, reverbPresetNames.length - 1);
    await _saveInt('reverb', reverbPreset.value);
    await AudioEngine.setReverb(reverbPreset.value);
    LogService.log('AudioEffects', 'Reverb: ${reverbPresetNames[reverbPreset.value]}');
  }

  // ── Spatial Audio ─────────────────────────────────────────────────────────

  static Future<void> setSpatial(bool value) async {
    spatialAudio.value = value;
    await _saveBool('spatial', value);
    await AudioEngine.setSpatialEnabled(value, strength: spatialStrength.value);
    LogService.log('AudioEffects', 'Spatial: $value');
  }

  static Future<void> setSpatialStrength(int strength) async {
    final v = strength.clamp(0, 1000);
    spatialStrength.value = v;
    await _saveInt('spatialStr', v);
    if (spatialAudio.value) {
      await AudioEngine.setSpatialEnabled(true, strength: v);
    }
    LogService.log('AudioEffects', 'Spatial strength: $v');
  }

  // ── Audio Output ──────────────────────────────────────────────────────────

  static Future<void> setAudioOutputMode(int modeIndex) async {
    final idx = modeIndex.clamp(0, 2);
    audioOutputMode.value = idx;
    await _saveInt('audioOutputMode', idx);
    await AudioEngine.setAudioOutputMode(AudioOutputMode.values[idx]);
    LogService.log('AudioEffects', 'AudioOutput: ${audioOutputNames[idx]}');
  }

  // ── Lyrics path ───────────────────────────────────────────────────────────

  static Future<void> setLyricsPath(String path) async {
    lyricsPath.value = path.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lyricsPath', path.trim());
    LogService.log('AudioEffects', 'Lyrics path: ${path.trim()}');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<void> _saveBool(String k, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(k, v);
  }

  static Future<void> _saveInt(String k, int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(k, v);
  }

  static Future<void> _saveDouble(String k, double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(k, v);
  }
}
