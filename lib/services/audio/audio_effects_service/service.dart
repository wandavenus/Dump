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

  // ── Crossfeed (Phase 7) ─────────────────────────────────────────────────────
  //
  // Native pipeline defaults this processor to bypass=false (i.e. active)
  // the moment it registers. We always explicitly push the bypass state on
  // startup (see `_pushEngineSettingsWhenReady`) so the audible effect stays
  // off until the user turns it on here, regardless of the native default.

  static final ValueNotifier<bool> crossfeedEnabled = ValueNotifier(false);

  /// Crossfeed blend strength [0, 1]. Default 0.3 when enabled.
  static final ValueNotifier<double> crossfeedAmount = ValueNotifier(0.3);

  // ── Compressor (Phase 6) ─────────────────────────────────────────────────────
  //
  // Native pipeline defaults this processor to bypass=false (threshold
  // −20 dBFS, ratio 4:1) the moment it registers — same caveat as crossfeed.

  static final ValueNotifier<bool> compressorEnabled = ValueNotifier(false);
  static final ValueNotifier<double> compressorThreshold = ValueNotifier(-20.0);

  /// 1.0 = no compression (off, no separate switch). Range (1.0, 20.0].
  static final ValueNotifier<double> compressorRatio = ValueNotifier(1.0);

  /// Attack time in ms — how fast gain reduction engages. Native default 10.0.
  static final ValueNotifier<double> compressorAttackMs = ValueNotifier(10.0);

  /// Release time in ms — how fast gain reduction recovers. Native default 100.0.
  static final ValueNotifier<double> compressorReleaseMs = ValueNotifier(100.0);

  /// Knee width in dB — 0 = hard knee. Native default 6.0.
  static final ValueNotifier<double> compressorKneeDb = ValueNotifier(6.0);

  // ── Limiter (Phase 6) ────────────────────────────────────────────────────────
  //
  // Native pipeline defaults this processor to bypass=false (ceiling
  // −1 dBFS) the moment it registers — same caveat as crossfeed.

  static final ValueNotifier<bool> limiterEnabled = ValueNotifier(false);

  /// 0.0 = off (no separate switch). Range [-24.0, 0.0].
  static final ValueNotifier<double> limiterThreshold = ValueNotifier(0.0);

  /// Gain-recovery time in ms after the limiter engages. Native default 50.0.
  static final ValueNotifier<double> limiterReleaseMs = ValueNotifier(50.0);

  // ── Soft Clipper (Phase 6) ───────────────────────────────────────────────────
  //
  // Native pipeline defaults this processor to bypass=false (threshold
  // −0.5 dBFS) the moment it registers — same caveat as crossfeed.

  static final ValueNotifier<bool> softClipperEnabled = ValueNotifier(false);

  /// 0.0 = off (no separate switch). Range [-12.0, 0.0].
  static final ValueNotifier<double> softClipperThreshold = ValueNotifier(0.0);

  // ── Native Preamp (Gain Processor, dsp.gain) ─────────────────────────────
  //
  // Manual gain trim applied at the very start of the native DSP pipeline,
  // before EQ/dynamics/etc. 0.0 = unity (off, no separate switch).
  static final ValueNotifier<double> nativePreampDb = ValueNotifier(0.0);

  static final ValueNotifier<double> crossfadeDuration = ValueNotifier(0.0);
  static final ValueNotifier<double> pitchShift = ValueNotifier(0.0);
  static final ValueNotifier<int> bassBoost = ValueNotifier(0);
  static final ValueNotifier<double> playbackSpeed = ValueNotifier(1.0);
  static final ValueNotifier<bool> equalizerEnabled = ValueNotifier(false);
  static final ValueNotifier<int> roomPreset = ValueNotifier(0);

  /// Index preset EQ yang terakhir diterapkan via [applyEqPreset].
  /// -1 berarti tidak ada preset aktif (gains diatur manual / belum di-init).
  static final ValueNotifier<int> eqPreset = ValueNotifier(-1);

  static final ValueNotifier<String> lyricsPath = ValueNotifier('');

  // ── Bit-Perfect Mode ─────────────────────────────────────────────────────
  //
  // Master switch that force-bypasses EVERY audio-altering feature in the
  // app (EQ, Bass Boost, Compressor, Limiter, Soft
  // Clipper, Crossfeed, ReplayGain, Loudness Normalization, Crossfade,
  // Speed, Pitch, and the native Gain/PEQ pipeline stages) so the signal
  // reaches the output as close as possible to the untouched source PCM.
  //
  // The previous state of every feature is snapshotted to SharedPreferences
  // before bypassing, so turning this back off restores exactly what the
  // user had configured — this survives an app restart, since the snapshot
  // is persisted, not just kept in memory.
  static final ValueNotifier<bool> bitPerfectMode = ValueNotifier(false);

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
    crossfeedEnabled.value    = prefs.getBool('crossfeedEnabled')   ?? false;
    crossfeedAmount.value     = prefs.getDouble('crossfeedAmount')  ?? 0.3;
    compressorEnabled.value   = prefs.getBool('compEnabled')        ?? false;
    compressorThreshold.value = prefs.getDouble('compThreshold')    ?? -20.0;
    compressorRatio.value     = prefs.getDouble('compRatio')        ?? 1.0;
    compressorAttackMs.value  = prefs.getDouble('compAttackMs')     ?? 10.0;
    compressorReleaseMs.value = prefs.getDouble('compReleaseMs')    ?? 100.0;
    compressorKneeDb.value    = prefs.getDouble('compKneeDb')       ?? 6.0;
    limiterEnabled.value      = prefs.getBool('limEnabled')         ?? false;
    limiterThreshold.value    = prefs.getDouble('limThreshold')     ?? 0.0;
    limiterReleaseMs.value    = prefs.getDouble('limReleaseMs')     ?? 50.0;
    nativePreampDb.value      = prefs.getDouble('nativePreampDb')   ?? 0.0;
    softClipperEnabled.value  = prefs.getBool('scEnabled')          ?? false;
    softClipperThreshold.value = prefs.getDouble('scThreshold')     ?? 0.0;
    bitPerfectMode.value      = prefs.getBool('bitPerfectMode')     ?? false;

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

    // Equalizer — sync initial enabled state to the system Equalizer effect.
    unawaited(PlaybackManager.setEqualizerEnabled(equalizerEnabled.value));
    if (equalizerEnabled.value) _sendRoomPresetEq(roomPreset.value);

    // Crossfade
    unawaited(PlaybackManager.setCrossfadeDuration(crossfadeDuration.value));

    // Crossfeed (Phase 7) — native default is bypass=false (active) as soon
    // as the processor registers, so we always push the explicit bypass
    // state here regardless of whether the user has touched the setting.
    PlaybackManager.setNativeCrossfeedBypass(!crossfeedEnabled.value);
    if (crossfeedEnabled.value) {
      PlaybackManager.setNativeCrossfeedParams(amount: crossfeedAmount.value);
    }

    // Native Preamp (dsp.gain) — always push explicit bypass state.
    PlaybackManager.setNativeGainBypass(nativePreampDb.value == 0.0);
    if (nativePreampDb.value != 0.0) {
      PlaybackManager.setNativeGainDb(nativePreampDb.value);
    }

    // Compressor (Phase 6) — same always-on native default; always push.
    PlaybackManager.setNativeCompressorBypass(!compressorEnabled.value);
    if (compressorEnabled.value) {
      PlaybackManager.setNativeCompressorParams(
        thresholdDb: compressorThreshold.value,
        ratio: compressorRatio.value,
        attackMs: compressorAttackMs.value,
        releaseMs: compressorReleaseMs.value,
        kneeDb: compressorKneeDb.value,
      );
    }

    // Limiter (Phase 6) — same always-on native default; always push.
    PlaybackManager.setNativeLimiterBypass(!limiterEnabled.value);
    if (limiterEnabled.value) {
      PlaybackManager.setNativeLimiterParams(
        thresholdDb: limiterThreshold.value,
        releaseMs: limiterReleaseMs.value,
      );
    }

    // Soft Clipper (Phase 6) — same always-on native default; always push.
    PlaybackManager.setNativeSoftClipperBypass(!softClipperEnabled.value);
    if (softClipperEnabled.value) {
      PlaybackManager.setNativeSoftClipperThresholdDb(softClipperThreshold.value);
    }
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

  // ── Crossfeed (Phase 7) ─────────────────────────────────────────────────────

  static Future<void> setCrossfeedEnabled(bool enabled) async {
    crossfeedEnabled.value = enabled;
    await _saveBool('crossfeedEnabled', enabled);
    PlaybackManager.setNativeCrossfeedBypass(!enabled);
    if (enabled) {
      PlaybackManager.setNativeCrossfeedParams(amount: crossfeedAmount.value);
    }
    LogService.log('AudioEffects', 'Crossfeed: ${enabled ? 'ON' : 'OFF'}');
  }

  static Future<void> setCrossfeedAmount(double amount) async {
    final v = amount.clamp(0.0, 1.0);
    crossfeedAmount.value = v;
    await _saveDouble('crossfeedAmount', v);
    if (crossfeedEnabled.value) {
      PlaybackManager.setNativeCrossfeedParams(amount: v);
    }
    LogService.log('AudioEffects', 'Crossfeed amount: ${v.toStringAsFixed(2)}');
  }

  // ── Compressor (Phase 6) ─────────────────────────────────────────────────────

  /// Re-sends every current compressor parameter to the native processor in
  /// one call. Used by threshold/ratio/attack/release/knee setters so each
  /// one doesn't have to repeat the full parameter list.
  static void _pushCompressorParams() {
    PlaybackManager.setNativeCompressorParams(
      thresholdDb: compressorThreshold.value,
      ratio: compressorRatio.value,
      attackMs: compressorAttackMs.value,
      releaseMs: compressorReleaseMs.value,
      kneeDb: compressorKneeDb.value,
    );
  }

  static Future<void> setCompressorEnabled(bool enabled) async {
    compressorEnabled.value = enabled;
    await _saveBool('compEnabled', enabled);
    PlaybackManager.setNativeCompressorBypass(!enabled);
    if (enabled) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor: ${enabled ? 'ON' : 'OFF'}');
  }

  static Future<void> setCompressorThreshold(double db) async {
    final v = db.clamp(-60.0, 0.0);
    compressorThreshold.value = v;
    await _saveDouble('compThreshold', v);
    if (compressorEnabled.value) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor threshold: $v dB');
  }

  /// Attack time in ms — how fast the compressor engages once the signal
  /// crosses the threshold. Range [0.1, 500].
  static Future<void> setCompressorAttackMs(double ms) async {
    final v = ms.clamp(0.1, 500.0);
    compressorAttackMs.value = v;
    await _saveDouble('compAttackMs', v);
    if (compressorEnabled.value) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor attack: $v ms');
  }

  /// Release time in ms — how fast gain reduction recovers. Range [1, 2000].
  static Future<void> setCompressorReleaseMs(double ms) async {
    final v = ms.clamp(1.0, 2000.0);
    compressorReleaseMs.value = v;
    await _saveDouble('compReleaseMs', v);
    if (compressorEnabled.value) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor release: $v ms');
  }

  /// Knee width in dB — 0 = hard knee (abrupt), higher = softer transition
  /// into compression. Range [0, 24].
  static Future<void> setCompressorKneeDb(double db) async {
    final v = db.clamp(0.0, 24.0);
    compressorKneeDb.value = v;
    await _saveDouble('compKneeDb', v);
    if (compressorEnabled.value) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor knee: $v dB');
  }

  /// Ratio drives the compressor's on/off state directly — 1:1 is the
  /// mathematical definition of "no compression", so there is no separate
  /// switch. Any ratio above 1.0 engages the processor.
  static Future<void> setCompressorRatio(double ratio) async {
    final v = ratio.clamp(1.0, 20.0);
    compressorRatio.value = v;
    await _saveDouble('compRatio', v);

    final enabled = v > 1.0;
    compressorEnabled.value = enabled;
    await _saveBool('compEnabled', enabled);
    PlaybackManager.setNativeCompressorBypass(!enabled);
    if (enabled) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor ratio: ${v.toStringAsFixed(1)}:1');
  }

  // ── Limiter (Phase 6) ────────────────────────────────────────────────────────

  static void _pushLimiterParams() {
    PlaybackManager.setNativeLimiterParams(
      thresholdDb: limiterThreshold.value,
      releaseMs: limiterReleaseMs.value,
    );
  }

  static Future<void> setLimiterEnabled(bool enabled) async {
    limiterEnabled.value = enabled;
    await _saveBool('limEnabled', enabled);
    PlaybackManager.setNativeLimiterBypass(!enabled);
    if (enabled) _pushLimiterParams();
    LogService.log('AudioEffects', 'Limiter: ${enabled ? 'ON' : 'OFF'}');
  }

  /// Gain-recovery time in ms after the limiter engages. Range [1, 1000].
  static Future<void> setLimiterReleaseMs(double ms) async {
    final v = ms.clamp(1.0, 1000.0);
    limiterReleaseMs.value = v;
    await _saveDouble('limReleaseMs', v);
    if (limiterEnabled.value) _pushLimiterParams();
    LogService.log('AudioEffects', 'Limiter release: $v ms');
  }

  /// The ceiling slider drives on/off directly — `0.0` dB (top of the
  /// slider's range) means "no headroom removed", i.e. off. Anything below
  /// engages the limiter at that ceiling, with no separate switch.
  static Future<void> setLimiterThreshold(double db) async {
    final v = db.clamp(-24.0, 0.0);
    limiterThreshold.value = v;
    await _saveDouble('limThreshold', v);

    final enabled = v < 0.0;
    limiterEnabled.value = enabled;
    await _saveBool('limEnabled', enabled);
    PlaybackManager.setNativeLimiterBypass(!enabled);
    if (enabled) _pushLimiterParams();
    LogService.log('AudioEffects', 'Limiter threshold: $v dB');
  }

  // ── Native Preamp (Gain Processor, dsp.gain) ─────────────────────────────

  /// Manual gain trim (dBFS) applied before every other native DSP stage.
  /// `0.0` (top-center of the slider) drives the on/off state directly —
  /// no separate switch. Range [-24.0, 24.0] (native hard limit is wider,
  /// clamped tighter here to keep the UI usable).
  static Future<void> setNativePreampDb(double db) async {
    final v = db.clamp(-24.0, 24.0);
    nativePreampDb.value = v;
    await _saveDouble('nativePreampDb', v);
    final enabled = v != 0.0;
    PlaybackManager.setNativeGainBypass(!enabled);
    if (enabled) PlaybackManager.setNativeGainDb(v);
    LogService.log('AudioEffects', 'Native Preamp: $v dB');
  }

  // ── Soft Clipper (Phase 6) ───────────────────────────────────────────────────

  static Future<void> setSoftClipperEnabled(bool enabled) async {
    softClipperEnabled.value = enabled;
    await _saveBool('scEnabled', enabled);
    PlaybackManager.setNativeSoftClipperBypass(!enabled);
    if (enabled) {
      PlaybackManager.setNativeSoftClipperThresholdDb(softClipperThreshold.value);
    }
    LogService.log('AudioEffects', 'Soft Clipper: ${enabled ? 'ON' : 'OFF'}');
  }

  /// The threshold slider drives on/off directly — `0.0` dB (top of the
  /// slider's range) means "clip point at digital max", i.e. off. Anything
  /// below engages the soft clipper at that threshold, with no separate
  /// switch.
  static Future<void> setSoftClipperThreshold(double db) async {
    final v = db.clamp(-12.0, 0.0);
    softClipperThreshold.value = v;
    await _saveDouble('scThreshold', v);

    final enabled = v < 0.0;
    softClipperEnabled.value = enabled;
    await _saveBool('scEnabled', enabled);
    PlaybackManager.setNativeSoftClipperBypass(!enabled);
    if (enabled) {
      PlaybackManager.setNativeSoftClipperThresholdDb(v);
    }
    LogService.log('AudioEffects', 'Soft Clipper threshold: $v dB');
  }

  // ── Equalizer ─────────────────────────────────────────────────────────────
  //
  // Band EQ is applied through the legacy Android system Equalizer
  // (Media3/AudioFlinger effect) only. The native 32-band Parametric EQ
  // (Phase 5) was removed — see `.agents/memory/eq-silent-attach-failure.md`
  // for background on why the system Equalizer is the sole EQ backend.

  /// Writes a single band's gain to the system Equalizer.
  static Future<void> _writeEqBand(int bandIndex, double gainDb) async {
    unawaited(PlaybackManager.setEqualizerBandGain(bandIndex, gainDb));
  }

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
    } on Exception catch (error) {
      LogService.warn('AudioEffects', 'getEqParameters: $error');
      return null;
    }
  }

  static Future<void> setEqualizerBandGain(int bandIndex, double gainDb) async {
    try {
      unawaited(_writeEqBand(bandIndex, gainDb).catchError(
        (Object e) => LogService.warn('AudioEffects', 'writeEqBand[$bandIndex] error: $e'),
      ));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('eqBand_$bandIndex', gainDb);
      // Manual band adjustment — clear preset selection indicator.
      eqPreset.value = -1;
    } on Exception catch (e) {
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
      unawaited(_writeEqBand(b, gains[b]));
    }
    unawaited(SharedPreferences.getInstance().then((prefs) {
      for (var b = 0; b < gains.length; b++) {
        unawaited(prefs.setDouble('eqBand_$b', gains[b]));
      }
    }));
  }

  static Future<void> restoreEqualizerBands() async {
    final prefs  = await SharedPreferences.getInstance();
    final params = await getEqualizerParameters();
    if (params == null) return;
    for (var i = 0; i < params.bandCount; i++) {
      final gain = prefs.getDouble('eqBand_$i');
      if (gain != null) {
        unawaited(_writeEqBand(i, gain));
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
      unawaited(_writeEqBand(i, clamped));
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

  // Throttle timer for pitch: while the slider is being dragged we update the
  // UI ValueNotifier on every tick (immediate visual feedback) but defer the
  // native MethodChannel call + SharedPreferences write to 50 ms after the
  // last movement. This prevents flooding the audio thread with rapid-fire
  // nativeSetPitchSemitones() calls and eliminates mid-drag SharedPrefs I/O.
  static Timer? _pitchThrottle;

  static Future<void> setPitch(double semitones) async {
    // Immediate UI update — slider label stays in sync on every tick.
    pitchShift.value = semitones;

    // Throttle: cancel any pending commit and restart the 50 ms window.
    _pitchThrottle?.cancel();
    _pitchThrottle = Timer(const Duration(milliseconds: 50), () async {
      await _saveDouble('pitch', semitones);
      _sendPitch(semitones);
      LogService.log('AudioEffects', 'Pitch: $semitones semitones');
    });
  }

  /// Converts semitone offset to a pitch factor and forwards to the active engine.
  static void _sendPitch(double semitones) {
    if (kIsWeb) return;
    final factor = math.pow(2.0, semitones / 12.0).toDouble();
    unawaited(PlaybackManager.setPitch(factor));
  }

  // ── Playback Speed ────────────────────────────────────────────────────────

  // Throttle timer for speed: same rationale as _pitchThrottle above.
  // The fast-bypass ↔ STFT transition at 1.0× already has a nativeReset()
  // guard in the Kotlin layer; throttling here reduces how often that
  // transition is triggered when the slider is dragged across the 1.0 division.
  static Timer? _speedThrottle;

  static Future<void> setSpeed(double speed) async {
    final v = speed.clamp(0.25, 3.0).toDouble();
    // Immediate UI update — slider label stays in sync on every tick.
    playbackSpeed.value = v;

    // Throttle: cancel any pending commit and restart the 50 ms window.
    _speedThrottle?.cancel();
    _speedThrottle = Timer(const Duration(milliseconds: 50), () async {
      await _saveDouble('speed', v);
      _sendSpeed(v);
      LogService.log('AudioEffects', 'Speed: ${v}x');
    });
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

  // ── Bit-Perfect Mode ─────────────────────────────────────────────────────
  //
  // Master switch — force-bypasses every audio-altering feature in the app
  // so the signal reaches the output as close as possible to the untouched
  // source PCM. Snapshots the previous state of every feature to
  // SharedPreferences before bypassing so turning it back off restores
  // exactly what the user had configured, even across an app restart.

  static Future<void> setBitPerfectMode(bool enabled) async {
    if (bitPerfectMode.value == enabled) return;
    bitPerfectMode.value = enabled;
    await _saveBool('bitPerfectMode', enabled);

    if (enabled) {
      await _snapshotBeforeBitPerfect();
      await _forceBypassEverything();
      // Switch native playback onto the dedicated processing-free player —
      // zero AudioProcessors, zero AudioEffects, no dual-player crossfade.
      await PlaybackManager.setBitPerfectMode(true);
      LogService.log(
        'AudioEffects',
        'Bit-Perfect Mode: ON — all audio processing bypassed',
      );
    } else {
      // Switch back to the normal dual-player pipeline first, so the
      // settings restored below apply to the correct (post-switch) session.
      await PlaybackManager.setBitPerfectMode(false);
      await _restoreFromBitPerfectSnapshot();
      LogService.log(
        'AudioEffects',
        'Bit-Perfect Mode: OFF — previous settings restored',
      );
    }
  }

  static Future<void> _snapshotBeforeBitPerfect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bpmSnapEq', equalizerEnabled.value);
    await prefs.setInt('bpmSnapBass', bassBoost.value);
    await prefs.setDouble('bpmSnapSpeed', playbackSpeed.value);
    await prefs.setDouble('bpmSnapPitch', pitchShift.value);
    await prefs.setDouble('bpmSnapCrossfade', crossfadeDuration.value);
    await prefs.setInt('bpmSnapRgMode', replayGainMode.value.index);
    await prefs.setBool('bpmSnapLn', loudnessNormEnabled.value);
    await prefs.setBool('bpmSnapCrossfeed', crossfeedEnabled.value);
    await prefs.setDouble('bpmSnapCompRatio', compressorRatio.value);
    await prefs.setDouble('bpmSnapLimThreshold', limiterThreshold.value);
    await prefs.setDouble('bpmSnapScThreshold', softClipperThreshold.value);
    await prefs.setBool('bpmSnapValid', true);
  }

  static Future<void> _forceBypassEverything() async {
    await setEqualizerEnabled(false);
    await setBassBoost(0);
    await setSpeed(1.0);
    await setPitch(0.0);
    await setCrossfade(0.0);
    await setReplayGainMode(ReplayGainMode.off);
    await setLoudnessNormEnabled(false);
    await setCrossfeedEnabled(false);
    await setCompressorRatio(1.0);
    await setLimiterThreshold(0.0);
    await setSoftClipperThreshold(0.0);

    // Bypass ReplayGain on the currently-loaded track immediately, rather
    // than waiting for the next track change to pick up the new mode.
    PlaybackManager.setNativeReplayGainBypass(true);
    // Native Gain/Preamp is a live DSP stage with no dedicated UI toggle
    // elsewhere in the app — force it to unity/bypass too so nothing in the
    // native chain still touches the signal.
    PlaybackManager.setNativeGainBypass(true);
    // System-level LoudnessEnhancer, in case anything left it engaged.
    unawaited(PlaybackManager.setLoudnessEnabled(false));
    unawaited(PlaybackManager.setLoudnessTargetGain(0.0));
  }

  static Future<void> _restoreFromBitPerfectSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('bpmSnapValid') ?? false)) return;

    final eq         = prefs.getBool('bpmSnapEq')             ?? false;
    final bass       = prefs.getInt('bpmSnapBass')            ?? 0;
    final speed      = prefs.getDouble('bpmSnapSpeed')        ?? 1.0;
    final pitch      = prefs.getDouble('bpmSnapPitch')        ?? 0.0;
    final crossfade  = prefs.getDouble('bpmSnapCrossfade')    ?? 0.0;
    final rgIdx      = prefs.getInt('bpmSnapRgMode')          ?? 0;
    final ln         = prefs.getBool('bpmSnapLn')             ?? false;
    final crossfeed  = prefs.getBool('bpmSnapCrossfeed')      ?? false;
    final compRatio  = prefs.getDouble('bpmSnapCompRatio')    ?? 1.0;
    final limThresh  = prefs.getDouble('bpmSnapLimThreshold') ?? 0.0;
    final scThresh   = prefs.getDouble('bpmSnapScThreshold')  ?? 0.0;

    await setEqualizerEnabled(eq);
    if (eq) await restoreEqualizerBands();
    await setBassBoost(bass);
    await setSpeed(speed);
    await setPitch(pitch);
    await setCrossfade(crossfade);
    await setReplayGainMode(
      ReplayGainMode.values[rgIdx.clamp(0, ReplayGainMode.values.length - 1)],
    );
    await setLoudnessNormEnabled(ln);
    await setCrossfeedEnabled(crossfeed);
    await setCompressorRatio(compRatio);
    await setLimiterThreshold(limThresh);
    await setSoftClipperThreshold(scThresh);

    // Native Gain stage has no user-facing toggle — its normal resting
    // state is simply "not bypassed" (unity passthrough).
    PlaybackManager.setNativeGainBypass(false);

    await prefs.setBool('bpmSnapValid', false);
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
