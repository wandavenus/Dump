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
  static final ValueNotifier<bool>   stereoWideningEnabled  = ValueNotifier(false);
  static final ValueNotifier<double> stereoWideningStrength = ValueNotifier(0.5);

  // ── Stream subscriptions (native → Dart mirror) ───────────────────────────

  static StreamSubscription<bool>?                     _skipSilenceSub;
  static StreamSubscription<Map<dynamic, dynamic>>?    _stereoWideningSub;

  // ── Initialize ────────────────────────────────────────────────────────────

  /// Load persisted values, subscribe to all three native state streams,
  /// then push every setting to the native service so cold starts are in sync.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    skipSilenceEnabled.value     = prefs.getBool('${_kPrefix}skipSilence')    ?? false;
    stereoWideningEnabled.value  = prefs.getBool('${_kPrefix}stereoEnabled')  ?? false;
    stereoWideningStrength.value = prefs.getDouble('${_kPrefix}stereoStrength') ?? 0.5;

    // ── Skip silence ─────────────────────────────────────────────────────────
    // Mirrors ExoPlayer's onSkipSilenceEnabledChanged callback so the toggle
    // is always correct even when native overrides the value for any reason
    // (e.g. a future ExoPlayer version that resets silence-skip on seek).
    _skipSilenceSub?.cancel();
    _skipSilenceSub = Media3PlaybackBridge.skipSilenceStream.listen((v) {
      if (skipSilenceEnabled.value != v) skipSilenceEnabled.value = v;
    });

    // ── Stereo widening ───────────────────────────────────────────────────────
    // Mirrors the StereoWidthManager confirmation after it has applied the
    // ChannelMixingMatrix to all live processors. This ensures `strength` is
    // always the value ExoPlayer is actually using, not just what was requested.
    _stereoWideningSub?.cancel();
    _stereoWideningSub = Media3PlaybackBridge.stereoWideningStream.listen((map) {
      final enabled  = map['enabled']  as bool?   ?? false;
      final strength = (map['strength'] as num?)?.toDouble() ?? 0.5;
      if (stereoWideningEnabled.value  != enabled)  stereoWideningEnabled.value  = enabled;
      if (stereoWideningStrength.value != strength) stereoWideningStrength.value = strength;
    });

    // Push all settings to native on startup.
    unawaited(_applyAll());

    LogService.log('MediaCap', 'Initialized — skipSilence=${skipSilenceEnabled.value} '
        'stereo=${stereoWideningEnabled.value}@${stereoWideningStrength.value}');
  }

  static Future<void> _applyAll() async {
    unawaited(Media3PlaybackBridge.setSkipSilence(skipSilenceEnabled.value));
    unawaited(Media3PlaybackBridge.setStereoWidening(
      enabled:  stereoWideningEnabled.value,
      strength: stereoWideningStrength.value,
    ));
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
    _stereoWideningSub?.cancel();
    _skipSilenceSub    = null;
    _stereoWideningSub = null;
  }
}
