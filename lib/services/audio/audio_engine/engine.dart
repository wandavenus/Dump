part of '../audio_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AudioEngine — Dual-Player Architecture
// ─────────────────────────────────────────────────────────────────────────────
//
//  Two independent playback slots (A and B) exist at all times.
//  Only one is "active" (audible); the other is the "standby" slot used for
//  preloading the next track and running the outgoing half of a crossfade.
//
//  Effect-control implementation is in effects_control.dart (same library).
//
// ─────────────────────────────────────────────────────────────────────────────

class AudioEngine {
  AudioEngine._();

  static const MethodChannel _effectsChannel =
      MethodChannel('musicplayer/audio_effects');

  // ── Slot state ────────────────────────────────────────────────────────────

  static PlayerSlot? _slotA;
  static PlayerSlot? _slotB;
  static int  _activeSlot = 0;
  static bool _initialized = false;

  // Effect support flags (queried from native on first session attach)
  static bool _virtualizerSupported = false;
  static bool _bassBoostSupported   = false;
  static bool _reverbSupported      = false;

  // ── Getters ───────────────────────────────────────────────────────────────

  static AudioPlayer get activePlayer  => _activeSlot == 0 ? _slotA!.player : _slotB!.player;
  static AudioPlayer get standbyPlayer => _activeSlot == 0 ? _slotB!.player : _slotA!.player;
  static PlayerSlot  get activeSlot    => _activeSlot == 0 ? _slotA! : _slotB!;
  static PlayerSlot  get standbySlot   => _activeSlot == 0 ? _slotB! : _slotA!;
  static AudioPlayer get player        => activePlayer;

  static AndroidEqualizer?        get equalizer        => activeSlot.equalizer;
  static AndroidLoudnessEnhancer? get loudnessEnhancer => activeSlot.loudnessEnhancer;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get virtualizerSupported => _virtualizerSupported;
  static bool get bassBoostSupported   => _bassBoostSupported;
  static bool get reverbSupported      => _reverbSupported;

  // ── Initialization ────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _slotA = PlayerSlot.create('A', isAndroid: isAndroid);
    _slotB = PlayerSlot.create('B', isAndroid: isAndroid);
    _activeSlot = 0;

    if (isAndroid) {
      _slotA!.listenSessionId(_engineAttachNativeEffects);
      _slotB!.listenSessionId(_engineAttachNativeEffects);

      final prefs   = await SharedPreferences.getInstance();
      final modeIdx = prefs.getInt('audioOutputMode') ?? 0;
      final mode    = AudioOutputMode.values[modeIdx.clamp(0, 2)];
      if (mode != AudioOutputMode.auto) _engineApplyOutputMode(mode);

      LogService.log('AudioEngine', 'Dual-player (Android DSP) initialized – Slot A active');
    } else {
      LogService.log('AudioEngine', 'Dual-player initialized (web / non-Android) – Slot A active');
    }
  }

  // ── Handoff ───────────────────────────────────────────────────────────────

  static void handoff() {
    _activeSlot = 1 - _activeSlot;
    LogService.log(
      'AudioEngine',
      'Handoff → Slot ${_activeSlot == 0 ? "A" : "B"} is now active',
    );
  }

  // ── Normalization (inline — touches slots directly) ───────────────────────

  static void applyNormalize({required bool enabled, double targetGainMb = 0.0}) {
    _slotA?.applyLoudnessEnhancer(enabled: enabled, targetGainMb: targetGainMb);
    _slotB?.applyLoudnessEnhancer(enabled: enabled, targetGainMb: targetGainMb);
  }

  static void applyNormalizeToSlot(
    PlayerSlot slot, {
    required bool enabled,
    double targetGainMb = 0.0,
  }) {
    slot.applyLoudnessEnhancer(enabled: enabled, targetGainMb: targetGainMb);
  }

  // ── Effect delegates (implementation in effects_control.dart) ─────────────

  static Future<void> setSpatialEnabled(bool enabled, {int strength = 1000}) =>
      _engineSetSpatial(enabled, strength);

  static Future<void> setBassBoost(int strength) => _engineSetBassBoost(strength);

  static Future<void> setReverb(int preset) => _engineSetReverb(preset);

  static Future<void> restoreEqBandsOnSlot(PlayerSlot slot) =>
      _engineRestoreEqBands(slot);

  static Future<void> setAudioOutputMode(AudioOutputMode mode) =>
      _engineSetOutputMode(mode);

  static Future<AudioOutputMode> getAudioOutputMode() => _engineGetOutputMode();

  // ── Speed / Pitch (active player only) ───────────────────────────────────

  static void setSpeed(double speed) {
    try { activePlayer.setSpeed(speed); } catch (_) {}
  }

  static void setPitch(double factor) {
    try { activePlayer.setPitch(factor); } catch (_) {}
  }

  static void reapplySpeedPitch(double speed, double pitch) {
    try {
      activePlayer.setSpeed(speed);
      activePlayer.setPitch(pitch);
    } catch (_) {}
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    await _slotA?.dispose();
    await _slotB?.dispose();
    _slotA       = null;
    _slotB       = null;
    _initialized = false;
    LogService.log('AudioEngine', 'Disposed');
  }
}
