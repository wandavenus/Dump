part of '../media_capabilities_service.dart';

/// Dart facade for the 8 new Media3 1.10.1 features.
///
/// All heavy processing runs natively inside [Media3PlaybackService.kt].
/// This class:
///   • Owns [ValueNotifier]s for each setting (UI binds to these).
///   • Persists every setting to [SharedPreferences] under the 'mcap_' prefix.
///   • Forwards changes to native via [Media3PlaybackBridge].
///   • Mirrors the native [skipSilenceStream] so the UI stays in sync with
///     changes made by other code paths (e.g. a future notification action).
///
/// Lifecycle: call [initialize()] once in [main()] after [AudioEffectsService].
class MediaCapabilitiesService {
  MediaCapabilitiesService._();

  static const _kPrefix = 'mcap_';

  // ── ValueNotifiers (UI ↔ Service) ─────────────────────────────────────────

  /// Item 1: Skip silence in ExoPlayer's SonicAudioProcessor.
  ///
  /// When enabled, ExoPlayer trims silent gaps between notes / tracks
  /// without changing the speed of the audio.  On Snapdragon 730 /
  /// Android 11 this is entirely software-based and ~0 % CPU overhead.
  static final ValueNotifier<bool> skipSilenceEnabled = ValueNotifier(false);

  /// Item 8: Software stereo widening via ChannelMixingAudioProcessor.
  ///
  /// Works in ExoPlayer's pipeline — not in AudioFlinger — so it applies
  /// correctly to both players during a crossfade overlap.
  /// Has no effect when tunneling is enabled (hardware bypasses the pipeline).
  static final ValueNotifier<bool>   stereoWideningEnabled  = ValueNotifier(false);
  static final ValueNotifier<double> stereoWideningStrength = ValueNotifier(0.5);

  /// Item 5: Audio tunneling — routes PCM directly from decoder to audio HAL.
  ///
  /// Bypasses the entire software effects chain (EQ, BassBoost, Virtualizer,
  /// Reverb, LoudnessEnhancer, ChannelMixingAudioProcessor).  Intended for a
  /// "pure playback" mode where the user wants minimal CPU/battery overhead.
  ///
  /// ⚠️  When this is true the UI should visually communicate that software
  /// effects and stereo widening are inactive.
  static final ValueNotifier<bool> tunnelingEnabled = ValueNotifier(false);

  // ── Stream subscription ───────────────────────────────────────────────────

  static StreamSubscription<bool>? _skipSilenceSub;

  // ── Initialize ────────────────────────────────────────────────────────────

  /// Load persisted values, mirror the native skip-silence stream, then
  /// push all settings to the native service so cold starts are in sync.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    skipSilenceEnabled.value     = prefs.getBool('${_kPrefix}skipSilence')  ?? false;
    stereoWideningEnabled.value  = prefs.getBool('${_kPrefix}stereoEnabled')  ?? false;
    stereoWideningStrength.value = prefs.getDouble('${_kPrefix}stereoStrength') ?? 0.5;
    tunnelingEnabled.value       = prefs.getBool('${_kPrefix}tunneling')    ?? false;

    // Mirror ExoPlayer's own skip-silence feedback (the native service emits
    // this whenever ExoPlayer confirms the change via onSkipSilenceEnabled-
    // Changed).  This keeps the toggle correct even if native overrides the
    // value for any reason.
    _skipSilenceSub?.cancel();
    _skipSilenceSub = Media3PlaybackBridge.skipSilenceStream.listen((v) {
      if (skipSilenceEnabled.value != v) skipSilenceEnabled.value = v;
    });

    // Push all settings to native on startup.
    unawaited(_applyAll());

    LogService.log('MediaCap', 'Initialized — skipSilence=${skipSilenceEnabled.value} '
        'stereo=${stereoWideningEnabled.value}@${stereoWideningStrength.value} '
        'tunneling=${tunnelingEnabled.value}');
  }

  static Future<void> _applyAll() async {
    unawaited(Media3PlaybackBridge.setSkipSilence(skipSilenceEnabled.value));
    unawaited(Media3PlaybackBridge.setStereoWidening(
      enabled:  stereoWideningEnabled.value,
      strength: stereoWideningStrength.value,
    ));
    unawaited(Media3PlaybackBridge.setTunnelingEnabled(tunnelingEnabled.value));
  }

  // ── Setters ───────────────────────────────────────────────────────────────

  /// Item 1: Toggle skip-silence.
  static Future<void> setSkipSilence(bool value) async {
    skipSilenceEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kPrefix}skipSilence', value);
    unawaited(Media3PlaybackBridge.setSkipSilence(value));
    LogService.log('MediaCap', 'skipSilence: $value');
  }

  /// Item 8: Toggle stereo widening.  Sends current [stereoWideningStrength]
  /// alongside the enable flag so native can apply both atomically.
  static Future<void> setStereoWidening(bool value) async {
    stereoWideningEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kPrefix}stereoEnabled', value);
    unawaited(Media3PlaybackBridge.setStereoWidening(
      enabled:  value,
      strength: stereoWideningStrength.value,
    ));
    LogService.log('MediaCap', 'stereoWidening: $value');
  }

  /// Item 8: Adjust stereo width.  [strength] is clamped to [0.0, 1.0].
  static Future<void> setStereoWideningStrength(double value) async {
    final v = value.clamp(0.0, 1.0);
    stereoWideningStrength.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_kPrefix}stereoStrength', v);
    if (stereoWideningEnabled.value) {
      unawaited(Media3PlaybackBridge.setStereoWidening(
        enabled:  true,
        strength: v,
      ));
    }
    LogService.log('MediaCap', 'stereoStrength: $v');
  }

  /// Item 5: Toggle audio tunneling.
  ///
  /// ⚠️  Enabling tunneling bypasses all software audio effects.
  /// The UI should display a warning when this is on.
  static Future<void> setTunnelingEnabled(bool value) async {
    tunnelingEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kPrefix}tunneling', value);
    unawaited(Media3PlaybackBridge.setTunnelingEnabled(value));
    LogService.log('MediaCap', 'tunneling: $value');
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// Item 6: Fetch accumulated [PlaybackStats] for the active player session.
  ///
  /// Returns null when the native service is not running or no playback
  /// session has begun (stats are only accumulated from the moment the first
  /// player listener is attached on service startup).
  ///
  /// Fields in the returned map:
  ///   `totalPlayTimeMs`      — milliseconds of audio actually played.
  ///   `totalBufferingTimeMs` — milliseconds spent buffering (local files → 0).
  ///   `totalRebufferCount`   — number of rebuffer events (local files → 0).
  ///   `totalErrorCount`      — number of playback errors during this session.
  static Future<Map<String, dynamic>?> getPlaybackStats() =>
      Media3PlaybackBridge.getPlaybackStats();

  // ── Dispose ───────────────────────────────────────────────────────────────

  static void dispose() {
    _skipSilenceSub?.cancel();
    _skipSilenceSub = null;
  }
}
