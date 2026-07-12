part of '../audio_effects_service.dart';

/// Central DSP settings controller — UI + state only.
///
/// All audio processing (EQ, bass, spatial, speed, pitch, crossfade,
/// loudness, ReplayGain) runs natively inside `Media3PlaybackService.kt`.
/// This class manages:
///   • [ValueNotifier]s for each setting (UI binds to these)
///   • [SharedPreferences] persistence
///   • Forwarding setting changes to the native engine via [PlaybackManager]
///
/// No layer in this file may reference [Media3PlaybackBridge] directly.
/// All engine calls go through [PlaybackManager].

class AudioEffectsService {
  AudioEffectsService._();

  // ── Value notifiers ────────────────────────────────────────────────────────

  static final ValueNotifier<ReplayGainMode> replayGainMode =
      ValueNotifier(ReplayGainMode.off);
  static final ValueNotifier<double> replayGainPreamp = ValueNotifier(0.0);

  /// Clipping protection — caps effective ReplayGain so that
  /// `gain_linear × peak_linear ≤ 1.0`, preventing digital clipping.
  /// Uses peak metadata when available; no-op when peak is absent.
  static final ValueNotifier<bool> clippingProtection = ValueNotifier(true);

  // ── Loudness Normalization (Phase 8.5) ─────────────────────────────────────

  /// Whether real-time EBU R128 loudness normalization is enabled.
  static final ValueNotifier<bool> loudnessNormEnabled = ValueNotifier(false);

  /// Target loudness level in LUFS for the normalization engine.
  /// Typical: −23.0 (EBU R128 broadcast), −16.0 (podcast), −14.0 (streaming).
  static final ValueNotifier<double> loudnessNormTarget = ValueNotifier(-23.0);

  static final ValueNotifier<double> crossfadeDuration = ValueNotifier(0.0);
  static final ValueNotifier<double> pitchShift = ValueNotifier(0.0);
  static final ValueNotifier<bool> spatialAudio = ValueNotifier(false);
  static final ValueNotifier<int> spatialStrength = ValueNotifier(1000);
  static final ValueNotifier<int> bassBoost = ValueNotifier(0);
  static final ValueNotifier<double> playbackSpeed = ValueNotifier(1.0);
  static final ValueNotifier<bool> equalizerEnabled = ValueNotifier(false);
  static final ValueNotifier<int> roomPreset = ValueNotifier(0);

  /// Index preset EQ yang terakhir diterapkan via [applyEqPreset].
  /// -1 berarti tidak ada preset aktif (gains diatur manual / belum di-init).
  static final ValueNotifier<int> eqPreset = ValueNotifier(-1);

  static final ValueNotifier<String> lyricsPath = ValueNotifier('');

  // ── Room acoustic presets ──────────────────────────────────────────────────
  // {name, eq gains [60Hz,230Hz,910Hz,3.6k,14k], description}

  static const List<Map<String, dynamic>> roomPresets = [
    {
      'name': 'Flat',
      'gains': [0.0, 0.0, 0.0, 0.0, 0.0],
      'desc': 'Tanpa efek ruangan',
    },
    {
      'name': 'Studio',
      'gains': [2.0, 1.0, 0.0, -1.0, 1.0],
      'desc': 'Rekaman studio profesional',
    },
    {
      'name': 'Live Stage',
      'gains': [3.0, 0.0, 2.0, 1.0, 2.0],
      'desc': 'Panggung pertunjukan langsung',
    },
    {
      'name': 'Concert Hall',
      'gains': [4.0, 1.0, -1.0, 2.0, 4.0],
      'desc': 'Aula konser klasik',
    },
    {
      'name': 'Cathedral',
      'gains': [3.0, 0.0, -2.0, 0.0, 5.0],
      'desc': 'Gema katedral besar',
    },
    {
      'name': 'Club',
      'gains': [6.0, 3.0, 1.0, 0.0, -1.0],
      'desc': 'Club malam dengan bass kuat',
    },
    {
      'name': 'Outdoor',
      'gains': [1.0, 0.0, 0.0, 2.0, 3.0],
      'desc': 'Ruang terbuka di luar ruangan',
    },
    {
      'name': 'Car',
      'gains': [4.0, 2.0, 1.0, -1.0, 0.0],
      'desc': 'Interior kabin mobil',
    },
    {
      'name': 'Bathroom',
      'gains': [0.0, 1.0, 3.0, 2.0, 1.0],
      'desc': 'Ruang kecil dengan dinding keras',
    },
  ];

  // ── Init ───────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    crossfadeDuration.value = prefs.getDouble('crossfade')    ?? 0.0;
    pitchShift.value       = prefs.getDouble('pitch')         ?? 0.0;
    spatialAudio.value     = prefs.getBool('spatial')         ?? false;
    spatialStrength.value  = prefs.getInt('spatialStr')       ?? 1000;
    bassBoost.value        = prefs.getInt('bassBoost')        ?? 0;
    playbackSpeed.value    = prefs.getDouble('speed')         ?? 1.0;
    equalizerEnabled.value = prefs.getBool('eqEnabled')       ?? false;
    roomPreset.value       = prefs.getInt('roomPreset')       ?? 0;
    eqPreset.value         = prefs.getInt('eqPreset')         ?? -1;
    lyricsPath.value       = prefs.getString('lyricsPath')    ?? '';

    final rgIdx = prefs.getInt('replayGainMode') ?? 0;
    replayGainMode.value =
        ReplayGainMode.values[rgIdx.clamp(0, ReplayGainMode.values.length - 1)];
    replayGainPreamp.value    = prefs.getDouble('replayGainPreamp') ?? 0.0;
    clippingProtection.value  = prefs.getBool('rgClipProtect')      ?? true;
    loudnessNormEnabled.value = prefs.getBool('lnEnabled')          ?? false;
    loudnessNormTarget.value  = prefs.getDouble('lnTarget')         ?? -23.0;

    applyAll();
    LogService.log('AudioEffects', 'Initialized');
  }

  // ── applyAll — send every setting to the active engine in one burst ────────

  static void applyAll() {
    if (kIsWeb) return;
    unawaited(_pushEngineSettingsWhenReady());
  }

  // Cold-start race fix: on a fresh install `Media3PlaybackService` does not
  // exist yet — it is only created on-demand by the user's first "play" /
  // "setQueue" call (see MainActivity's `needsService` allowlist; anything
  // else must not force-start it, or a queueless cold start hits the
  // startForeground() deadline crash). `applyAll()` used to push every
  // setting immediately and unconditionally at Dart startup, so on a fresh
  // install this was the very first call into `musicplayer/media3_playback`
  // — racing `Media3PlaybackService.onCreate()` and hitting
  // `PlatformException(not_ready)` once `_invoke`'s retry/backoff window
  // (~3 s) ran out. Waiting for the real readiness signal here — instead of
  // retrying/ignoring the failure — means these calls simply run once the
  // service has actually finished wiring, however long that takes.
  static Future<void> _pushEngineSettingsWhenReady() async {
    await PlaybackManager.waitForServiceReady();

    // Speed & pitch
    _sendSpeed(playbackSpeed.value);
    _sendPitch(pitchShift.value);

    // Bass boost
    unawaited(PlaybackManager.setBassBoost(bassBoost.value));
    unawaited(PlaybackManager.setBassBoostEnabled(bassBoost.value > 0));

    // Virtualizer / spatial
    unawaited(PlaybackManager.setVirtualizerStrength(spatialStrength.value));
    unawaited(PlaybackManager.setVirtualizerEnabled(spatialAudio.value));

    // Equalizer
    unawaited(PlaybackManager.setEqualizerEnabled(equalizerEnabled.value));
    if (equalizerEnabled.value) _sendRoomPresetEq(roomPreset.value);

    // Crossfade
    unawaited(PlaybackManager.setCrossfadeDuration(crossfadeDuration.value));
  }

  // ── ReplayGain (Audio Normalize) ───────────────────────────────────────────

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

  static Future<void> setClippingProtection(bool enabled) async {
    clippingProtection.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rgClipProtect', enabled);
    LogService.log('AudioEffects', 'Clipping protection: $enabled');
  }

  // ── Loudness Normalization (Phase 8.5) ─────────────────────────────────────

  static Future<void> setLoudnessNormEnabled(bool enabled) async {
    loudnessNormEnabled.value = enabled;
    await _saveBool('lnEnabled', enabled);
    PlaybackManager.setNativeLoudnessNormBypass(!enabled);
    if (!enabled) {
      PlaybackManager.resetNativeLoudnessNorm();
    } else {
      // Mutual exclusion: system LoudnessEnhancer (AudioFlinger layer) and
      // native EBU R128 normalization (ExoPlayer audio processor layer) both
      // apply gain in the same signal path, in series.  Having both active
      // simultaneously causes double-boosting and potential clipping.
      // Disable the system LoudnessEnhancer when native normalization is on.
      unawaited(PlaybackManager.setLoudnessEnabled(false));
      unawaited(PlaybackManager.setLoudnessTargetGain(0.0));
      LogService.log(
        'AudioEffects',
        'System LoudnessEnhancer disabled — native Loudness Norm is now active',
      );
    }
    LogService.log('AudioEffects', 'Loudness Norm: ${enabled ? 'ON' : 'OFF'}');
  }

  static Future<void> setLoudnessNormTarget(double lufs) async {
    final v = lufs.clamp(-36.0, -6.0);
    loudnessNormTarget.value = v;
    await _saveDouble('lnTarget', v);
    PlaybackManager.setNativeLoudnessNormTargetLufs(v);
    LogService.log('AudioEffects', 'Loudness target: ${v.toStringAsFixed(1)} LUFS');
  }

  // ── Equalizer ─────────────────────────────────────────────────────────────

  static Future<void> setEqualizerEnabled(bool value) async {
    equalizerEnabled.value = value;
    await _saveBool('eqEnabled', value);
    unawaited(PlaybackManager.setEqualizerEnabled(value));
    if (value) _sendRoomPresetEq(roomPreset.value);
    LogService.log('AudioEffects', 'EQ enabled: $value');
  }

  /// Returns engine-agnostic EQ parameters, or null if the active engine
  /// does not support a hardware/software equalizer.
  static Future<EqualizerParameters?> getEqualizerParameters() async {
    try {
      return await PlaybackManager.getEqualizerParameters();
    } catch (error) {
      LogService.warn('AudioEffects', 'getEqParameters: $error');
      return null;
    }
  }

  static Future<void> setEqualizerBandGain(int bandIndex, double gainDb) async {
    try {
      unawaited(PlaybackManager.setEqualizerBandGain(bandIndex, gainDb));
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
    if (equalizerEnabled.value) _sendRoomPresetEq(i);

    LogService.log('AudioEffects', 'Room preset: ${preset['name']}');
  }

  static void _sendRoomPresetEq(int index) {
    final i = index.clamp(0, roomPresets.length - 1).toInt();
    final gains = roomPresets[i]['gains'] as List<double>;
    for (var b = 0; b < gains.length; b++) {
      unawaited(PlaybackManager.setEqualizerBandGain(b, gains[b]));
    }
    SharedPreferences.getInstance().then((prefs) {
      for (var b = 0; b < gains.length; b++) {
        prefs.setDouble('eqBand_$b', gains[b]);
      }
    });
  }

  static Future<void> restoreEqualizerBands() async {
    final prefs  = await SharedPreferences.getInstance();
    final params = await getEqualizerParameters();
    if (params == null) return;
    for (var i = 0; i < params.bandCount; i++) {
      final gain = prefs.getDouble('eqBand_$i');
      if (gain != null) {
        unawaited(PlaybackManager.setEqualizerBandGain(i, gain));
      }
    }
  }

  // Legacy EQ presets kept for backward compat
  static const List<Map<String, dynamic>> eqPresets = [
    {'name': 'Normal',      'gains': [0.0, 0.0, 0.0, 0.0, 0.0]},
    {'name': 'Classical',   'gains': [5.0, 3.0, 0.0, 3.0, 4.0]},
    {'name': 'Dance',       'gains': [6.0, 0.0, 2.0, 4.0, 1.0]},
    {'name': 'Flat',        'gains': [0.0, 0.0, 0.0, 0.0, 0.0]},
    {'name': 'Folk',        'gains': [3.0, 0.0, 0.0, 2.0, -1.0]},
    {'name': 'Heavy Metal', 'gains': [4.0, 1.0, 9.0, 3.0, 0.0]},
    {'name': 'Hip-Hop',     'gains': [5.0, 4.0, 1.0, 1.0, 3.0]},
    {'name': 'Jazz',        'gains': [4.0, 2.0, -2.0, 2.0, 5.0]},
    {'name': 'Pop',         'gains': [-1.0, 2.0, 5.0, 1.0, -2.0]},
    {'name': 'Rock',        'gains': [5.0, 3.0, -1.0, 3.0, 5.0]},
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
      unawaited(PlaybackManager.setEqualizerBandGain(i, clamped));
      await prefs.setDouble('eqBand_$i', clamped);
    }
    LogService.log('AudioEffects', 'EQ preset: ${eqPresets[presetIndex]['name']}');
  }

  // ── Crossfade ──────────────────────────────────────────────────────────────

  static Future<void> setCrossfade(double seconds) async {
    crossfadeDuration.value = seconds;
    await _saveDouble('crossfade', seconds);
    unawaited(PlaybackManager.setCrossfadeDuration(seconds));
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
    unawaited(PlaybackManager.setPitch(factor));
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
    unawaited(PlaybackManager.setSpeed(speed));
  }

  // ── Bass Boost ────────────────────────────────────────────────────────────

  static Future<void> setBassBoost(int strength) async {
    final v = strength.clamp(0, 1000).toInt();
    bassBoost.value = v;
    await _saveInt('bassBoost', v);
    unawaited(PlaybackManager.setBassBoost(v));
    unawaited(PlaybackManager.setBassBoostEnabled(v > 0));
    LogService.log('AudioEffects', 'BassBoost: $v');
  }

  // ── Spatial Audio ─────────────────────────────────────────────────────────

  static Future<void> setSpatial(bool value) async {
    spatialAudio.value = value;
    await _saveBool('spatial', value);
    unawaited(PlaybackManager.setVirtualizerEnabled(value));
    LogService.log('AudioEffects', 'Spatial: $value');
  }

  static Future<void> setSpatialStrength(int strength) async {
    final v = strength.clamp(0, 1000).toInt();
    spatialStrength.value = v;
    await _saveInt('spatialStr', v);
    unawaited(PlaybackManager.setVirtualizerStrength(v));
    if (spatialAudio.value) {
      unawaited(PlaybackManager.setVirtualizerEnabled(true));
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
