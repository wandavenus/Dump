part of '../audio_effects_service.dart';

@immutable
class RoomPreset {
  final String name;
  final List<double> gains;
  final String desc;
  const RoomPreset({required this.name, required this.gains, required this.desc});
}

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

  static final ValueNotifier<ReplayGainMode> replayGainMode = ValueNotifier(
    ReplayGainMode.off,
  );
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

  // Media3 reports the actual PCM rate asynchronously when a track is
  // configured. Keep it for later UI changes so enabling an effect while a
  // 44.1 kHz track is playing does not send the native layer's 48 kHz default.
  static int _nativeSampleRate = 48000;

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

  static const List<RoomPreset> roomPresets = [
    RoomPreset(name: 'Flat',        gains: [0.0, 0.0, 0.0,  0.0,  0.0], desc: 'Tanpa efek ruangan'),
    RoomPreset(name: 'Studio',      gains: [2.0, 1.0, 0.0, -1.0,  1.0], desc: 'Rekaman studio profesional'),
    RoomPreset(name: 'Live Stage',  gains: [3.0, 0.0, 2.0,  1.0,  2.0], desc: 'Panggung pertunjukan langsung'),
    RoomPreset(name: 'Concert Hall',gains: [4.0, 1.0,-1.0,  2.0,  4.0], desc: 'Aula konser klasik'),
    RoomPreset(name: 'Cathedral',   gains: [3.0, 0.0,-2.0,  0.0,  5.0], desc: 'Gema katedral besar'),
    RoomPreset(name: 'Club',        gains: [6.0, 3.0, 1.0,  0.0, -1.0], desc: 'Club malam dengan bass kuat'),
    RoomPreset(name: 'Outdoor',     gains: [1.0, 0.0, 0.0,  2.0,  3.0], desc: 'Ruang terbuka di luar ruangan'),
    RoomPreset(name: 'Car',         gains: [4.0, 2.0, 1.0, -1.0,  0.0], desc: 'Interior kabin mobil'),
    RoomPreset(name: 'Bathroom',    gains: [0.0, 1.0, 3.0,  2.0,  1.0], desc: 'Ruang kecil dengan dinding keras'),
  ];

  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const _kCrossfade        = 'crossfade';
  static const _kPitch            = 'pitch';
  static const _kBassBoost        = 'bassBoost';
  static const _kSpeed            = 'speed';
  static const _kEqEnabled        = 'eqEnabled';
  static const _kRoomPreset       = 'roomPreset';
  static const _kEqPreset         = 'eqPreset';
  static const _kLyricsPath       = 'lyricsPath';
  static const _kReplayGainMode   = 'replayGainMode';
  static const _kReplayGainPreamp = 'replayGainPreamp';
  static const _kRgClipProtect    = 'rgClipProtect';
  static const _kLnEnabled        = 'lnEnabled';
  static const _kLnTarget         = 'lnTarget';
  static const _kCrossfeedEnabled = 'crossfeedEnabled';
  static const _kCrossfeedAmount  = 'crossfeedAmount';
  static const _kCompEnabled      = 'compEnabled';
  static const _kCompThreshold    = 'compThreshold';
  static const _kCompRatio        = 'compRatio';
  static const _kCompAttackMs     = 'compAttackMs';
  static const _kCompReleaseMs    = 'compReleaseMs';
  static const _kCompKneeDb       = 'compKneeDb';
  static const _kLimEnabled       = 'limEnabled';
  static const _kLimThreshold     = 'limThreshold';
  static const _kLimReleaseMs     = 'limReleaseMs';
  static const _kNativePreampDb   = 'nativePreampDb';
  static const _kScEnabled        = 'scEnabled';
  static const _kScThreshold      = 'scThreshold';
  static const _kBitPerfectMode   = 'bitPerfectMode';
  static const _kBpmSnapEq           = 'bpmSnapEq';
  static const _kBpmSnapBass         = 'bpmSnapBass';
  static const _kBpmSnapSpeed        = 'bpmSnapSpeed';
  static const _kBpmSnapPitch        = 'bpmSnapPitch';
  static const _kBpmSnapCrossfade    = 'bpmSnapCrossfade';
  static const _kBpmSnapRgMode       = 'bpmSnapRgMode';
  static const _kBpmSnapLn           = 'bpmSnapLn';
  static const _kBpmSnapCrossfeed    = 'bpmSnapCrossfeed';
  static const _kBpmSnapCompRatio    = 'bpmSnapCompRatio';
  static const _kBpmSnapLimThreshold = 'bpmSnapLimThreshold';
  static const _kBpmSnapScThreshold  = 'bpmSnapScThreshold';
  static const _kBpmSnapValid        = 'bpmSnapValid';
  static String _kEqBand(int i)      => 'eqBand_$i';

  // Cached SharedPreferences instance — initialised once in [init].
  static late SharedPreferences _prefs;

  // ── Init ───────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final prefs = _prefs;

    crossfadeDuration.value = prefs.getDouble(_kCrossfade) ?? 0.0;
    pitchShift.value = prefs.getDouble(_kPitch) ?? 0.0;
    bassBoost.value = prefs.getInt(_kBassBoost) ?? 0;
    playbackSpeed.value = prefs.getDouble(_kSpeed) ?? 1.0;
    equalizerEnabled.value = prefs.getBool(_kEqEnabled) ?? false;
    roomPreset.value = prefs.getInt(_kRoomPreset) ?? 0;
    eqPreset.value = prefs.getInt(_kEqPreset) ?? -1;
    lyricsPath.value = prefs.getString(_kLyricsPath) ?? '';

    final rgIdx = prefs.getInt(_kReplayGainMode) ?? 0;
    replayGainMode.value =
        ReplayGainMode.values[rgIdx.clamp(0, ReplayGainMode.values.length - 1)];
    replayGainPreamp.value = prefs.getDouble(_kReplayGainPreamp) ?? 0.0;
    clippingProtection.value = prefs.getBool(_kRgClipProtect) ?? true;
    loudnessNormEnabled.value = prefs.getBool(_kLnEnabled) ?? false;
    loudnessNormTarget.value = prefs.getDouble(_kLnTarget) ?? -23.0;
    crossfeedEnabled.value = prefs.getBool(_kCrossfeedEnabled) ?? false;
    crossfeedAmount.value = prefs.getDouble(_kCrossfeedAmount) ?? 0.3;
    compressorEnabled.value = prefs.getBool(_kCompEnabled) ?? false;
    compressorThreshold.value = prefs.getDouble(_kCompThreshold) ?? -20.0;
    compressorRatio.value = prefs.getDouble(_kCompRatio) ?? 1.0;
    compressorAttackMs.value = prefs.getDouble(_kCompAttackMs) ?? 10.0;
    compressorReleaseMs.value = prefs.getDouble(_kCompReleaseMs) ?? 100.0;
    compressorKneeDb.value = prefs.getDouble(_kCompKneeDb) ?? 6.0;
    limiterEnabled.value = prefs.getBool(_kLimEnabled) ?? false;
    limiterThreshold.value = prefs.getDouble(_kLimThreshold) ?? 0.0;
    limiterReleaseMs.value = prefs.getDouble(_kLimReleaseMs) ?? 50.0;
    nativePreampDb.value = prefs.getDouble(_kNativePreampDb) ?? 0.0;
    softClipperEnabled.value = prefs.getBool(_kScEnabled) ?? false;
    softClipperThreshold.value = prefs.getDouble(_kScThreshold) ?? 0.0;
    bitPerfectMode.value = prefs.getBool(_kBitPerfectMode) ?? false;

    applyAll();
    LogService.log('AudioEffects', 'Initialized');
  }

  // ── applyAll — send every setting to the active engine in one burst ────────

  static void applyAll() {
    if (kIsWeb) return;
    unawaited(_pushEngineSettingsWhenReady());
  }

  /// Rebuild sample-rate-dependent native coefficients after Media3 switches
  /// to a different PCM format. The native pipeline receives the sample rate
  /// on every audio block, but compressor/limiter/crossfeed coefficients are
  /// prepared on the control thread and otherwise retain their 48 kHz default.
  static void setNativeDspSampleRate(int sampleRate) {
    if (sampleRate <= 0 || kIsWeb) return;
    _nativeSampleRate = sampleRate;

    if (crossfeedEnabled.value) {
      PlaybackManager.setNativeCrossfeedParams(
        amount: crossfeedAmount.value,
        sampleRate: sampleRate.toDouble(),
      );
    }
    if (compressorEnabled.value) {
      PlaybackManager.setNativeCompressorParams(
        thresholdDb: compressorThreshold.value,
        ratio: compressorRatio.value,
        attackMs: compressorAttackMs.value,
        releaseMs: compressorReleaseMs.value,
        kneeDb: compressorKneeDb.value,
        sampleRate: sampleRate.toDouble(),
      );
    }
    if (limiterEnabled.value) {
      PlaybackManager.setNativeLimiterParams(
        thresholdDb: limiterThreshold.value,
        releaseMs: limiterReleaseMs.value,
        sampleRate: sampleRate.toDouble(),
      );
    }
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
      PlaybackManager.setNativeCrossfeedParams(
        amount: crossfeedAmount.value,
        sampleRate: _nativeSampleRate.toDouble(),
      );
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
        sampleRate: _nativeSampleRate.toDouble(),
      );
    }

    // Limiter (Phase 6) — same always-on native default; always push.
    PlaybackManager.setNativeLimiterBypass(!limiterEnabled.value);
    if (limiterEnabled.value) {
      PlaybackManager.setNativeLimiterParams(
        thresholdDb: limiterThreshold.value,
        releaseMs: limiterReleaseMs.value,
        sampleRate: _nativeSampleRate.toDouble(),
      );
    }

    // Soft Clipper (Phase 6) — same always-on native default; always push.
    PlaybackManager.setNativeSoftClipperBypass(!softClipperEnabled.value);
    if (softClipperEnabled.value) {
      PlaybackManager.setNativeSoftClipperThresholdDb(
        softClipperThreshold.value,
      );
    }
  }

  // ── ReplayGain (Audio Normalize) ───────────────────────────────────────────

  static Future<void> setReplayGainMode(ReplayGainMode mode) async {
    replayGainMode.value = mode;
    await _saveInt(_kReplayGainMode, mode.index);
    LogService.log('AudioEffects', 'ReplayGain mode: ${mode.name}');
  }

  static Future<void> setReplayGainPreamp(double db) async {
    final v = db.clamp(-15.0, 15.0);
    replayGainPreamp.value = v;
    await _saveDouble(_kReplayGainPreamp, v);
    LogService.log('AudioEffects', 'ReplayGain preamp: $v dB');
  }

  static Future<void> setClippingProtection(bool enabled) async {
    clippingProtection.value = enabled;
    await _saveBool(_kRgClipProtect, enabled);
    LogService.log('AudioEffects', 'Clipping protection: $enabled');
  }

  // ── Loudness Normalization (Phase 8.5) ─────────────────────────────────────

  static Future<void> setLoudnessNormEnabled(bool enabled) async {
    loudnessNormEnabled.value = enabled;
    await _saveBool(_kLnEnabled, enabled);
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
    await _saveDouble(_kLnTarget, v);
    PlaybackManager.setNativeLoudnessNormTargetLufs(v);
    LogService.log(
      'AudioEffects',
      'Loudness target: ${v.toStringAsFixed(1)} LUFS',
    );
  }

  // ── Crossfeed (Phase 7) ─────────────────────────────────────────────────────

  static Future<void> setCrossfeedEnabled(bool enabled) async {
    crossfeedEnabled.value = enabled;
    await _saveBool(_kCrossfeedEnabled, enabled);
    PlaybackManager.setNativeCrossfeedBypass(!enabled);
    if (enabled) {
      PlaybackManager.setNativeCrossfeedParams(
        amount: crossfeedAmount.value,
        sampleRate: _nativeSampleRate.toDouble(),
      );
    }
    LogService.log('AudioEffects', 'Crossfeed: ${enabled ? 'ON' : 'OFF'}');
  }

  static Future<void> setCrossfeedAmount(double amount) async {
    final v = amount.clamp(0.0, 1.0);
    crossfeedAmount.value = v;
    await _saveDouble(_kCrossfeedAmount, v);
    if (crossfeedEnabled.value) {
      PlaybackManager.setNativeCrossfeedParams(
        amount: v,
        sampleRate: _nativeSampleRate.toDouble(),
      );
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
      sampleRate: _nativeSampleRate.toDouble(),
    );
  }

  static Future<void> setCompressorEnabled(bool enabled) async {
    compressorEnabled.value = enabled;
    await _saveBool(_kCompEnabled, enabled);
    PlaybackManager.setNativeCompressorBypass(!enabled);
    if (enabled) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor: ${enabled ? 'ON' : 'OFF'}');
  }

  static Future<void> setCompressorThreshold(double db) async {
    final v = db.clamp(-60.0, 0.0);
    compressorThreshold.value = v;
    await _saveDouble(_kCompThreshold, v);
    if (compressorEnabled.value) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor threshold: $v dB');
  }

  /// Attack time in ms — how fast the compressor engages once the signal
  /// crosses the threshold. Range [0.1, 500].
  static Future<void> setCompressorAttackMs(double ms) async {
    final v = ms.clamp(0.1, 500.0);
    compressorAttackMs.value = v;
    await _saveDouble(_kCompAttackMs, v);
    if (compressorEnabled.value) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor attack: $v ms');
  }

  /// Release time in ms — how fast gain reduction recovers. Range [1, 2000].
  static Future<void> setCompressorReleaseMs(double ms) async {
    final v = ms.clamp(1.0, 2000.0);
    compressorReleaseMs.value = v;
    await _saveDouble(_kCompReleaseMs, v);
    if (compressorEnabled.value) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor release: $v ms');
  }

  /// Knee width in dB — 0 = hard knee (abrupt), higher = softer transition
  /// into compression. Range [0, 24].
  static Future<void> setCompressorKneeDb(double db) async {
    final v = db.clamp(0.0, 24.0);
    compressorKneeDb.value = v;
    await _saveDouble(_kCompKneeDb, v);
    if (compressorEnabled.value) _pushCompressorParams();
    LogService.log('AudioEffects', 'Compressor knee: $v dB');
  }

  /// Ratio drives the compressor's on/off state directly — 1:1 is the
  /// mathematical definition of "no compression", so there is no separate
  /// switch. Any ratio above 1.0 engages the processor.
  static Future<void> setCompressorRatio(double ratio) async {
    final v = ratio.clamp(1.0, 20.0);
    compressorRatio.value = v;
    await _saveDouble(_kCompRatio, v);

    final enabled = v > 1.0;
    compressorEnabled.value = enabled;
    await _saveBool(_kCompEnabled, enabled);
    PlaybackManager.setNativeCompressorBypass(!enabled);
    if (enabled) _pushCompressorParams();
    LogService.log(
      'AudioEffects',
      'Compressor ratio: ${v.toStringAsFixed(1)}:1',
    );
  }

  // ── Limiter (Phase 6) ────────────────────────────────────────────────────────

  static void _pushLimiterParams() {
    PlaybackManager.setNativeLimiterParams(
      thresholdDb: limiterThreshold.value,
      releaseMs: limiterReleaseMs.value,
      sampleRate: _nativeSampleRate.toDouble(),
    );
  }

  static Future<void> setLimiterEnabled(bool enabled) async {
    limiterEnabled.value = enabled;
    await _saveBool(_kLimEnabled, enabled);
    PlaybackManager.setNativeLimiterBypass(!enabled);
    if (enabled) _pushLimiterParams();
    LogService.log('AudioEffects', 'Limiter: ${enabled ? 'ON' : 'OFF'}');
  }

  /// Gain-recovery time in ms after the limiter engages. Range [1, 1000].
  static Future<void> setLimiterReleaseMs(double ms) async {
    final v = ms.clamp(1.0, 1000.0);
    limiterReleaseMs.value = v;
    await _saveDouble(_kLimReleaseMs, v);
    if (limiterEnabled.value) _pushLimiterParams();
    LogService.log('AudioEffects', 'Limiter release: $v ms');
  }

  /// The ceiling slider drives on/off directly — `0.0` dB (top of the
  /// slider's range) means "no headroom removed", i.e. off. Anything below
  /// engages the limiter at that ceiling, with no separate switch.
  static Future<void> setLimiterThreshold(double db) async {
    final v = db.clamp(-24.0, 0.0);
    limiterThreshold.value = v;
    await _saveDouble(_kLimThreshold, v);

    final enabled = v < 0.0;
    limiterEnabled.value = enabled;
    await _saveBool(_kLimEnabled, enabled);
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
    await _saveDouble(_kNativePreampDb, v);
    final enabled = v != 0.0;
    PlaybackManager.setNativeGainBypass(!enabled);
    if (enabled) PlaybackManager.setNativeGainDb(v);
    LogService.log('AudioEffects', 'Native Preamp: $v dB');
  }

  // ── Soft Clipper (Phase 6) ───────────────────────────────────────────────────

  static Future<void> setSoftClipperEnabled(bool enabled) async {
    softClipperEnabled.value = enabled;
    await _saveBool(_kScEnabled, enabled);
    PlaybackManager.setNativeSoftClipperBypass(!enabled);
    if (enabled) {
      PlaybackManager.setNativeSoftClipperThresholdDb(
        softClipperThreshold.value,
      );
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
    await _saveDouble(_kScThreshold, v);

    final enabled = v < 0.0;
    softClipperEnabled.value = enabled;
    await _saveBool(_kScEnabled, enabled);
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
    await _saveBool(_kEqEnabled, value);
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
      unawaited(
        _writeEqBand(bandIndex, gainDb).catchError(
          (Object e) => LogService.warn(
            'AudioEffects',
            'writeEqBand[$bandIndex] error: $e',
          ),
        ),
      );
      await _prefs.setDouble(_kEqBand(bandIndex), gainDb);
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
    await _saveInt(_kRoomPreset, i);

    final preset = roomPresets[i];
    if (equalizerEnabled.value) _sendRoomPresetEq(i);

    LogService.log('AudioEffects', 'Room preset: ${preset.name}');
  }

  static void _sendRoomPresetEq(int index) {
    final i = index.clamp(0, roomPresets.length - 1).toInt();
    final gains = roomPresets[i].gains;
    for (var b = 0; b < gains.length; b++) {
      unawaited(_writeEqBand(b, gains[b]));
      unawaited(_prefs.setDouble(_kEqBand(b), gains[b]));
    }
  }

  static Future<void> restoreEqualizerBands() async {
    final params = await getEqualizerParameters();
    if (params == null) return;
    for (var i = 0; i < params.bandCount; i++) {
      final gain = _prefs.getDouble(_kEqBand(i));
      if (gain != null) {
        unawaited(_writeEqBand(i, gain));
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
    await _saveInt(_kEqPreset, presetIndex);

    // Send gains to native; use engine params for band count + clamp range.
    final params = await getEqualizerParameters();
    final bandCount = params?.bandCount ?? gains.length;
    final lo = params?.minDecibels ?? -15.0;
    final hi = params?.maxDecibels ?? 15.0;
    for (var i = 0; i < bandCount && i < gains.length; i++) {
      final clamped = gains[i].clamp(lo, hi).toDouble();
      unawaited(_writeEqBand(i, clamped));
      await _prefs.setDouble(_kEqBand(i), clamped);
    }
    LogService.log(
      'AudioEffects',
      'EQ preset: ${eqPresets[presetIndex]['name']}',
    );
  }

  // ── Crossfade ──────────────────────────────────────────────────────────────

  static Future<void> setCrossfade(double seconds) async {
    crossfadeDuration.value = seconds;
    await _saveDouble(_kCrossfade, seconds);
    unawaited(PlaybackManager.setCrossfadeDuration(seconds));
    LogService.log('AudioEffects', 'Crossfade: ${seconds}s');
  }

  // ── Pitch Shift ───────────────────────────────────────────────────────────

  // Live preview is separate from the committed setter below. The slider can
  // update the audio while it is dragged without writing SharedPreferences on
  // every pointer event.
  static Timer? _pitchThrottle;
  static double? _pendingPreviewPitch;
  static double? _lastPreviewPitch;

  static Future<void> setPitch(double semitones) async {
    pitchShift.value = semitones;
    _pitchThrottle?.cancel();
    _pitchThrottle = null;
    _pendingPreviewPitch = null;
    _lastPreviewPitch = semitones;
    await _saveDouble(_kPitch, semitones);
    _sendPitch(semitones);
    LogService.log('AudioEffects', 'Pitch: $semitones semitones');
  }

  /// Updates pitch during a drag at most once per 32 ms. Persistence happens
  /// only in [setPitch] when the slider is released.
  static void previewPitch(double semitones) {
    pitchShift.value = semitones;
    _pendingPreviewPitch = semitones;
    _flushPitchPreview(immediate: _pitchThrottle == null);
  }

  static void _flushPitchPreview({required bool immediate}) {
    if (immediate) {
      final value = _pendingPreviewPitch;
      if (value != null) {
        _lastPreviewPitch = value;
        _pendingPreviewPitch = null;
        _sendPitch(value);
      }
    }
    _pitchThrottle ??= Timer(const Duration(milliseconds: 32), () {
      _pitchThrottle = null;
      final value = _pendingPreviewPitch;
      if (value == null) return;
      _pendingPreviewPitch = null;
      if (value != _lastPreviewPitch) {
        _lastPreviewPitch = value;
        _sendPitch(value);
      }
    });
  }

  /// Converts semitone offset to a pitch factor and forwards to the active engine.
  static void _sendPitch(double semitones) {
    if (kIsWeb) return;
    final factor = math.pow(2.0, semitones / 12.0).toDouble();
    unawaited(PlaybackManager.setPitch(factor));
  }

  // ── Playback Speed ────────────────────────────────────────────────────────

  static Timer? _speedThrottle;
  static double? _pendingPreviewSpeed;
  static double? _lastPreviewSpeed;

  static Future<void> setSpeed(double speed) async {
    final v = speed.clamp(0.25, 3.0).toDouble();
    playbackSpeed.value = v;
    _speedThrottle?.cancel();
    _speedThrottle = null;
    _pendingPreviewSpeed = null;
    _lastPreviewSpeed = v;
    await _saveDouble(_kSpeed, v);
    _sendSpeed(v);
    LogService.log('AudioEffects', 'Speed: ${v}x');
  }

  /// Updates speed during a drag at most once per 32 ms. Persistence happens
  /// only in [setSpeed] when the slider is released.
  static void previewSpeed(double speed) {
    final v = speed.clamp(0.25, 3.0).toDouble();
    playbackSpeed.value = v;
    _pendingPreviewSpeed = v;
    _flushSpeedPreview(immediate: _speedThrottle == null);
  }

  static void _flushSpeedPreview({required bool immediate}) {
    if (immediate) {
      final value = _pendingPreviewSpeed;
      if (value != null) {
        _lastPreviewSpeed = value;
        _pendingPreviewSpeed = null;
        _sendSpeed(value);
      }
    }
    _speedThrottle ??= Timer(const Duration(milliseconds: 32), () {
      _speedThrottle = null;
      final value = _pendingPreviewSpeed;
      if (value == null) return;
      _pendingPreviewSpeed = null;
      if (value != _lastPreviewSpeed) {
        _lastPreviewSpeed = value;
        _sendSpeed(value);
      }
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
    await _saveInt(_kBassBoost, v);
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
    await _saveBool(_kBitPerfectMode, enabled);

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
    await _prefs.setBool(_kBpmSnapEq, equalizerEnabled.value);
    await _prefs.setInt(_kBpmSnapBass, bassBoost.value);
    await _prefs.setDouble(_kBpmSnapSpeed, playbackSpeed.value);
    await _prefs.setDouble(_kBpmSnapPitch, pitchShift.value);
    await _prefs.setDouble(_kBpmSnapCrossfade, crossfadeDuration.value);
    await _prefs.setInt(_kBpmSnapRgMode, replayGainMode.value.index);
    await _prefs.setBool(_kBpmSnapLn, loudnessNormEnabled.value);
    await _prefs.setBool(_kBpmSnapCrossfeed, crossfeedEnabled.value);
    await _prefs.setDouble(_kBpmSnapCompRatio, compressorRatio.value);
    await _prefs.setDouble(_kBpmSnapLimThreshold, limiterThreshold.value);
    await _prefs.setDouble(_kBpmSnapScThreshold, softClipperThreshold.value);
    await _prefs.setBool(_kBpmSnapValid, true);
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
    if (!(_prefs.getBool(_kBpmSnapValid) ?? false)) return;

    final eq = _prefs.getBool(_kBpmSnapEq) ?? false;
    final bass = _prefs.getInt(_kBpmSnapBass) ?? 0;
    final speed = _prefs.getDouble(_kBpmSnapSpeed) ?? 1.0;
    final pitch = _prefs.getDouble(_kBpmSnapPitch) ?? 0.0;
    final crossfade = _prefs.getDouble(_kBpmSnapCrossfade) ?? 0.0;
    final rgIdx = _prefs.getInt(_kBpmSnapRgMode) ?? 0;
    final ln = _prefs.getBool(_kBpmSnapLn) ?? false;
    final crossfeed = _prefs.getBool(_kBpmSnapCrossfeed) ?? false;
    final compRatio = _prefs.getDouble(_kBpmSnapCompRatio) ?? 1.0;
    final limThresh = _prefs.getDouble(_kBpmSnapLimThreshold) ?? 0.0;
    final scThresh = _prefs.getDouble(_kBpmSnapScThreshold) ?? 0.0;

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

    await _prefs.setBool(_kBpmSnapValid, false);
  }

  // ── Lyrics path ───────────────────────────────────────────────────────────

  static Future<void> setLyricsPath(String path) async {
    final v = path.trim();
    lyricsPath.value = v;
    await _prefs.setString(_kLyricsPath, v);
    LogService.log('AudioEffects', 'Lyrics path: $v');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<void> _saveBool(String k, bool v) => _prefs.setBool(k, v);
  static Future<void> _saveInt(String k, int v) => _prefs.setInt(k, v);
  static Future<void> _saveDouble(String k, double v) => _prefs.setDouble(k, v);
}
