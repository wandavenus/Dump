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

    // Phase 5: register the Parametric EQ processor (slot 1, after gain).
    final peqStatus = NativeRuntimeStatus.fromCode(
        bindings.nar_peq_processor_register_internal());
    if (peqStatus != NativeRuntimeStatus.ok &&
        peqStatus != NativeRuntimeStatus.duplicateModule) {
      throw NativeRuntimeException(
          'NativeDspPipeline.initialize (peq)', peqStatus);
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
