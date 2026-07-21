part of '../playback_manager.dart';

// ── Native DSP pipeline (Phase 4) ─────────────────────────────────────────
//
// The C-side DSP pipeline (dsp_pipeline.c + gain_processor.c) is
// architecture-only in Phase 4: the pipeline and gain processor are fully
// implemented but not yet wired into Media3's audio thread. Controls here
// let future UI / audio-engine code configure the pipeline without
// importing native_audio_runtime directly.

  /// Whether the native DSP pipeline initialized successfully on this device.
  static bool get nativeDspAvailable =>
      NativeDspPipeline.instance.isInitialized;

  // ── Fail-open guard ───────────────────────────────────────────────────────
  //
  // Every native DSP call below (ReplayGain, Loudness Normalization, Gain,
  // Compressor, Limiter, Crossfeed, Soft Clipper) MUST pass through
  // [_dspGuard] before touching `bindings.nar_*` / the `Native*` facades.
  //
  // Rationale: the native runtime can fail to load for reasons entirely
  // outside app logic (missing device support, a native build/link defect,
  // web/unsupported platform). When that happens [NativeDspPipeline.isInitialized]
  // is `false` and EVERY `bindings.nar_*` call becomes unsafe to make — some
  // native toolchains throw on first symbol resolution rather than failing
  // silently. Native DSP is always optional; Media3 playback must never be
  // blocked, delayed, or aborted by a native DSP failure. This is the single
  // centralized choke point for that contract — do not call the `Native*`
  // facades or `bindings.nar_*` from anywhere else in the app (see
  // NATIVE_BRIDGES.md).
  static bool _dspUnavailableWarned = false;

  /// Returns `true` when it is safe to call into the native DSP pipeline.
  /// Returns `false` (and logs a single, non-spammy warning) when the
  /// pipeline never initialized — callers must skip the native call and
  /// return a safe default instead of touching `bindings.nar_*`.
  static bool _dspGuard(String callSite) {
    if (NativeDspPipeline.instance.isInitialized) return true;
    if (!_dspUnavailableWarned) {
      _dspUnavailableWarned = true;
      LogService.log(
        'PlaybackManager',
        'Native DSP pipeline unavailable — DSP calls are no-ops from here on '
        '(fail-open). First skipped call: $callSite',
        level: LogLevel.warning,
      );
    }
    return false;
  }

  /// Set the gain processor's target gain in dBFS (clamped to [-96, +24]).
  /// Thread-safe — safe to call from any isolate. No-op when the native DSP
  /// pipeline is unavailable.
  static void setNativeGainDb(double gainDb) {
    if (!_dspGuard('setNativeGainDb')) return;
    NativeDspPipeline.instance.setGainDb(gainDb);
  }

  /// Current native gain in dBFS. `0.0` (unity) when the pipeline is
  /// unavailable.
  static double get nativeGainDb =>
      _dspGuard('nativeGainDb') ? NativeDspPipeline.instance.gainDb : 0.0;

  /// Enable (`true`) or disable (`false`) the gain processor's zero-copy
  /// bypass mode. When bypassed, audio passes through unmodified. No-op when
  /// the native DSP pipeline is unavailable.
  static void setNativeGainBypass(bool bypass) {
    if (!_dspGuard('setNativeGainBypass')) return;
    NativeDspPipeline.instance.setGainBypass(bypass);
  }

  /// Whether the native gain processor is currently bypassed. `true`
  /// (effectively bypassed) when the pipeline is unavailable.
  static bool get nativeGainBypass => !_dspGuard('nativeGainBypass') ||
      NativeDspPipeline.instance.gainBypass;

  /// Enable or disable a specific native DSP processor by its C id
  /// (e.g. `'dsp.gain'`). Thread-safe. No-op when the pipeline is unavailable.
  static void setNativeDspProcessorEnabled(String id,
      {required bool enabled}) {
    if (!_dspGuard('setNativeDspProcessorEnabled($id)')) return;
    NativeDspPipeline.instance.setProcessorEnabled(id, enabled: enabled);
  }

  /// Whether the named native DSP processor is currently enabled. `false`
  /// when the pipeline is unavailable.
  static bool isNativeDspProcessorEnabled(String id) =>
      _dspGuard('isNativeDspProcessorEnabled($id)') &&
      NativeDspPipeline.instance.isProcessorEnabled(id);

  /// Number of native DSP processors registered in the pipeline.
  static int get nativeDspProcessorCount =>
      NativeDspPipeline.instance.processorCount;

  /// Ids of every registered native DSP processor, in processing order.
  static List<String> get nativeDspProcessorIds => [
        for (var i = 0; i < NativeDspPipeline.instance.processorCount; i++)
          NativeDspPipeline.instance.processorIdAt(i) ?? '',
      ];

  // Native Parametric EQ (Phase 5) was removed — the legacy Android system
  // Equalizer (via Media3PlaybackBridge.getEqualizerParameters/
  // setEqualizerBandGain) is now the sole EQ backend. See
  // `.agents/memory/eq-silent-attach-failure.md` for background.

  /// Release native module and DSP pipeline resources. Safe to call even
  /// if never initialized.
  static Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await NativeDspPipeline.instance.dispose();
    await NativeModuleRegistry.disposeAll();
    _initialized = false;
  }

  // ── Native DSP: Dynamics Processing (Phase 6) ────────────────────────────
  //
  // Signal chain (Phase 6): dsp.gain → dsp.compressor → dsp.limiter
  //                         → dsp.soft_clipper → AudioTrack
  //
  // All methods delegate to the singleton facades in native_audio_runtime.
  // The UI must never import these facades directly — always use PlaybackManager.
  //
  // Sample rate: pass the current value from audioFormatStream to all
  // setParams() calls. If the sample rate changes between tracks, re-apply
  // parameters with the new rate to keep time constants accurate.

  // ── Compressor ────────────────────────────────────────────────────────────

  /// Whether the native compressor is available (pipeline initialized).
  static bool get nativeCompressorAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Configure all compressor parameters. Safe to call during playback.
  ///
  /// [thresholdDb]  : Default −20 dBFS. Range (−96, 0).
  /// [ratio]        : Default 4.0. Range [1.001, 100]. 1.0 = no compression.
  /// [attackMs]     : Default 10.0 ms. Range [0.1, 500].
  /// [releaseMs]    : Default 100.0 ms. Range [1, 2000].
  /// [kneeDb]       : Default 6.0 dB. Range [0, 24]. 0 = hard knee.
  /// [makeupGainDb] : Default 0.0 dBFS. Range [−24, 24].
  /// [sampleRate]   : Current playback sample rate. 0 → 48000 Hz fallback.
  static int setNativeCompressorParams({
    double thresholdDb  = -20.0,
    double ratio        =   4.0,
    double attackMs     =  10.0,
    double releaseMs    = 100.0,
    double kneeDb       =   6.0,
    double makeupGainDb =   0.0,
    double sampleRate   = 48000.0,
  }) {
    if (!_dspGuard('setNativeCompressorParams')) {
      return NativeRuntimeStatus.notInitialized.index;
    }
    return NativeCompressor.instance.setParams(
      thresholdDb:  thresholdDb,
      ratio:        ratio,
      attackMs:     attackMs,
      releaseMs:    releaseMs,
      kneeDb:       kneeDb,
      makeupGainDb: makeupGainDb,
      sampleRate:   sampleRate,
    );
  }

  /// Enable (`false`) or bypass (`true`) the compressor. No-op when the
  /// pipeline is unavailable.
  static void setNativeCompressorBypass(bool bypass) {
    if (!_dspGuard('setNativeCompressorBypass')) return;
    NativeCompressor.instance.setBypass(bypass);
  }

  /// Whether the compressor bypass is currently active. `true` (effectively
  /// bypassed) when the pipeline is unavailable.
  static bool get nativeCompressorBypass =>
      !_dspGuard('nativeCompressorBypass') || NativeCompressor.instance.bypass;

  // ── Limiter ───────────────────────────────────────────────────────────────

  /// Whether the native limiter is available (pipeline initialized).
  static bool get nativeLimiterAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Configure the limiter. Safe to call during playback.
  ///
  /// [thresholdDb] : Ceiling in dBFS. Default −1.0. Must be < 0.
  /// [releaseMs]   : Gain recovery time in ms. Default 50.0. Range [1, 1000].
  /// [sampleRate]  : Current playback sample rate. 0 → 48000 Hz fallback.
  static int setNativeLimiterParams({
    double thresholdDb = -1.0,
    double releaseMs   = 50.0,
    double sampleRate  = 48000.0,
  }) {
    if (!_dspGuard('setNativeLimiterParams')) {
      return NativeRuntimeStatus.notInitialized.index;
    }
    return NativeLimiter.instance.setParams(
      thresholdDb: thresholdDb,
      releaseMs:   releaseMs,
      sampleRate:  sampleRate,
    );
  }

  /// Enable (`false`) or bypass (`true`) the limiter. No-op when the
  /// pipeline is unavailable.
  static void setNativeLimiterBypass(bool bypass) {
    if (!_dspGuard('setNativeLimiterBypass')) return;
    NativeLimiter.instance.setBypass(bypass);
  }

  /// Whether the limiter bypass is currently active. `true` (effectively
  /// bypassed) when the pipeline is unavailable.
  static bool get nativeLimiterBypass =>
      !_dspGuard('nativeLimiterBypass') || NativeLimiter.instance.bypass;

  /// Look-ahead frames the limiter uses (63 = ~1.3 ms at 48 kHz). `0` when
  /// the pipeline is unavailable.
  static int get nativeLimiterLookaheadFrames => _dspGuard(
        'nativeLimiterLookaheadFrames',
      )
      ? NativeLimiter.instance.lookaheadFrames
      : 0;

  // ── ReplayGain (Phase 8) ──────────────────────────────────────────────────

  /// Whether the native ReplayGain DSP processor is available.
  static bool get nativeReplayGainAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Apply a ReplayGain gain value to the native DSP pipeline slot 1.
  ///
  /// [gainDb]                : raw metadata gain in dBFS plus any user preamp
  ///                           offset. Clamped to [−24, +24] by the C layer.
  /// [peakLinear]            : track/album peak in linear scale (e.g. 1.05).
  ///                           Pass 0.0 when no peak data is available.
  /// [useClippingProtection] : when `true` and [peakLinear] > 0, the native
  ///                           layer caps effective gain so that
  ///                           `gain_linear × peak_linear ≤ 1.0`.
  ///
  /// Thread-safe — effective linear gain stored atomically; audio thread picks
  /// it up on its next render cycle without blocking.
  ///
  /// This is a **fail-open** call: when the native DSP pipeline never
  /// initialized (missing device support, native build issue, unsupported
  /// platform), this returns [NativeRuntimeStatus.notInitialized]'s index
  /// immediately without touching `bindings.nar_*` — it never throws, so it
  /// can never block playback. See [_dspGuard].
  static int setNativeReplayGain({
    required double gainDb,
    double peakLinear = 0.0,
    bool useClippingProtection = true,
  }) {
    if (!_dspGuard('setNativeReplayGain')) {
      return NativeRuntimeStatus.notInitialized.index;
    }
    return NativeReplayGain.instance.setGain(
      gainDb: gainDb,
      peakLinear: peakLinear,
      useClippingProtection: useClippingProtection,
    );
  }

  /// Bypass (`true`) or engage (`false`) the native ReplayGain DSP processor.
  /// Thread-safe atomic store. No-op (never throws) when the pipeline is
  /// unavailable.
  static void setNativeReplayGainBypass(bool bypass) {
    if (!_dspGuard('setNativeReplayGainBypass')) return;
    NativeReplayGain.instance.setBypass(bypass);
  }

  /// `true` when the native ReplayGain processor is bypassed (gain not
  /// applied). Also `true` (effectively bypassed) when the pipeline is
  /// unavailable.
  static bool get nativeReplayGainBypassed =>
      !_dspGuard('nativeReplayGainBypassed') ||
      NativeReplayGain.instance.bypass;

  // ── Loudness Normalization (Phase 8.5) ────────────────────────────────────

  /// Whether the native Loudness Normalization DSP processor is available.
  static bool get nativeLoudnessNormAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Set the target output loudness in LUFS.
  ///
  /// Typical values: −23.0 (EBU R128 broadcast), −16.0 (podcast), −14.0
  /// (streaming). Clamped to [−36, −6] by the C layer.
  /// Takes effect on the next 85 ms measurement boundary (UPDATE_FRAMES).
  /// No-op when the pipeline is unavailable.
  static void setNativeLoudnessNormTargetLufs(double lufs) {
    if (!_dspGuard('setNativeLoudnessNormTargetLufs')) return;
    NativeLoudnessNorm.instance.setTargetLufs(lufs);
  }

  /// Bypass (`true`) or engage (`false`) the Loudness Normalization processor.
  /// Thread-safe atomic store. No-op when the pipeline is unavailable.
  static void setNativeLoudnessNormBypass(bool bypass) {
    if (!_dspGuard('setNativeLoudnessNormBypass')) return;
    NativeLoudnessNorm.instance.setBypass(bypass);
  }

  /// `true` when the Loudness Normalization processor is bypassed. Also
  /// `true` (effectively bypassed) when the pipeline is unavailable.
  static bool get nativeLoudnessNormBypassed =>
      !_dspGuard('nativeLoudnessNormBypassed') ||
      NativeLoudnessNorm.instance.bypass;

  /// Update the K-weighting coefficients for a new sample rate.
  /// Call when ExoPlayer reports a sample-rate change between tracks. No-op
  /// when the pipeline is unavailable.
  static void setNativeLoudnessSampleRate(int sampleRate) {
    if (!_dspGuard('setNativeLoudnessSampleRate')) return;
    NativeLoudnessNorm.instance.setSampleRate(sampleRate);
  }

  /// Current short-term LUFS reading from the analyzer.
  /// Returns −99.0 before the first 85 ms window completes, when bypassed,
  /// or when the pipeline is unavailable.
  static double get nativeLoudnessMeasuredLufs =>
      _dspGuard('nativeLoudnessMeasuredLufs')
          ? NativeLoudnessNorm.instance.measuredLufs
          : -99.0;

  /// Current smooth gain applied to the audio stream, in dBFS.
  /// Positive = boost, negative = attenuation. 0.0 when bypassed or when the
  /// pipeline is unavailable.
  static double get nativeLoudnessAppliedGainDb =>
      _dspGuard('nativeLoudnessAppliedGainDb')
          ? NativeLoudnessNorm.instance.appliedGainDb
          : 0.0;

  /// Reset the loudness analyzer and smooth gain back to unity.
  /// Must be called on every track change so each track is measured fresh.
  /// No-op when the pipeline is unavailable.
  static void resetNativeLoudnessNorm() {
    if (!_dspGuard('resetNativeLoudnessNorm')) return;
    NativeLoudnessNorm.instance.reset();
  }

  // ── Soft Clipper ──────────────────────────────────────────────────────────

  /// Whether the native soft clipper is available (pipeline initialized).
  static bool get nativeSoftClipperAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Set the soft-clip threshold in dBFS. Default: −0.5 dBFS.
  /// Samples below the threshold pass through unchanged; samples above are
  /// shaped toward 0 dBFS via a tanh curve. Range: [−12, −0.001).
  static void setNativeSoftClipperThresholdDb(double thresholdDb) {
    if (!_dspGuard('setNativeSoftClipperThresholdDb')) return;
    NativeSoftClipper.instance.setThresholdDb(thresholdDb);
  }

  /// Current soft-clip threshold in dBFS. `0.0` when the pipeline is
  /// unavailable.
  static double get nativeSoftClipperThresholdDb =>
      _dspGuard('nativeSoftClipperThresholdDb')
          ? NativeSoftClipper.instance.thresholdDb
          : 0.0;

  /// Enable (`false`) or bypass (`true`) the soft clipper. No-op when the
  /// pipeline is unavailable.
  static void setNativeSoftClipperBypass(bool bypass) {
    if (!_dspGuard('setNativeSoftClipperBypass')) return;
    NativeSoftClipper.instance.setBypass(bypass);
  }

  /// Whether the soft clipper bypass is currently active. `true`
  /// (effectively bypassed) when the pipeline is unavailable.
  static bool get nativeSoftClipperBypass =>
      !_dspGuard('nativeSoftClipperBypass') ||
      NativeSoftClipper.instance.bypass;

  // ── Native DSP: Crossfeed / Stereo Processing (Phase 7) ──────────────────
  //
  // Signal chain (Phase 7): dsp.gain → dsp.compressor →
  //                          dsp.crossfeed → dsp.limiter → dsp.soft_clipper
  //
  // Crossfeed improves headphone listening by blending a lowpass-filtered
  // version of each channel into the opposite channel, reducing the unnatural
  // channel isolation of headphones and reproducing the acoustic coupling of
  // speakers. Only the L and R channels are affected; mono/surround channels
  // pass through unchanged.
  //
  // All methods delegate directly to [NativeCrossfeed.instance]. The UI must
  // not import that class — use only these PlaybackManager statics.

  /// Whether the crossfeed processor is available on this device.
  /// `true` on Android (native FFI active); `false` on web/unsupported.
  static bool get nativeCrossfeedAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Configure all crossfeed parameters in one call.
  ///
  /// Parameters are pre-computed on the calling thread (biquad coefficient
  /// computation via sinf/cosf) and adopted lock-free by the audio thread on
  /// its next render cycle — no audible interruption.
  ///
  /// [amount]    : Crossfeed blend [0, 1]. Default 0.3. 0 = off.
  /// [cutoffHz]  : LP cutoff for cross path [100, 2000] Hz. Default 700.
  /// [hfCompDb]  : HF shelf gain [0, 12] dB. Default 3.0.
  /// [hfCompHz]  : HF shelf corner [1000, 16000] Hz. Default 4000.
  /// [width]     : Stereo width after mixing [0, 2]. Default 1.0.
  /// [sampleRate]: Current playback sample rate. 0 → 48000 Hz fallback.
  static int setNativeCrossfeedParams({
    double amount = 0.3,
    double cutoffHz = 700.0,
    double hfCompDb = 3.0,
    double hfCompHz = 4000.0,
    double width = 1.0,
    double sampleRate = 48000.0,
  }) {
    if (!_dspGuard('setNativeCrossfeedParams')) {
      return NativeRuntimeStatus.notInitialized.index;
    }
    return NativeCrossfeed.instance.setParams(
      amount: amount,
      cutoffHz: cutoffHz,
      hfCompDb: hfCompDb,
      hfCompHz: hfCompHz,
      width: width,
      sampleRate: sampleRate,
    );
  }

  /// Enable (`false`) or bypass (`true`) the crossfeed processor.
  /// Thread-safe — may be called while audio is rendering. No-op when the
  /// pipeline is unavailable.
  static void setNativeCrossfeedBypass(bool bypass) {
    if (!_dspGuard('setNativeCrossfeedBypass')) return;
    NativeCrossfeed.instance.setBypass(bypass);
  }

  /// Whether the crossfeed bypass is currently active. `true` (effectively
  /// bypassed) when the pipeline is unavailable.
  static bool get nativeCrossfeedBypass =>
      !_dspGuard('nativeCrossfeedBypass') || NativeCrossfeed.instance.bypass;
