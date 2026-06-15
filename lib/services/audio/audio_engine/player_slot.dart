part of '../audio_engine.dart';

/// One independent playback slot (Player A or Player B).
///
/// Each slot owns its own [AudioPlayer] and – on Android – its own
/// [AndroidEqualizer] + [AndroidLoudnessEnhancer] DSP pipeline so that both
/// players can run simultaneously during crossfade with identical effect chains.
class PlayerSlot {
  final String name; // 'A' or 'B'

  final AudioPlayer player;
  final AndroidEqualizer? equalizer;
  final AndroidLoudnessEnhancer? loudnessEnhancer;

  StreamSubscription<int?>? _sessionSub;

  PlayerSlot._({
    required this.name,
    required this.player,
    this.equalizer,
    this.loudnessEnhancer,
  });

  // ── Factory ─────────────────────────────────────────────────────────────

  static PlayerSlot create(String name, {required bool isAndroid}) {
    if (isAndroid) {
      final eq  = AndroidEqualizer();
      final lhe = AndroidLoudnessEnhancer();
      final p   = AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: [lhe, eq],
        ),
      );
      return PlayerSlot._(name: name, player: p, equalizer: eq, loudnessEnhancer: lhe);
    }
    return PlayerSlot._(name: name, player: AudioPlayer());
  }

  // ── Session listener ─────────────────────────────────────────────────────

  /// Calls [onId] each time the Android audio-session ID is assigned or
  /// changes on this slot's player (used to re-attach native effects).
  void listenSessionId(void Function(int id) onId) {
    _sessionSub?.cancel();
    _sessionSub = player.androidAudioSessionIdStream
        .where((id) => id != null)
        .distinct()
        .listen((id) => onId(id!));
  }

  // ── Volume helpers ───────────────────────────────────────────────────────

  void setVolume(double v) {
    try { player.setVolume(v.clamp(0.0, 1.0)); } catch (_) {}
  }

  // ── Loudness enhancer ────────────────────────────────────────────────────

  /// Apply loudness normalisation to this slot.
  /// [targetGainMb] is in millibels (gainDb * 100).
  void applyLoudnessEnhancer({required bool enabled, double targetGainMb = 0.0}) {
    final lhe = loudnessEnhancer;
    if (lhe == null) {
      // Web / non-Android: simple volume fallback (attenuate only)
      if (!enabled) setVolume(1.0);
      return;
    }
    try {
      lhe.setTargetGain(targetGainMb);
      lhe.setEnabled(enabled);
    } catch (_) {}
  }

  // ── Stop and silence ─────────────────────────────────────────────────────

  Future<void> stopAndReset() async {
    try {
      setVolume(0.0);
      await player.stop();
    } catch (_) {}
  }

  // ── Dispose ──────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _sessionSub?.cancel();
    _sessionSub = null;
    try { await player.dispose(); } catch (_) {}
  }
}
