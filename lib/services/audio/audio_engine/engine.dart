part of '../audio_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AudioEngine — Dual-Player Architecture
// ─────────────────────────────────────────────────────────────────────────────
//
//  Two independent playback slots (A and B) exist at all times.
//  Only one is "active" (audible); the other is the "standby" slot used for
//  preloading the next track and running the outgoing half of a crossfade.
//
//  Handoff flow:
//    ┌─────────────┐              ┌─────────────┐
//    │  Slot A     │  crossfade   │  Slot B     │
//    │  (active)   │ ──────────>  │  (standby)  │
//    │  vol: 1→0   │              │  vol: 0→1   │
//    └─────────────┘              └─────────────┘
//          ↑  handoff() swaps roles  ↑
//
//  After handoff():
//    • Slot B becomes active (vol=1, playing current track)
//    • Slot A becomes standby (stopped, ready to preload next-next track)
//
// ─────────────────────────────────────────────────────────────────────────────

/// Low-level dual-player engine.
///
/// All UI and service code should use [AudioService] rather than this class
/// directly.  The only external consumers of [AudioEngine] are:
///   • [AudioService]          – playback control
///   • [AudioEffectsService]   – DSP settings
///   • [AudioSessionHandler]   – OS audio focus / interruptions
///   • [CrossfadeController]   – volume automation
class AudioEngine {
  AudioEngine._();

  static const MethodChannel _effectsChannel =
      MethodChannel('musicplayer/audio_effects');

  // ── Slot state ────────────────────────────────────────────────────────────

  static PlayerSlot? _slotA;
  static PlayerSlot? _slotB;

  /// 0 = Slot A is active; 1 = Slot B is active.
  static int _activeSlot = 0;

  static bool _initialized = false;

  // Effect support flags (queried from native on first session attach)
  static bool _virtualizerSupported = false;
  static bool _bassBoostSupported   = false;
  static bool _reverbSupported      = false;

  // ── Getters ───────────────────────────────────────────────────────────────

  /// The currently audible player.
  static AudioPlayer get activePlayer =>
      _activeSlot == 0 ? _slotA!.player : _slotB!.player;

  /// The player that is preloaded / will be faded in next.
  static AudioPlayer get standbyPlayer =>
      _activeSlot == 0 ? _slotB!.player : _slotA!.player;

  static PlayerSlot get activeSlot =>
      _activeSlot == 0 ? _slotA! : _slotB!;

  static PlayerSlot get standbySlot =>
      _activeSlot == 0 ? _slotB! : _slotA!;

  /// Backward-compatible alias: returns the active player.
  static AudioPlayer get player => activePlayer;

  /// Active slot's equalizer (Android only).
  static AndroidEqualizer? get equalizer => activeSlot.equalizer;

  /// Active slot's loudness enhancer (Android only).
  static AndroidLoudnessEnhancer? get loudnessEnhancer =>
      activeSlot.loudnessEnhancer;

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
      // Attach native effects whenever either slot's session ID changes
      _slotA!.listenSessionId((id) => _attachNativeEffects(id));
      _slotB!.listenSessionId((id) => _attachNativeEffects(id));

      // Apply stored audio output mode
      final prefs   = await SharedPreferences.getInstance();
      final modeIdx = prefs.getInt('audioOutputMode') ?? 0;
      final mode    = AudioOutputMode.values[modeIdx.clamp(0, 2)];
      if (mode != AudioOutputMode.auto) _applyOutputMode(mode);

      LogService.log('AudioEngine', 'Dual-player (Android DSP) initialized – Slot A active');
    } else {
      LogService.log('AudioEngine', 'Dual-player initialized (web / non-Android) – Slot A active');
    }
  }

  // ── Handoff ───────────────────────────────────────────────────────────────

  /// Swaps active and standby slots.
  ///
  /// Called by [CrossfadeController] at the end of a crossfade, or by
  /// [AudioService] for an instant gapless swap.
  static void handoff() {
    _activeSlot = 1 - _activeSlot;
    LogService.log(
      'AudioEngine',
      'Handoff → Slot ${_activeSlot == 0 ? "A" : "B"} is now active',
    );
  }

  // ── Native effect attachment ──────────────────────────────────────────────

  /// Attaches native Android effects (BassBoost, Reverb, Virtualizer) to the
  /// given audio session.  The native side maintains per-session effect
  /// instances so both slots can have independent effect chains.
  static Future<void> _attachNativeEffects(int sessionId) async {
    try {
      final result = await _effectsChannel.invokeMapMethod<String, dynamic>(
        'attachEffects',
        {'sessionId': sessionId},
      );
      if (result != null) {
        _virtualizerSupported = result['virtualizerSupported'] as bool? ?? false;
        _bassBoostSupported   = result['bassBoostSupported']   as bool? ?? false;
        _reverbSupported      = result['reverbSupported']      as bool? ?? false;
      }
      LogService.log(
        'AudioEngine',
        'Native effects attached (session $sessionId) '
        'virt=$_virtualizerSupported bass=$_bassBoostSupported reverb=$_reverbSupported',
      );
    } catch (e) {
      LogService.warn('AudioEngine', 'attachEffects: $e');
    }
  }

  // ── Effect controls (applied to ALL slots) ────────────────────────────────

  /// Apply normalize to both slots so the standby player already has the
  /// correct gain before crossfade starts.
  static void applyNormalize({required bool enabled, double targetGainMb = 0.0}) {
    _slotA?.applyLoudnessEnhancer(enabled: enabled, targetGainMb: targetGainMb);
    _slotB?.applyLoudnessEnhancer(enabled: enabled, targetGainMb: targetGainMb);
  }

  /// Apply normalisation gain to a specific slot only (used by [AudioService]
  /// when per-track LUFS gain differs between active and preloaded track).
  static void applyNormalizeToSlot(
    PlayerSlot slot, {
    required bool enabled,
    double targetGainMb = 0.0,
  }) {
    slot.applyLoudnessEnhancer(enabled: enabled, targetGainMb: targetGainMb);
  }

  static Future<void> setSpatialEnabled(bool enabled, {int strength = 1000}) async {
    if (!isAndroid) return;
    try {
      await _effectsChannel.invokeMethod('setSpatialEnabled', {
        'enabled':  enabled,
        'strength': strength.clamp(0, 1000),
      });
    } catch (e) {
      LogService.warn('AudioEngine', 'setSpatialEnabled: $e');
    }
  }

  static Future<void> setBassBoost(int strength) async {
    if (!isAndroid) return;
    try {
      await _effectsChannel.invokeMethod(
        'setBassBoost', {'strength': strength.clamp(0, 1000)},
      );
    } catch (e) {
      LogService.warn('AudioEngine', 'setBassBoost: $e');
    }
  }

  static Future<void> setReverb(int preset) async {
    if (!isAndroid) return;
    try {
      await _effectsChannel.invokeMethod('setReverb', {'preset': preset});
    } catch (e) {
      LogService.warn('AudioEngine', 'setReverb: $e');
    }
  }

  // ── Speed / Pitch (active player only – reapplied on handoff) ────────────

  static void setSpeed(double speed) {
    try { activePlayer.setSpeed(speed); } catch (_) {}
  }

  static void setPitch(double factor) {
    try { activePlayer.setPitch(factor); } catch (_) {}
  }

  /// Reapply speed + pitch to the currently-active slot after a handoff.
  static void reapplySpeedPitch(double speed, double pitch) {
    try {
      activePlayer.setSpeed(speed);
      activePlayer.setPitch(pitch);
    } catch (_) {}
  }

  // ── Equalizer (active slot) ───────────────────────────────────────────────

  /// Restores saved EQ band gains on the given slot's equalizer.
  static Future<void> restoreEqBandsOnSlot(PlayerSlot slot) async {
    final eq = slot.equalizer;
    if (eq == null) return;
    try {
      final prefs  = await SharedPreferences.getInstance();
      final params = await eq.parameters;
      for (var i = 0; i < params.bands.length; i++) {
        final gain = prefs.getDouble('eqBand_$i');
        if (gain != null) await params.bands[i].setGain(gain);
      }
      final enabled = prefs.getBool('eqEnabled') ?? false;
      await eq.setEnabled(enabled);
    } catch (e) {
      LogService.warn('AudioEngine', 'restoreEqBands: $e');
    }
  }

  // ── Audio output mode ─────────────────────────────────────────────────────

  static Future<void> setAudioOutputMode(AudioOutputMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('audioOutputMode', mode.index);
    if (isAndroid) _applyOutputMode(mode);
    LogService.log('AudioEngine', 'Output mode: ${mode.name}');
  }

  static Future<AudioOutputMode> getAudioOutputMode() async {
    final prefs = await SharedPreferences.getInstance();
    final idx   = prefs.getInt('audioOutputMode') ?? 0;
    return AudioOutputMode.values[idx.clamp(0, 2)];
  }

  static void _applyOutputMode(AudioOutputMode mode) {
    try {
      _effectsChannel.invokeMethod('setAudioOutputMode', {'mode': mode.index});
    } catch (e) {
      LogService.warn('AudioEngine', 'setAudioOutputMode: $e');
    }
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
