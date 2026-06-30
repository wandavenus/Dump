part of '../audio_effects_service.dart';

/// Central DSP settings controller — UI + state only.
///
/// All audio processing (EQ, bass, reverb, spatial, speed, pitch, crossfade,
/// loudness, ReplayGain) runs natively inside `Media3PlaybackService.kt`.
/// This class manages:
///   • [ValueNotifier]s for each setting (UI binds to these)
///   • [SharedPreferences] persistence
///   • Forwarding setting changes to the active engine via [AudioEngineManager]
///
/// No layer in this file may reference [Media3PlaybackBridge] directly.
/// All engine calls go through [AudioEngineManager].
class AudioEffectsService {
  AudioEffectsService._();

  // ── Value notifiers ────────────────────────────────────────────────────────

  static final ValueNotifier<bool> audioNormalize = ValueNotifier(false);
  static final ValueNotifier<ReplayGainMode> replayGainMode = ValueNotifier(
    ReplayGainMode.off,
  );
  static final ValueNotifier<double> replayGainPreamp = ValueNotifier(0.0);
  static final ValueNotifier<double> crossfadeDuration = ValueNotifier(0.0);
  static final ValueNotifier<double> pitchShift = ValueNotifier(0.0);
  static final ValueNotifier<bool> spatialAudio = ValueNotifier(false);
  static final ValueNotifier<int> spatialStrength = ValueNotifier(1000);
  static final ValueNotifier<int> bassBoost = ValueNotifier(0);
  static final ValueNotifier<int> reverbPreset = ValueNotifier(0);
  static final ValueNotifier<double> playbackSpeed = ValueNotifier(1.0);
  static final ValueNotifier<bool> equalizerEnabled = ValueNotifier(false);
  static final ValueNotifier<int> roomPreset = ValueNotifier(0);

  /// Index preset EQ yang terakhir diterapkan via [applyEqPreset].
  /// -1 berarti tidak ada preset aktif (gains diatur manual / belum di-init).
  static final ValueNotifier<int> eqPreset = ValueNotifier(-1);

  static final ValueNotifier<String> lyricsPath = ValueNotifier('');

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

  // ── Room acoustic presets ──────────────────────────────────────────────────
  // {name, reverb (0-6), eq gains [60Hz,230Hz,910Hz,3.6k,14k], description}

  static const List<Map<String, dynamic>> roomPresets = [
    {
      'name': 'Flat',
      'reverb': 0,
      'gains': [0.0, 0.0, 0.0, 0.0, 0.0],
      'desc': 'Tanpa efek ruangan',
    },
    {
      'name': 'Studio',
      'reverb': 0,
      'gains': [2.0, 1.0, 0.0, -1.0, 1.0],
      'desc': 'Rekaman studio profesional',
    },
    {
      'name': 'Live Stage',
      'reverb': 3,
      'gains': [3.0, 0.0, 2.0, 1.0, 2.0],
      'desc': 'Panggung pertunjukan langsung',
    },
    {
      'name': 'Concert Hall',
      'reverb': 5,
      'gains': [4.0, 1.0, -1.0, 2.0, 4.0],
      'desc': 'Aula konser klasik',
    },
    {
      'name': 'Cathedral',
      'reverb': 6,
      'gains': [3.0, 0.0, -2.0, 0.0, 5.0],
      'desc': 'Gema katedral besar',
    },
    {
      'name': 'Club',
      'reverb': 2,
      'gains': [6.0, 3.0, 1.0, 0.0, -1.0],
      'desc': 'Club malam dengan bass kuat',
    },
    {
      'name': 'Outdoor',
      'reverb': 1,
      'gains': [1.0, 0.0, 0.0, 2.0, 3.0],
      'desc': 'Ruang terbuka di luar ruangan',
    },
    {
      'name': 'Car',
      'reverb': 1,
      'gains': [4.0, 2.0, 1.0, -1.0, 0.0],
      'desc': 'Interior kabin mobil',
    },
    {
      'name': 'Bathroom',
      'reverb': 2,
      'gains': [0.0, 1.0, 3.0, 2.0, 1.0],
      'desc': 'Ruang kecil dengan dinding keras',
    },
  ];

  // ── Init ───────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    audioNormalize.value = prefs.getBool('normalize') ?? false;
    crossfadeDuration.value = prefs.getDouble('crossfade') ?? 0.0;
    pitchShift.value = prefs.getDouble('pitch') ?? 0.0;
    spatialAudio.value = prefs.getBool('spatial') ?? false;
    spatialStrength.value = prefs.getInt('spatialStr') ?? 1000;
    bassBoost.value = prefs.getInt('bassBoost') ?? 0;
    reverbPreset.value = prefs.getInt('reverb') ?? 0;
    playbackSpeed.value = prefs.getDouble('speed') ?? 1.0;
    equalizerEnabled.value = prefs.getBool('eqEnabled') ?? false;
    roomPreset.value = prefs.getInt('roomPreset') ?? 0;
    eqPreset.value = prefs.getInt('eqPreset') ?? -1;
    lyricsPath.value = prefs.getString('lyricsPath') ?? '';

    final rgIdx = prefs.getInt('replayGainMode') ?? 0;
    replayGainMode.value =
        ReplayGainMode.values[rgIdx.clamp(0, ReplayGainMode.values.length - 1)];
    replayGainPreamp.value = prefs.getDouble('replayGainPreamp') ?? 0.0;

    // Registrasi applyAll sebagai post-switch callback di AudioEngineManager.
    // Setiap kali engine diganti, AudioEngineManager akan memanggil applyAll()
    // agar pengaturan DSP (speed, pitch, EQ, bass, reverb, dll.) dikirim ulang
    // ke engine baru. Pola callback dipakai untuk menghindari circular import.
    AudioEngineManager.registerPostSwitchCallback(applyAll);

    applyAll();
    LogService.log('AudioEffects', 'Initialized');
  }

  // ── applyAll — send every setting to the active engine in one burst ────────

  static void applyAll() {
    if (kIsWeb) return;

    // Speed & pitch — routed through AudioEngineManager → active engine
    _sendSpeed(playbackSpeed.value);
    _sendPitch(pitchShift.value);

    // Bass boost
    unawaited(AudioEngineManager.setBassBoost(bassBoost.value));
    unawaited(AudioEngineManager.setBassBoostEnabled(bassBoost.value > 0));

    // Virtualizer / spatial
    unawaited(AudioEngineManager.setVirtualizerStrength(spatialStrength.value));
    unawaited(AudioEngineManager.setVirtualizerEnabled(spatialAudio.value));

    // Reverb
    unawaited(AudioEngineManager.setReverbPreset(reverbPreset.value));

    // Equalizer
    unawaited(AudioEngineManager.setEqualizerEnabled(equalizerEnabled.value));
    if (equalizerEnabled.value) _sendRoomPresetEq(roomPreset.value);

    // Loudness normalize (when ReplayGain is off)
    if (replayGainMode.value == ReplayGainMode.off) {
      unawaited(AudioEngineManager.setLoudnessEnabled(audioNormalize.value));
      if (!audioNormalize.value) {
        unawaited(AudioEngineManager.setLoudnessTargetGain(0));
      }
    }

    // Crossfade
    unawaited(AudioEngineManager.setCrossfadeDuration(crossfadeDuration.value));
  }

  // ── Normalize ─────────────────────────────────────────────────────────────

  static Future<void> setNormalize(bool value) async {
    audioNormalize.value = value;
    await _saveBool('normalize', value);
    if (replayGainMode.value == ReplayGainMode.off) {
      unawaited(AudioEngineManager.setLoudnessEnabled(value));
      if (!value) unawaited(AudioEngineManager.setLoudnessTargetGain(0));
    }
    LogService.log('AudioEffects', 'Normalize: $value');
  }

  // ── ReplayGain ────────────────────────────────────────────────────────────

  static Future<void> setReplayGainMode(ReplayGainMode mode) async {
    replayGainMode.value = mode;
    await _saveInt('replayGainMode', mode.index);
    LogService.log('AudioEffects', 'ReplayGain mode: ${mode.name}');
  }

  static Future<void> setReplayGainPreamp(double db) async {
    final v = db.clamp(-15.0, 15.0);
    replayGainPreamp.value = v;
    await _saveDouble('replayGainPreamp', v);
    LogService.log('AudioEffects', 'ReplayGain preamp: $v dB');
  }

  // ── Equalizer ─────────────────────────────────────────────────────────────

  static Future<void> setEqualizerEnabled(bool value) async {
    equalizerEnabled.value = value;
    await _saveBool('eqEnabled', value);
    unawaited(AudioEngineManager.setEqualizerEnabled(value));
    if (value) _sendRoomPresetEq(roomPreset.value);
    LogService.log('AudioEffects', 'EQ enabled: $value');
  }

  /// Returns engine-agnostic EQ parameters, or null if the active engine
  /// does not support a hardware/software equalizer.
  static Future<EngineEqualizerParameters?> getEqualizerParameters() async {
    try {
      return await AudioEngineManager.getEqualizerParameters();
    } catch (error) {
      LogService.warn('AudioEffects', 'getEqParameters: $error');
      return null;
    }
  }

  static Future<void> setEqualizerBandGain(int bandIndex, double gainDb) async {
    try {
      unawaited(AudioEngineManager.setEqualizerBandGain(bandIndex, gainDb));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('eqBand_$bandIndex', gainDb);
      // Manual band adjustment — clear preset selection indicator.
      eqPreset.value = -1;
    } catch (e) {
      LogService.warn('AudioEffects', 'setEqBand: $e');
    }
  }

  // ── Room Presets ──────────────────────────────────────────────────────────

  static Future<void> setRoomPreset(int index) async {
    final i = index.clamp(0, roomPresets.length - 1).toInt();
    roomPreset.value = i;
    await _saveInt('roomPreset', i);

    final preset = roomPresets[i];
    final rev = preset['reverb'] as int;
    await setReverb(rev);
    if (equalizerEnabled.value) _sendRoomPresetEq(i);

    LogService.log('AudioEffects', 'Room preset: ${preset['name']}');
  }

  static void _sendRoomPresetEq(int index) {
    final i = index.clamp(0, roomPresets.length - 1).toInt();
    final gains = roomPresets[i]['gains'] as List<double>;
    for (var b = 0; b < gains.length; b++) {
      unawaited(AudioEngineManager.setEqualizerBandGain(b, gains[b]));
    }
    SharedPreferences.getInstance().then((prefs) {
      for (var b = 0; b < gains.length; b++) {
        prefs.setDouble('eqBand_$b', gains[b]);
      }
    });
  }

  static Future<void> restoreEqualizerBands() async {
    final prefs = await SharedPreferences.getInstance();
    final params = await getEqualizerParameters();
    if (params == null) return;
    for (var i = 0; i < params.bandCount; i++) {
      final gain = prefs.getDouble('eqBand_$i');
      if (gain != null) {
        unawaited(AudioEngineManager.setEqualizerBandGain(i, gain));
      }
    }
  }

  // Legacy EQ presets kept for backward compat
  static const List<Map<String, dynamic>> eqPresets = [
    {
      'name': 'Normal',
      'gains': [0.0, 0.0, 0.0, 0.0, 0.0],
    },
    {
      'name': 'Classical',
      'gains': [5.0, 3.0, 0.0, 3.0, 4.0],
    },
    {
      'name': 'Dance',
      'gains': [6.0, 0.0, 2.0, 4.0, 1.0],
    },
    {
      'name': 'Flat',
      'gains': [0.0, 0.0, 0.0, 0.0, 0.0],
    },
    {
      'name': 'Folk',
      'gains': [3.0, 0.0, 0.0, 2.0, -1.0],
    },
    {
      'name': 'Heavy Metal',
      'gains': [4.0, 1.0, 9.0, 3.0, 0.0],
    },
    {
      'name': 'Hip-Hop',
      'gains': [5.0, 4.0, 1.0, 1.0, 3.0],
    },
    {
      'name': 'Jazz',
      'gains': [4.0, 2.0, -2.0, 2.0, 5.0],
    },
    {
      'name': 'Pop',
      'gains': [-1.0, 2.0, 5.0, 1.0, -2.0],
    },
    {
      'name': 'Rock',
      'gains': [5.0, 3.0, -1.0, 3.0, 5.0],
    },
  ];

  static Future<void> applyEqPreset(int presetIndex) async {
    if (presetIndex < 0 || presetIndex >= eqPresets.length) return;
    final gains = eqPresets[presetIndex]['gains'] as List<double>;

    // Update notifier BEFORE async work so UI updates immediately.
    eqPreset.value = presetIndex;
    await _saveInt('eqPreset', presetIndex);

    // Send gains to native; use engine params for band count + clamp range.
    final params = await getEqualizerParameters();
    final prefs = await SharedPreferences.getInstance();
    final bandCount = params?.bandCount ?? gains.length;
    final lo = params?.minDecibels ?? -15.0;
    final hi = params?.maxDecibels ?? 15.0;
    for (var i = 0; i < bandCount && i < gains.length; i++) {
      final clamped = gains[i].clamp(lo, hi).toDouble();
      unawaited(AudioEngineManager.setEqualizerBandGain(i, clamped));
      await prefs.setDouble('eqBand_$i', clamped);
    }
    LogService.log(
      'AudioEffects',
      'EQ preset: ${eqPresets[presetIndex]['name']}',
    );
  }

  // ── Crossfade ──────────────────────────────────────────────────────────────

  static Future<void> setCrossfade(double seconds) async {
    crossfadeDuration.value = seconds;
    await _saveDouble('crossfade', seconds);
    unawaited(AudioEngineManager.setCrossfadeDuration(seconds));
    LogService.log('AudioEffects', 'Crossfade: ${seconds}s');
  }

  // ── Pitch Shift ───────────────────────────────────────────────────────────

  static Future<void> setPitch(double semitones) async {
    pitchShift.value = semitones;
    await _saveDouble('pitch', semitones);
    _sendPitch(semitones);
    LogService.log('AudioEffects', 'Pitch: $semitones semitones');
  }

  /// Converts semitone offset to a pitch factor and forwards to the active engine.
  static void _sendPitch(double semitones) {
    if (kIsWeb) return;
    final factor = math.pow(2.0, semitones / 12.0).toDouble();
    unawaited(AudioEngineManager.setPitch(factor));
  }

  // ── Playback Speed ────────────────────────────────────────────────────────

  static Future<void> setSpeed(double speed) async {
    final v = speed.clamp(0.25, 3.0).toDouble();
    playbackSpeed.value = v;
    await _saveDouble('speed', v);
    _sendSpeed(v);
    LogService.log('AudioEffects', 'Speed: ${v}x');
  }

  static void _sendSpeed(double speed) {
    if (kIsWeb) return;
    unawaited(AudioEngineManager.setSpeed(speed));
  }

  // ── Bass Boost ────────────────────────────────────────────────────────────

  static Future<void> setBassBoost(int strength) async {
    final v = strength.clamp(0, 1000).toInt();
    bassBoost.value = v;
    await _saveInt('bassBoost', v);
    unawaited(AudioEngineManager.setBassBoost(v));
    unawaited(AudioEngineManager.setBassBoostEnabled(v > 0));
    LogService.log('AudioEffects', 'BassBoost: $v');
  }

  // ── Reverb ────────────────────────────────────────────────────────────────

  static Future<void> setReverb(int preset) async {
    final v = preset.clamp(0, reverbPresetNames.length - 1).toInt();
    reverbPreset.value = v;
    await _saveInt('reverb', v);
    unawaited(AudioEngineManager.setReverbPreset(v));
    LogService.log('AudioEffects', 'Reverb: ${reverbPresetNames[v]}');
  }

  // ── Spatial Audio ─────────────────────────────────────────────────────────

  static Future<void> setSpatial(bool value) async {
    spatialAudio.value = value;
    await _saveBool('spatial', value);
    unawaited(AudioEngineManager.setVirtualizerEnabled(value));
    LogService.log('AudioEffects', 'Spatial: $value');
  }

  static Future<void> setSpatialStrength(int strength) async {
    final v = strength.clamp(0, 1000).toInt();
    spatialStrength.value = v;
    await _saveInt('spatialStr', v);
    unawaited(AudioEngineManager.setVirtualizerStrength(v));
    if (spatialAudio.value) {
      unawaited(AudioEngineManager.setVirtualizerEnabled(true));
    }
    LogService.log('AudioEffects', 'Spatial strength: $v');
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
