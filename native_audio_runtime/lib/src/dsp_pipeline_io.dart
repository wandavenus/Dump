/// Real `dart:ffi`-backed DSP pipeline and AudioBuffer wrappers (Phase 4).
/// Selected by the conditional export in `native_audio_runtime.dart` — never
/// import this file directly; use `package:native_audio_runtime/native_audio_runtime.dart`.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

import '../native_audio_runtime_bindings_generated.dart' as bindings;
import 'runtime_types.dart';

// ── NativeAudioBuffer ─────────────────────────────────────────────────────────

/// Dart wrapper around a native `NarAudioBuffer` (interleaved float32 PCM).
///
/// **Lifecycle**: call [create] to allocate; call [destroy] exactly once when
/// done. Using any property after [destroy] violates the contract (debug-mode
/// assertion fires). Dart GC does NOT free the native allocation — [destroy]
/// is mandatory.
///
/// **Ownership**: Dart owns the buffer's lifetime. The native DSP pipeline
/// processes it in-place via [NativeDspPipeline.processBuffer] without taking
/// ownership.
///
/// **Zero-copy data access**: [data] returns a [Float32List] backed directly by
/// the native heap allocation — writes are visible to C immediately, and C
/// writes (from [NativeDspPipeline.processBuffer]) are visible in Dart
/// immediately after the call returns. No intermediate copy.
class NativeAudioBuffer {
  final ffi.Pointer<bindings.NarAudioBuffer> _ptr;
  bool _destroyed = false;

  NativeAudioBuffer._(this._ptr);

  /// Allocate an interleaved float32 PCM buffer.
  ///
  /// [capacityFrames] and [frameCount] start equal — call [setFrameCount] to
  /// mark fewer valid frames without reallocating.
  ///
  /// Returns `null` if allocation fails or any argument is invalid.
  static NativeAudioBuffer? create({
    required int capacityFrames,
    required int channelCount,
    required int sampleRate,
  }) {
    final ptr = bindings.nar_audio_buffer_create(
      capacityFrames,
      channelCount,
      sampleRate,
      0, // NAR_SAMPLE_FORMAT_FLOAT32
    );
    if (ptr == ffi.nullptr) return null;
    return NativeAudioBuffer._(ptr);
  }

  /// Free the native allocation. Must be called exactly once per buffer.
  /// Safe to call more than once (subsequent calls are no-ops).
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    bindings.nar_audio_buffer_destroy(_ptr);
  }

  /// View of the interleaved sample data as a [Float32List].
  ///
  /// This is a direct window into native memory — mutations are immediately
  /// visible on the C side (and vice-versa). The list length is
  /// `capacityFrames × channelCount`; valid sample count is
  /// `frameCount × channelCount`.
  ///
  /// Valid only while this buffer is alive (before [destroy]).
  Float32List get data {
    _assertAlive();
    final dataPtr = bindings.nar_audio_buffer_data(_ptr);
    if (dataPtr == ffi.nullptr) return Float32List(0);
    final total = bindings.nar_audio_buffer_capacity_frames(_ptr) *
        bindings.nar_audio_buffer_channel_count(_ptr);
    return dataPtr.asTypedList(total);
  }

  int get capacityFrames {
    _assertAlive();
    return bindings.nar_audio_buffer_capacity_frames(_ptr);
  }

  int get frameCount {
    _assertAlive();
    return bindings.nar_audio_buffer_frame_count(_ptr);
  }

  /// Narrow the number of valid frames to [n] (must be in [0, capacityFrames]).
  /// Returns a native status code (0 = OK).
  int setFrameCount(int n) {
    _assertAlive();
    return bindings.nar_audio_buffer_set_frame_count(_ptr, n);
  }

  int get channelCount {
    _assertAlive();
    return bindings.nar_audio_buffer_channel_count(_ptr);
  }

  int get sampleRate {
    _assertAlive();
    return bindings.nar_audio_buffer_sample_rate(_ptr);
  }

  /// Optional playback-position timestamp in microseconds. Pure metadata —
  /// not interpreted by the pipeline.
  int get timestampUs {
    _assertAlive();
    return bindings.nar_audio_buffer_timestamp_us(_ptr);
  }

  void setTimestampUs(int us) {
    _assertAlive();
    bindings.nar_audio_buffer_set_timestamp_us(_ptr, us);
  }

  /// Raw native pointer — pass to [NativeDspPipeline.processBuffer].
  /// Valid only while this buffer is alive.
  ffi.Pointer<bindings.NarAudioBuffer> get nativePointer {
    _assertAlive();
    return _ptr;
  }

  void _assertAlive() {
    assert(!_destroyed, 'NativeAudioBuffer used after destroy()');
  }
}

// ── NativeDspPipeline ─────────────────────────────────────────────────────────

/// Dart facade over the native C DSP pipeline (`src/dsp_pipeline.h`).
///
/// **Architecture**: `PlaybackManager` is the only sanctioned caller of these
/// methods from the app layer — do not import this class directly from UI or
/// service code. The pipeline is not yet wired into Media3's audio path in
/// Phase 4; it runs as a standalone chain that can be exercised via
/// [processBuffer] (primarily for testing).
///
/// **Threading**: [setGainDb], [setGainBypass], [setProcessorEnabled] are
/// thread-safe (backed by C11 atomics). [processBuffer] and [reset] must be
/// called from a single audio thread.
///
/// **Lifecycle**: call [initialize] once (after [NativeAudioRuntime.initialize]),
/// use the knobs, call [dispose] on shutdown. Idempotent — calling
/// [initialize] or [dispose] more than once is safe.
class NativeDspPipeline {
  NativeDspPipeline._();

  static final NativeDspPipeline instance = NativeDspPipeline._();

  bool _initialized = false;

  /// Whether [initialize] has completed successfully (Dart-tracked).
  bool get isInitialized => _initialized;

  /// Whether the C DSP pipeline is initialized, queried directly from native
  /// state. Normally mirrors [isInitialized]; useful for diagnostics and for
  /// verifying that the Dart and C lifecycle are in sync.
  bool get isInitializedNative =>
      bindings.nar_dsp_pipeline_is_initialized() != 0;

  /// Initialize the C DSP pipeline and register built-in processors:
  ///   1. dsp.gain  — Phase 4 gain / volume stage
  ///   2. dsp.peq   — Phase 5 parametric equalizer
  ///
  /// Idempotent — safe to call more than once (e.g. after a hot restart).
  Future<void> initialize() async {
    if (_initialized) return;

    final pipelineStatus =
        NativeRuntimeStatus.fromCode(bindings.nar_dsp_pipeline_init());
    if (pipelineStatus != NativeRuntimeStatus.ok) {
      throw NativeRuntimeException(
          'NativeDspPipeline.initialize (pipeline)', pipelineStatus);
    }

    final gainStatus = NativeRuntimeStatus.fromCode(
        bindings.nar_gain_processor_register_internal());
    // duplicateModule is expected on hot restart (processor already registered).
    if (gainStatus != NativeRuntimeStatus.ok &&
        gainStatus != NativeRuntimeStatus.duplicateModule) {
      throw NativeRuntimeException(
          'NativeDspPipeline.initialize (gain)', gainStatus);
    }

    // Phase 8: ReplayGain (slot 1, between gain and peq).
    // Starts bypassed — PlaybackManager engages it after resolving metadata.
    final replayGainStatus = NativeRuntimeStatus.fromCode(
        bindings.nar_replaygain_processor_register_internal());
    if (replayGainStatus != NativeRuntimeStatus.ok &&
        replayGainStatus != NativeRuntimeStatus.duplicateModule) {
      throw NativeRuntimeException(
          'NativeDspPipeline.initialize (replaygain)', replayGainStatus);
    }

    // Phase 5: register the Parametric EQ processor (slot 2, after replaygain).
    final peqStatus = NativeRuntimeStatus.fromCode(
        bindings.nar_peq_processor_register_internal());
    if (peqStatus != NativeRuntimeStatus.ok &&
        peqStatus != NativeRuntimeStatus.duplicateModule) {
      throw NativeRuntimeException(
          'NativeDspPipeline.initialize (peq)', peqStatus);
    }

    // Phase 6: Compressor (slot 2)
    final compStatus = NativeRuntimeStatus.fromCode(
        bindings.nar_comp_processor_register_internal());
    if (compStatus != NativeRuntimeStatus.ok &&
        compStatus != NativeRuntimeStatus.duplicateModule) {
      throw NativeRuntimeException(
          'NativeDspPipeline.initialize (comp)', compStatus);
    }

    // Phase 7: Crossfeed (slot 3, between compressor and limiter)
    final crossfeedStatus = NativeRuntimeStatus.fromCode(
        bindings.nar_crossfeed_processor_register_internal());
    if (crossfeedStatus != NativeRuntimeStatus.ok &&
        crossfeedStatus != NativeRuntimeStatus.duplicateModule) {
      throw NativeRuntimeException(
          'NativeDspPipeline.initialize (crossfeed)', crossfeedStatus);
    }

    // Phase 6: Limiter (slot 4)
    final limiterStatus = NativeRuntimeStatus.fromCode(
        bindings.nar_limiter_processor_register_internal());
    if (limiterStatus != NativeRuntimeStatus.ok &&
        limiterStatus != NativeRuntimeStatus.duplicateModule) {
      throw NativeRuntimeException(
          'NativeDspPipeline.initialize (limiter)', limiterStatus);
    }

    // Phase 6: Soft Clipper (slot 5)
    final softClipperStatus = NativeRuntimeStatus.fromCode(
        bindings.nar_soft_clipper_processor_register_internal());
    if (softClipperStatus != NativeRuntimeStatus.ok &&
        softClipperStatus != NativeRuntimeStatus.duplicateModule) {
      throw NativeRuntimeException(
          'NativeDspPipeline.initialize (soft_clipper)', softClipperStatus);
    }

    _initialized = true;
  }

  /// Dispose the pipeline and all processors. Safe to call even if never
  /// initialized.
  Future<void> dispose() async {
    if (!_initialized) return;
    bindings.nar_dsp_pipeline_dispose();
    _initialized = false;
  }

  // ── Pipeline controls ──────────────────────────────────────────────────────

  /// Process [buffer] through all enabled processors in registration order.
  /// Returns the native status code (0 = OK).
  int processBuffer(NativeAudioBuffer buffer) =>
      bindings.nar_dsp_pipeline_process(buffer.nativePointer);

  /// Reset all processor states (clear filter history etc.).
  void reset() => bindings.nar_dsp_pipeline_reset();

  /// Number of processors currently registered.
  int get processorCount => bindings.nar_dsp_pipeline_processor_count();

  /// Sum of algorithmic latency across all processors, in frames.
  int get totalLatencyFrames =>
      bindings.nar_dsp_pipeline_total_latency_frames();

  /// Processor id at [index] in registration order, or `null` if out of range.
  String? processorIdAt(int index) {
    final ptr = bindings.nar_dsp_pipeline_processor_id_at(index);
    if (ptr == ffi.nullptr) return null;
    return ptr.cast<pkg_ffi.Utf8>().toDartString();
  }

  /// Enable or disable the processor identified by [id] (e.g. `'dsp.gain'`).
  void setProcessorEnabled(String id, {required bool enabled}) {
    final idPtr = pkg_ffi.StringUtf8Pointer(id).toNativeUtf8();
    try {
      bindings.nar_dsp_pipeline_set_enabled(idPtr.cast(), enabled ? 1 : 0);
    } finally {
      pkg_ffi.calloc.free(idPtr);
    }
  }

  /// Returns `true` if the named processor is enabled.
  bool isProcessorEnabled(String id) {
    final idPtr = pkg_ffi.StringUtf8Pointer(id).toNativeUtf8();
    try {
      return bindings.nar_dsp_pipeline_is_enabled(idPtr.cast()) == 1;
    } finally {
      pkg_ffi.calloc.free(idPtr);
    }
  }

  // ── Gain processor controls ────────────────────────────────────────────────

  /// Set the gain in dBFS. Clamped to [-96.0, +24.0] by the native layer.
  /// Thread-safe — may be called from any thread while [processBuffer] runs.
  void setGainDb(double gainDb) =>
      bindings.nar_gain_processor_set_gain_db(gainDb);

  /// Current gain in dBFS (after clamping).
  double get gainDb => bindings.nar_gain_processor_get_gain_db();

  /// Enable (`true`) or disable (`false`) the zero-copy bypass mode.
  /// When bypassed, [processBuffer] returns immediately without touching
  /// any sample. Thread-safe.
  void setGainBypass(bool bypass) =>
      bindings.nar_gain_processor_set_bypass(bypass ? 1 : 0);

  /// `true` if the gain processor is in bypass mode.
  bool get gainBypass => bindings.nar_gain_processor_get_bypass() != 0;
}

// ── NativeParametricEq ────────────────────────────────────────────────────────

/// Dart facade over the native Parametric EQ processor (`src/peq_processor.h`).
///
/// **Architecture**: `PlaybackManager` is the only sanctioned caller — do not
/// import this class directly from UI or service code.
///
/// **Threading**: [setBand], [setBandEnabled], [setBypass] are thread-safe
/// (backed by C11 atomics + acquire/release dirty protocol). The audio thread
/// reads the parameters lock-free during ExoPlayer's render cycle.
///
/// **Sample rate**: always pass the current playback sample rate from
/// [PlaybackManager.audioFormatStream] (or a recent snapshot). If the sample
/// rate changes (e.g. 44.1 kHz → 48 kHz between tracks), re-apply all active
/// bands via [setBand] so coefficients stay correct. Using a stale sample rate
/// causes a mild frequency offset in the filter response, not a crash.
///
/// **Lifecycle**: managed by [NativeDspPipeline.initialize] / [dispose].
/// The PEQ processor is registered immediately after the gain processor; no
/// separate initialization step is needed.
class NativeParametricEq {
  NativeParametricEq._();

  static final NativeParametricEq instance = NativeParametricEq._();

  // ── Band configuration ─────────────────────────────────────────────────────

  /// Configure a single EQ band. Computes biquad coefficients on the calling
  /// thread and queues them for atomic adoption by the audio thread on its
  /// next render cycle — no playback interruption.
  ///
  /// [bandIndex] : 0 … [maxBands]-1.
  /// [enabled]   : Whether this band processes audio.
  /// [type]      : Filter topology ([PeqFilterType]).
  /// [freqHz]    : Centre/corner frequency in Hz.
  /// [q]         : Quality factor (> 0; typical values 0.5–10).
  /// [gainDb]    : Gain in dBFS for Peak/Shelf types. Ignored by LP/HP/BP/Notch.
  /// [sampleRate]: Current playback sample rate (from [audioFormatStream]).
  ///
  /// Returns the native status code (0 = OK).
  int setBand({
    required int bandIndex,
    required bool enabled,
    required PeqFilterType type,
    required double freqHz,
    required double q,
    required double gainDb,
    required double sampleRate,
  }) =>
      bindings.nar_peq_set_band(
        bandIndex,
        enabled ? 1 : 0,
        type.index,
        freqHz,
        q,
        gainDb,
        sampleRate,
      );

  /// Enable or disable a single band without recomputing coefficients.
  /// Useful for quick A/B comparison of individual bands.
  int setBandEnabled(int bandIndex, {required bool enabled}) =>
      bindings.nar_peq_set_band_enabled(bandIndex, enabled ? 1 : 0);

  /// Whether the band at [bandIndex] is currently enabled.
  bool isBandEnabled(int bandIndex) =>
      bindings.nar_peq_get_band_enabled(bandIndex) == 1;

  // ── Global bypass ─────────────────────────────────────────────────────────

  /// Enable or disable the global PEQ bypass.
  /// When bypassed, all bands are skipped with zero computational cost
  /// (true zero-copy pass-through). Thread-safe.
  void setBypass(bool bypass) =>
      bindings.nar_peq_set_bypass(bypass ? 1 : 0);

  /// `true` if the global PEQ bypass is active.
  bool get bypass => bindings.nar_peq_get_bypass() != 0;

  // ── Metadata ──────────────────────────────────────────────────────────────

  /// Maximum number of configurable bands (compile-time constant = 32).
  int get maxBands => bindings.nar_peq_max_bands();

  /// Number of bands currently configured (0 until the first [setBand] call).
  int get bandCount => bindings.nar_peq_band_count();
}

// ── NativeCompressor ──────────────────────────────────────────────────────────

/// Dart facade over the native Compressor processor (`src/comp_processor.h`).
///
/// Feed-forward soft-knee dynamic range compressor sitting at pipeline slot 2
/// (after dsp.peq, before dsp.limiter).
///
/// **Architecture**: [PlaybackManager] is the only sanctioned caller.
/// **Threading**: all setters are thread-safe (acquire/release dirty protocol).
class NativeCompressor {
  NativeCompressor._();
  static final NativeCompressor instance = NativeCompressor._();

  /// Configure all compressor parameters in one call.
  ///
  /// [thresholdDb]  : Level above which compression starts. Default: −20 dBFS.
  /// [ratio]        : Compression ratio N:1. Default: 4.0. 1.0 = no compression.
  /// [attackMs]     : Envelope rise time in ms. Default: 10.0.
  /// [releaseMs]    : Envelope fall time in ms. Default: 100.0.
  /// [kneeDb]       : Soft-knee half-width in dB. Default: 6.0. 0 = hard knee.
  /// [makeupGainDb] : Post-compression gain. Default: 0.0 dBFS.
  /// [sampleRate]   : Current playback sample rate. 0 → 48000 Hz fallback.
  int setParams({
    required double thresholdDb,
    required double ratio,
    required double attackMs,
    required double releaseMs,
    required double kneeDb,
    required double makeupGainDb,
    double sampleRate = 48000.0,
  }) =>
      bindings.nar_comp_set_params(
          thresholdDb, ratio, attackMs, releaseMs, kneeDb, makeupGainDb, sampleRate);

  /// Enable (`false`) or bypass (`true`) the compressor.
  void setBypass(bool bypass) => bindings.nar_comp_set_bypass(bypass ? 1 : 0);

  /// `true` if the compressor bypass is active.
  bool get bypass => bindings.nar_comp_get_bypass() != 0;
}

// ── NativeLimiter ─────────────────────────────────────────────────────────────

/// Dart facade over the native Limiter processor (`src/limiter_processor.h`).
///
/// Brickwall look-ahead limiter at pipeline slot 3.
/// Prevents any output sample from exceeding [thresholdDb].
///
/// **Architecture**: [PlaybackManager] is the only sanctioned caller.
class NativeLimiter {
  NativeLimiter._();
  static final NativeLimiter instance = NativeLimiter._();

  /// Configure limiter parameters.
  ///
  /// [thresholdDb] : Ceiling in dBFS. Default: −1.0. Must be < 0.
  /// [releaseMs]   : Gain recovery time in ms. Default: 50.0.
  /// [sampleRate]  : Current playback sample rate. 0 → 48000 Hz fallback.
  int setParams({
    required double thresholdDb,
    required double releaseMs,
    double sampleRate = 48000.0,
  }) =>
      bindings.nar_limiter_set_params(thresholdDb, releaseMs, sampleRate);

  /// Enable (`false`) or bypass (`true`) the limiter.
  void setBypass(bool bypass) => bindings.nar_limiter_set_bypass(bypass ? 1 : 0);

  /// `true` if the limiter bypass is active.
  bool get bypass => bindings.nar_limiter_get_bypass() != 0;

  /// Look-ahead delay in frames (63 at compile time = ~1.3 ms at 48 kHz).
  int get lookaheadFrames => bindings.nar_limiter_lookahead_frames();
}

// ── NativeCrossfeed ───────────────────────────────────────────────────────────

/// Dart facade over the native Crossfeed processor
/// (`src/crossfeed_processor.h`).
///
/// Frequency-dependent headphone crossfeed at pipeline slot 3
/// (after dsp.compressor, before dsp.limiter).
///
/// **Architecture**: [PlaybackManager] is the only sanctioned caller.
/// **Threading**: [setParams] and [setBypass] are thread-safe
/// (acquire/release dirty protocol for params; atomic store for bypass).
class NativeCrossfeed {
  NativeCrossfeed._();
  static final NativeCrossfeed instance = NativeCrossfeed._();

  /// Configure all crossfeed parameters in one call.
  ///
  /// [amount]    : Crossfeed blend strength [0, 1]. Default: 0.3.
  ///               0 = no crossfeed (transparent); 1 = maximum blend.
  /// [cutoffHz]  : Lowpass cutoff for the cross-channel path [100, 2000] Hz.
  ///               Default: 700 Hz — typical crossover between directional and
  ///               non-directional frequency content.
  /// [hfCompDb]  : High-shelf gain for HF compensation [0, 12] dB. Default: 3.0.
  ///               Compensates for the slight HF loss introduced by crossfeed.
  /// [hfCompHz]  : High-shelf corner frequency [1000, 16000] Hz. Default: 4000.
  /// [width]     : Stereo width multiplier after mixing [0, 2]. Default: 1.0.
  ///               1.0 = natural post-crossfeed image; < 1 = narrower.
  /// [sampleRate]: Current playback sample rate. 0 → 48000 Hz fallback.
  ///
  /// Returns the native status code (0 = OK).
  int setParams({
    double amount = 0.3,
    double cutoffHz = 700.0,
    double hfCompDb = 3.0,
    double hfCompHz = 4000.0,
    double width = 1.0,
    double sampleRate = 48000.0,
  }) =>
      bindings.nar_crossfeed_set_params(
          amount, cutoffHz, hfCompDb, hfCompHz, width, sampleRate);

  /// Enable (`false`) or bypass (`true`) the crossfeed processor.
  void setBypass(bool bypass) =>
      bindings.nar_crossfeed_set_bypass(bypass ? 1 : 0);

  /// `true` if the crossfeed bypass is active.
  bool get bypass => bindings.nar_crossfeed_get_bypass() != 0;
}

// ── NativeReplayGain ──────────────────────────────────────────────────────────

/// Dart facade over the native ReplayGain processor
/// (`src/replaygain_processor.h`).
///
/// Metadata-driven transparent gain stage at pipeline slot 1 (between
/// dsp.gain and dsp.peq). Starts bypassed — [PlaybackManager] engages it
/// after resolving REPLAYGAIN_TRACK_GAIN / REPLAYGAIN_ALBUM_GAIN (or R128 /
/// iTunNORM equivalents) via [ReplayGainService.resolveBoth].
///
/// **Architecture**: [PlaybackManager] is the only sanctioned caller — do not
/// import this class directly from UI or service code.
///
/// **Threading**: [setGain] and [setBypass] are thread-safe (lock-free atomics;
/// no blocking on the audio thread). The effective linear gain is pre-computed
/// on the calling thread (powf + clipping protection); the audio thread only
/// does an atomic load + scalar multiply loop.
class NativeReplayGain {
  NativeReplayGain._();
  static final NativeReplayGain instance = NativeReplayGain._();

  /// Set the gain applied by the ReplayGain processor.
  ///
  /// The effective linear gain is computed here on the control thread
  /// (dB → linear conversion + optional clipping protection) and stored
  /// atomically — the audio thread picks up the new value on its next
  /// render cycle without blocking.
  ///
  /// [gainDb]                : gain in dBFS from metadata (e.g. −6.0 = 6 dB
  ///                           attenuation). Clamped to [−24, +24] dB.
  /// [peakLinear]            : track/album peak in linear scale. Pass 0.0
  ///                           if peak data is unavailable.
  /// [useClippingProtection] : if `true`, caps effective gain so that
  ///                           `gain_linear × peak_linear ≤ 1.0`.
  ///
  /// Returns the native status code (0 = OK).
  int setGain({
    required double gainDb,
    double peakLinear = 0.0,
    bool useClippingProtection = true,
  }) =>
      bindings.nar_replaygain_set_gain(
          gainDb, peakLinear, useClippingProtection ? 1 : 0);

  /// Enable (`false`) or bypass (`true`) the ReplayGain processor.
  void setBypass(bool bypass) =>
      bindings.nar_replaygain_set_bypass(bypass ? 1 : 0);

  /// `true` if the ReplayGain processor is currently bypassed.
  bool get bypass => bindings.nar_replaygain_get_bypass() != 0;
}

// ── NativeSoftClipper ─────────────────────────────────────────────────────────

/// Dart facade over the native Soft Clipper processor
/// (`src/soft_clipper_processor.h`).
///
/// Tanh waveshaper at pipeline slot 5 (last in the dynamics chain).
/// Samples below [thresholdDb] pass through unchanged; samples above are
/// smoothly limited asymptotically toward 0 dBFS.
///
/// **Architecture**: [PlaybackManager] is the only sanctioned caller.
class NativeSoftClipper {
  NativeSoftClipper._();
  static final NativeSoftClipper instance = NativeSoftClipper._();

  /// Set the soft-clip threshold in dBFS. Default: −0.5 dBFS.
  void setThresholdDb(double thresholdDb) =>
      bindings.nar_soft_clipper_set_threshold_db(thresholdDb);

  /// Current soft-clip threshold in dBFS.
  double get thresholdDb => bindings.nar_soft_clipper_get_threshold_db();

  /// Enable (`false`) or bypass (`true`) the soft clipper.
  void setBypass(bool bypass) =>
      bindings.nar_soft_clipper_set_bypass(bypass ? 1 : 0);

  /// `true` if the soft clipper bypass is active.
  bool get bypass => bindings.nar_soft_clipper_get_bypass() != 0;
}
