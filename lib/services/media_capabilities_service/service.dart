// ignore_for_file: unawaited_futures

part of '../media_capabilities_service.dart';

/// Dart facade for Media3 advanced playback capabilities.
///
/// All heavy processing runs natively inside [Media3PlaybackService.kt].
/// This class:
///   • Owns [ValueNotifier]s for each setting (UI binds to these).
///   • Persists every setting to [SharedPreferences] under the 'mcap_' prefix.
///   • Forwards changes to the active engine via [PlaybackManager].
///   • Mirrors the native skip-silence and stereo-widening state streams so
///     the UI stays in sync with changes confirmed by the active engine.
///
/// No layer in this file may reference Media3PlaybackBridge directly.
/// All engine calls go through [PlaybackManager].
///
/// Lifecycle: call [initialize()] once in [main()] after [AudioEffectsService].
class MediaCapabilitiesService {
  MediaCapabilitiesService._();

  static const _kPrefix = 'mcap_';

  // ── ValueNotifiers (UI ↔ Service) ─────────────────────────────────────────

  /// Item 8: Software stereo widening via ChannelMixingAudioProcessor.
  ///
  /// Works in ExoPlayer's pipeline — not in AudioFlinger — so it applies
  /// correctly to both players during a crossfade overlap.
  static final ValueNotifier<bool> stereoWideningEnabled = ValueNotifier(false);
  static final ValueNotifier<double> stereoWideningStrength = ValueNotifier(
    0.5,
  );

  /// Reverb: software Schroeder room-reverb effect (damped comb + all-pass
  /// tail).
  ///
  /// Works in ExoPlayer's pipeline — not in AudioFlinger — so it applies
  /// correctly to both players during a crossfade overlap. intensity = 0
  /// is fully transparent (effect off).
  static final ValueNotifier<bool> reverbEnabled = ValueNotifier(false);
  static final ValueNotifier<double> reverbIntensity = ValueNotifier(0.5);

  /// Native speaker enhancement. It is intentionally a one-toggle/one-slider
  /// feature rather than exposing its internal filter controls.
  static final ValueNotifier<bool> acousticEngineEnabled = ValueNotifier(false);
  static final ValueNotifier<double> acousticEngineIntensity = ValueNotifier(
    0.5,
  );

  // ── Stream subscriptions (engine → Dart mirror) ───────────────────────────

  static StreamSubscription<Map<dynamic, dynamic>>? _stereoWideningSub;
  static StreamSubscription<Map<dynamic, dynamic>>? _reverbSub;

  // ── Acoustic Engine native push coalescing ───────────────────────────────
  //
  // The native processor rebuilds its whole per-stream coefficient snapshot
  // (five `nar_biquad_compute` calls, i.e. transcendentals) on the audio
  // thread every time the published intensity differs from the applied one —
  // see `acoustic_engine_processor.c`. A slider drag publishes one value per
  // tick, so pushing every tick straight through made the audio thread redo
  // that work dozens of times per second while also clearing the filter
  // history on each change (audible ticks).
  //
  // So the control-plane push is coalesced: [ValueNotifier]s and
  // SharedPreferences still update synchronously (the UI stays exact and the
  // value survives a crash), but the FFI publish is debounced so a drag
  // results in ONE rebuild once the finger settles. Explicit toggles bypass
  // the debounce entirely — on/off must never feel laggy.
  static const _acousticEnginePushDelay = Duration(milliseconds: 120);
  static Timer? _acousticEnginePushTimer;

  // ── Initialize ────────────────────────────────────────────────────────────

  /// Load persisted values, subscribe to engine state streams,
  /// then push every setting to the active engine so cold starts are in sync.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    stereoWideningEnabled.value =
        prefs.getBool('${_kPrefix}stereoEnabled') ?? false;
    stereoWideningStrength.value =
        prefs.getDouble('${_kPrefix}stereoStrength') ?? 0.5;
    // Reverb is stored under its own keys. The legacy echo (feedback-delay)
    // keys are read as a one-time migration fallback so existing users keep
    // their previously saved setting across upgrades.
    reverbEnabled.value =
        prefs.getBool('${_kPrefix}reverbEnabled') ??
        prefs.getBool('${_kPrefix}echoEnabled') ??
        false;
    reverbIntensity.value = _normalizeReverbIntensity(
      prefs.getDouble('${_kPrefix}reverbIntensity') ??
          prefs.getDouble('${_kPrefix}echoIntensity') ??
          0.5,
    );
    acousticEngineEnabled.value =
        prefs.getBool('${_kPrefix}acousticEngineEnabled') ?? false;
    acousticEngineIntensity.value = _normalizeReverbIntensity(
      prefs.getDouble('${_kPrefix}acousticEngineIntensity') ?? 0.5,
    );

    // ── Stereo widening ───────────────────────────────────────────────────────
    // Mirrors the engine confirmation after the processor matrix is applied.
    // Ensures `strength` is always the value the engine is actually using,
    // not just what was requested.
    _stereoWideningSub?.cancel();
    _stereoWideningSub = PlaybackManager.stereoWideningStream.listen((map) {
      final enabled = map['enabled'] as bool? ?? false;
      final strength = (map['strength'] as num?)?.toDouble() ?? 0.5;
      if (stereoWideningEnabled.value != enabled) {
        stereoWideningEnabled.value = enabled;
      }
      if (stereoWideningStrength.value != strength) {
        stereoWideningStrength.value = strength;
      }
    });

    // ── Reverb ───────────────────────────────────────────────────────────────
    // Mirrors the engine confirmation after the effect parameters are applied,
    // so the UI always shows what the engine is actually using.
    _reverbSub?.cancel();
    _reverbSub = PlaybackManager.reverbStream.listen((map) {
      final enabled = map['enabled'] as bool? ?? false;
      final intensity = _normalizeReverbIntensity(
        (map['intensity'] as num?)?.toDouble() ?? 0.5,
      );
      if (reverbEnabled.value != enabled) {
        reverbEnabled.value = enabled;
      }
      if (reverbIntensity.value != intensity) {
        reverbIntensity.value = intensity;
      }
    });

    // Push all settings to active engine on startup. This bypasses the
    // coalescing timer: it is a one-shot, and there is nothing to coalesce.
    _flushAcousticEnginePush();
    unawaited(_applyAll());

    LogService.log(
      'MediaCap',
      'Initialized — '
          'stereo=${stereoWideningEnabled.value}@${stereoWideningStrength.value} '
          'reverb=${reverbEnabled.value}@${reverbIntensity.value}',
    );
  }

  // Cold-start race fix — same root cause as AudioEffectsService.applyAll():
  // `Media3PlaybackService` doesn't exist until the user's first "play" /
  // "setQueue" call, so pushing settings unconditionally at Dart startup
  // races `onCreate()` and can hit `PlatformException(not_ready)`. Waiting
  // for the real readiness signal (instead of retrying/ignoring the failure)
  // means these calls run once the service has actually finished wiring.
  static Future<void> _applyAll() async {
    await PlaybackManager.waitForServiceReady();
    unawaited(
      PlaybackManager.setStereoWidening(
        enabled: stereoWideningEnabled.value,
        strength: stereoWideningStrength.value,
      ),
    );
    unawaited(
      PlaybackManager.setReverb(
        enabled: reverbEnabled.value,
        intensity: reverbIntensity.value,
      ),
    );
    PlaybackManager.setNativeAcousticEngine(
      enabled: acousticEngineEnabled.value,
      intensity: acousticEngineIntensity.value,
    );
  }

  // ── Setters ───────────────────────────────────────────────────────────────

  /// Item 8: Toggle stereo widening.  Sends current [stereoWideningStrength]
  /// alongside the enable flag so the engine can apply both atomically.
  static Future<void> setStereoWidening(bool value) async {
    stereoWideningEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kPrefix}stereoEnabled', value);
    unawaited(
      PlaybackManager.setStereoWidening(
        enabled: value,
        strength: stereoWideningStrength.value,
      ),
    );
    LogService.log('MediaCap', 'stereoWidening: $value');
  }

  /// Item 8: Adjust stereo width.  [strength] is clamped to [0.0, 1.0].
  static Future<void> setStereoWideningStrength(double value) async {
    final v = value.clamp(0.0, 1.0);
    stereoWideningStrength.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_kPrefix}stereoStrength', v);
    if (stereoWideningEnabled.value) {
      unawaited(PlaybackManager.setStereoWidening(enabled: true, strength: v));
    }
    LogService.log('MediaCap', 'stereoStrength: $v');
  }

  /// Reverb: Toggle the reverb effect. Sends current [reverbIntensity]
  /// alongside the enable flag so the engine can apply both atomically.
  static Future<void> setReverb(bool value) async {
    reverbEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kPrefix}reverbEnabled', value);
    unawaited(
      PlaybackManager.setReverb(
        enabled: value,
        intensity: reverbIntensity.value,
      ),
    );
    LogService.log('MediaCap', 'reverb: $value');
  }

  /// Reverb: Adjust reverb strength. [value] is clamped to [0.0, 1.0].
  static Future<void> setReverbIntensity(double value) async {
    final v = _normalizeReverbIntensity(value);
    reverbIntensity.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_kPrefix}reverbIntensity', v);
    if (reverbEnabled.value) {
      unawaited(PlaybackManager.setReverb(enabled: true, intensity: v));
    }
    LogService.log('MediaCap', 'reverbIntensity: $v');
  }

  /// Explicit on/off toggle for the Acoustic Engine. Pushes to the native
  /// processor immediately (no debounce): an enable/disable must not wait on
  /// a timer, and the native bypass is already a zero-copy store.
  static Future<void> setAcousticEngine(bool value) async {
    final changed = acousticEngineEnabled.value != value;
    acousticEngineEnabled.value = value;
    if (changed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${_kPrefix}acousticEngineEnabled', value);
    }
    _acousticEnginePushTimer?.cancel();
    _acousticEnginePushTimer = null;
    PlaybackManager.setNativeAcousticEngine(
      enabled: value,
      intensity: acousticEngineIntensity.value,
    );
    LogService.log('MediaCap', 'acousticEngine: $value');
  }

  /// Single entry point for the Acoustic Engine slider.
  ///
  /// Mirrors the "intensity drives enable" convention the other engine sliders
  /// use: 0 means off, any value above 0 turns the processor on. Folding both
  /// values into this one call means a drag writes at most one preference
  /// key per actual change instead of an enable write plus an intensity write
  /// on every single tick.
  ///
  /// The native publish is coalesced through [_scheduleAcousticEnginePush];
  /// see the field's docs for why the C side must not see every tick.
  static Future<void> setAcousticEngineIntensity(double value) async {
    final v = _normalizeReverbIntensity(value);
    final enable = v > 0;
    final intensityChanged = acousticEngineIntensity.value != v;
    final enableChanged = acousticEngineEnabled.value != enable;
    if (!intensityChanged && !enableChanged) return;

    acousticEngineIntensity.value = v;
    acousticEngineEnabled.value = enable;

    final prefs = await SharedPreferences.getInstance();
    if (intensityChanged) {
      await prefs.setDouble('${_kPrefix}acousticEngineIntensity', v);
    }
    if (enableChanged) {
      await prefs.setBool('${_kPrefix}acousticEngineEnabled', enable);
    }

    _scheduleAcousticEnginePush(enable, v);
    LogService.log('MediaCap', 'acousticEngineIntensity: $v (enabled: $enable)');
  }

  /// Coalesces the FFI publish for a slider drag. Repeated calls within
  /// [_acousticEnginePushDelay] collapse into a single native update, so the
  /// audio thread performs at most one coefficient rebuild per drag.
  static void _scheduleAcousticEnginePush(bool enabled, double intensity) {
    _acousticEnginePushTimer?.cancel();
    _acousticEnginePushTimer = Timer(_acousticEnginePushDelay, () {
      _acousticEnginePushTimer = null;
      PlaybackManager.setNativeAcousticEngine(
        enabled: enabled,
        intensity: intensity,
      );
    });
  }

  /// Applies any pending coalesced publish right away, if there is one.
  /// Used at startup (where there is nothing to coalesce) and on teardown.
  static void _flushAcousticEnginePush() {
    final timer = _acousticEnginePushTimer;
    if (timer == null) return;
    timer.cancel();
    _acousticEnginePushTimer = null;
    PlaybackManager.setNativeAcousticEngine(
      enabled: acousticEngineEnabled.value,
      intensity: acousticEngineIntensity.value,
    );
  }

  /// Keeps persisted, event-stream, and UI values safe for the native
  /// feedback processor. `clamp` alone preserves NaN, which would otherwise
  /// poison the reverb delay buffers through the platform channel.
  static double _normalizeReverbIntensity(double value) =>
      value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;

  // ── Query ─────────────────────────────────────────────────────────────────

  /// Item 6: Fetch accumulated [PlaybackStats] for the active player session.
  ///
  /// Returns null when the active engine does not support playback stats,
  /// or when no playback session has begun.
  ///
  /// Fields in the returned map:
  ///   `totalPlayTimeMs`      — milliseconds of audio actually played.
  ///   `totalBufferingTimeMs` — milliseconds spent buffering (local files → 0).
  ///   `totalRebufferCount`   — number of rebuffer events (local files → 0).
  ///   `totalErrorCount`      — number of playback errors during this session.
  static Future<Map<String, dynamic>?> getPlaybackStats() =>
      PlaybackManager.getPlaybackStats();

  // ── Dispose ───────────────────────────────────────────────────────────────

  static void dispose() {
    _flushAcousticEnginePush();
    _acousticEnginePushTimer = null;
    (_stereoWideningSub?.cancel())?.ignore();
    _stereoWideningSub = null;
    (_reverbSub?.cancel())?.ignore();
    _reverbSub = null;
  }
}
