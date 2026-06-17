part of '../audio_engine.dart';

/// Low-level audio hardware facade.
///
/// [DualPlayerManager] owns player lifecycle.  [AudioEngine] exposes a
/// stable [player] getter, keeps DSP references in sync via the
/// [_onPrimaryChanged] callback, and owns all native-effect channel calls.
class AudioEngine {
  AudioEngine._();

  static const MethodChannel _effectsChannel =
      MethodChannel('musicplayer/audio_effects');

  // ── Player references (kept in sync via _onPrimaryChanged) ─────────────────

  static AudioPlayer?             _player;
  static AndroidEqualizer?        _equalizer;
  static AndroidLoudnessEnhancer? _loudnessEnhancer;
  static StreamSubscription<int?>? _sessionSub;

  static bool _initialized = false;

  // Effect-support flags read from native on Android 11+.
  static bool _virtualizerSupported = false;
  static bool _bassBoostSupported   = false;
  static bool _reverbSupported      = false;

  // ── Native-effect retry state ───────────────────────────────────────────────
  //
  // On Android 11 the OS audio session may not be registered when the first
  // androidAudioSessionIdStream event fires.  We retry with exponential
  // back-off (50 → 100 → 200 → 400 ms) and stop as soon as one attempt
  // succeeds.  A new session ID cancels any pending retry for an old one.

  /// The last session ID for which effects were successfully attached.
  static int    _lastAttachedSessionId  = -1;
  /// Which session ID the current retry loop is working on.
  static int    _effectsRetrySessionId  = -1;
  /// How many retries have been issued for [_effectsRetrySessionId].
  static int    _effectsRetryCount      = 0;
  /// Pending retry timer (cancelled on new session ID or successful attach).
  static Timer? _effectsRetryTimer;

  // ── Public getters ──────────────────────────────────────────────────────────

  static AudioPlayer get player {
    assert(_initialized, 'AudioEngine.initialize() must be called first');
    return _player!;
  }

  static AndroidEqualizer?        get equalizer       => _equalizer;
  static AndroidLoudnessEnhancer? get loudnessEnhancer => _loudnessEnhancer;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get virtualizerSupported => _virtualizerSupported;
  static bool get bassBoostSupported   => _bassBoostSupported;
  static bool get reverbSupported      => _reverbSupported;

  // ── Initialization ─────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Register callbacks BEFORE DualPlayerManager.initialize() so the
    // first onPrimaryChanged fires with the callbacks already set.
    DualPlayerManager.onPrimaryChanged     = _onPrimaryChanged;
    DualPlayerManager.onSecondarySessionId = attachEffectsToSession;

    await DualPlayerManager.initialize();

    // Restore stored audio output mode.
    final prefs   = await SharedPreferences.getInstance();
    final modeIdx = prefs.getInt('audioOutputMode') ?? 0;
    final mode    = AudioOutputMode.values[modeIdx.clamp(0, 2)];
    if (mode != AudioOutputMode.auto) applyOutputModeNow(mode);

    LogService.log(
      'AudioEngine',
      isAndroid
          ? 'Initialized (Android DSP via DualPlayerManager)'
          : 'Initialized (web / non-Android)',
    );
  }

  // ── Primary-player change callback ─────────────────────────────────────────

  /// Called by [DualPlayerManager] whenever [primaryPlayer] changes
  /// (at init and on every promote).
  static void _onPrimaryChanged() {
    _player           = DualPlayerManager.primaryPlayer;
    _equalizer        = DualPlayerManager.primaryEqualizer;
    _loudnessEnhancer = DualPlayerManager.primaryLoudness;

    // Re-subscribe to the new primary's Android audio-session ID.
    _sessionSub?.cancel();
    if (isAndroid) {
      _sessionSub = _player!.androidAudioSessionIdStream
          .where((id) => id != null)
          .distinct()
          .listen((id) => _attachNativeEffects(id!));
    }

    LogService.verbose('AudioEngine', 'Active player reference updated');
  }

  // ── Native effect attachment ────────────────────────────────────────────────

  /// Called for BOTH primary (via [_onPrimaryChanged] listener) and
  /// secondary (via [DualPlayerManager.onSecondarySessionId]) so that
  /// native effects are attached before each player ever becomes primary.
  static Future<void> attachEffectsToSession(int sessionId) =>
      _attachNativeEffects(sessionId);

  /// Entry point: validates dedup / session-change before the first attempt.
  static Future<void> _attachNativeEffects(int sessionId) async {
    if (!isAndroid) return;

    // New session ID → cancel any in-flight retry loop for the old session.
    if (sessionId != _effectsRetrySessionId) {
      _effectsRetryTimer?.cancel();
      _effectsRetryTimer  = null;
      _effectsRetryCount  = 0;
      _effectsRetrySessionId = sessionId;
    }

    // Already attached to this session — nothing to do.
    if (sessionId == _lastAttachedSessionId) return;

    await _tryAttachEffects(sessionId);
  }

  /// Performs one attach attempt.  On failure schedules the next retry with
  /// exponential back-off (50 → 100 → 200 → 400 ms, max 4 attempts total).
  static Future<void> _tryAttachEffects(int sessionId) async {
    // Guard: a newer session may have arrived while this retry was queued.
    if (sessionId != _effectsRetrySessionId) return;

    const maxAttempts = 4;
    try {
      final result = await _effectsChannel.invokeMapMethod<String, dynamic>(
        'attachEffects',
        {'sessionId': sessionId},
      );
      // ── Success ──────────────────────────────────────────────────────────
      _lastAttachedSessionId = sessionId;
      _effectsRetryTimer?.cancel();
      _effectsRetryTimer = null;
      _effectsRetryCount = 0;
      _virtualizerSupported = result?['virtualizerSupported'] as bool? ?? false;
      _bassBoostSupported   = result?['bassBoostSupported']   as bool? ?? false;
      _reverbSupported      = result?['reverbSupported']      as bool? ?? false;
      LogService.log(
        'AudioEngine',
        'Native effects attached (session $sessionId) — '
        'virt=$_virtualizerSupported, bass=$_bassBoostSupported, '
        'reverb=$_reverbSupported',
      );
    } catch (e) {
      // ── Failure — schedule retry if budget remains ────────────────────────
      if (_effectsRetryCount < maxAttempts) {
        // Exponential back-off: 50 ms, 100 ms, 200 ms, 400 ms.
        final backoff = Duration(milliseconds: 50 * (1 << _effectsRetryCount));
        _effectsRetryCount++;
        LogService.warn(
          'AudioEngine',
          'attachEffects attempt $_effectsRetryCount/$maxAttempts failed '
          '— retry in ${backoff.inMilliseconds} ms: $e',
        );
        _effectsRetryTimer?.cancel();
        _effectsRetryTimer = Timer(
          backoff,
          () => unawaited(_tryAttachEffects(sessionId)),
        );
      } else {
        // Budget exhausted — log and stop so we don't loop forever.
        LogService.warn(
          'AudioEngine',
          'attachEffects gave up after $maxAttempts attempts '
          '(session $sessionId): $e',
        );
        _effectsRetryCount = 0;
      }
    }
  }

  // ── Native effect controls (called by AudioEffectsService) ─────────────────

  static Future<void> setSpatialEnabled(
      bool enabled, {int strength = 1000}) async {
    if (!isAndroid) return;
    try {
      await _effectsChannel.invokeMethod('setSpatialEnabled', {
        'enabled':  enabled,
        'strength': strength.clamp(0, 1000).toInt(),
      });
    } catch (e) {
      LogService.warn('AudioEngine', 'setSpatialEnabled: $e');
    }
  }

  static Future<void> setBassBoost(int strength) async {
    if (!isAndroid) return;
    try {
      await _effectsChannel
          .invokeMethod('setBassBoost', {'strength': strength.clamp(0, 1000)});
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

  // ── Audio output mode ──────────────────────────────────────────────────────

  static Future<void> setAudioOutputMode(AudioOutputMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('audioOutputMode', mode.index);
    if (isAndroid) applyOutputModeNow(mode);
    LogService.log('AudioEngine', 'Output mode: ${mode.name}');
  }

  static Future<AudioOutputMode> getAudioOutputMode() async {
    final prefs = await SharedPreferences.getInstance();
    final idx   = prefs.getInt('audioOutputMode') ?? 0;
    return AudioOutputMode.values[idx.clamp(0, 2)];
  }

  /// Applies output mode NOW via the native channel (no prefs write).
  static void applyOutputModeNow(AudioOutputMode mode) {
    try {
      _effectsChannel
          .invokeMethod('setAudioOutputMode', {'mode': mode.index});
    } catch (e) {
      LogService.warn('AudioEngine', 'setAudioOutputMode: $e');
    }
  }

  // ── Normalize (LoudnessEnhancer + ReplayGain volume) ─────────────────────

  /// Applies loudness normalization to the active player.
  ///
  /// On Android: uses [AndroidLoudnessEnhancer] with [targetGainMb].
  /// On non-Android / web: approximates via player volume clamped to [0.1, 1.0].
  ///
  /// [targetGainMb] is in millibels (100 mb = 1 dB).  Pass 0 for neutral.
  static void applyNormalize({
    required bool enabled,
    double targetGainMb = 0.0,
  }) {
    final enhancer = _loudnessEnhancer;
    if (enhancer == null) {
      // Non-Android (web) fallback: rough volume approximation.
      if (!enabled) {
        try { _player?.setVolume(1.0); } catch (_) {}
        return;
      }
      // Convert mb → linear scale: volume = 10^(gainMb / 2000)
      final gainDb     = targetGainMb / 100.0;
      final linearGain = _dbToLinear(gainDb);
      final volume     = linearGain.clamp(0.1, 1.0);
      try { _player?.setVolume(volume); } catch (e) {
        LogService.warn('AudioEngine', 'fallback volume: $e');
      }
      return;
    }
    try {
      if (enabled) {
        // AndroidLoudnessEnhancer accepts millibels; clamp to ±2400 mb (±24 dB).
        final clamped = targetGainMb.clamp(-2400.0, 2400.0);
        enhancer.setTargetGain(clamped);
        enhancer.setEnabled(true);
      } else {
        enhancer.setTargetGain(0.0);
        enhancer.setEnabled(false);
      }
    } catch (e) {
      LogService.warn('AudioEngine', 'applyNormalize: $e');
    }
  }

  static double _dbToLinear(double db) {
    if (db == 0.0) return 1.0;
    // 10^(db/20) via series expansion (avoids dart:math import)
    final x = db / 20.0;
    return _pow10(x);
  }

  static double _pow10(double x) {
    // e^(x * ln10); ln10 ≈ 2.302585092994046
    const ln10 = 2.302585092994046;
    return _exp(x * ln10);
  }

  static double _exp(double x) {
    // Taylor series for e^x — accurate enough for small |x|
    var result = 1.0;
    var term   = 1.0;
    for (var i = 1; i <= 30; i++) {
      term   *= x / i;
      result += term;
    }
    return result;
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    _sessionSub?.cancel();
    _sessionSub = null;
    // Cancel any pending native-effect retry so no Timer fires after dispose.
    _effectsRetryTimer?.cancel();
    _effectsRetryTimer     = null;
    _effectsRetryCount     = 0;
    _effectsRetrySessionId = -1;
    _lastAttachedSessionId = -1;
    await DualPlayerManager.dispose();
    _player           = null;
    _equalizer        = null;
    _loudnessEnhancer = null;
    _initialized      = false;
    LogService.log('AudioEngine', 'Disposed');
  }
}
