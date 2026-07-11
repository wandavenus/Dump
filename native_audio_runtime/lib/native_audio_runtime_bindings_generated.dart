// AUTO GENERATED FILE, DO NOT EDIT BY HAND.
//
// Mirrors `package:ffigen` output for the native runtime headers.
// Regenerate with `dart run ffigen --config ffigen.yaml` once libclang is
// available in the build environment; until then this file is maintained
// by hand and MUST stay in sync with the C headers, function-for-function.
//
// Phase 4 additions: NarAudioBuffer (opaque), audio_buffer.h bindings,
// dsp_pipeline.h bindings, gain_processor.h bindings.
// ignore_for_file: type=lint, unused_import
import 'dart:ffi' as ffi;

// ── Opaque native types ───────────────────────────────────────────────────────

/// Opaque handle to a `NarAudioBuffer` struct (see `src/audio_buffer.h`).
/// Never instantiated from Dart — only used as `Pointer<NarAudioBuffer>`.
final class NarAudioBuffer extends ffi.Opaque {}

// ── native_audio_runtime.h ────────────────────────────────────────────────────

/// Initialize the native runtime. Idempotent and thread-safe.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_init();

/// Tear down the native runtime and clear the module registry.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_dispose();

/// Returns 1 if the runtime is currently initialized, 0 otherwise.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_is_initialized();

/// Static runtime version string. Owned by native code — do not free.
@ffi.Native<ffi.Pointer<ffi.Char> Function()>()
external ffi.Pointer<ffi.Char> native_runtime_get_version();

/// Number of capability entries known to the runtime.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_capability_count();

/// Capability key at `index`, or nullptr if out of range.
@ffi.Native<ffi.Pointer<ffi.Char> Function(ffi.Int32)>()
external ffi.Pointer<ffi.Char> native_runtime_capability_key(int index);

/// Whether the capability at `index` is supported.
@ffi.Native<ffi.Int32 Function(ffi.Int32)>()
external int native_runtime_capability_supported(int index);

/// Register a module id with the runtime.
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>()
external int native_runtime_register_module(ffi.Pointer<ffi.Char> moduleId);

/// Number of modules currently registered.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_module_count();

/// Module id at `index` in registration order, or nullptr if out of range.
@ffi.Native<ffi.Pointer<ffi.Char> Function(ffi.Int32)>()
external ffi.Pointer<ffi.Char> native_runtime_module_id_at(int index);

/// Status code of the most recent runtime call.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_last_status();

// ── audio_buffer.h ────────────────────────────────────────────────────────────

/// Allocate an interleaved PCM buffer. Returns nullptr on failure.
/// `format`: 0 = FLOAT32 (only supported format in Phase 4).
@ffi.Native<
    ffi.Pointer<NarAudioBuffer> Function(
        ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)>()
external ffi.Pointer<NarAudioBuffer> nar_audio_buffer_create(
    int capacityFrames, int channelCount, int sampleRate, int format);

/// Free a buffer. Safe to call with nullptr (no-op).
@ffi.Native<ffi.Void Function(ffi.Pointer<NarAudioBuffer>)>()
external void nar_audio_buffer_destroy(ffi.Pointer<NarAudioBuffer> buffer);

/// Direct pointer to interleaved float32 sample data. Returns nullptr for
/// a null buffer or non-FLOAT32 format.
@ffi.Native<
    ffi.Pointer<ffi.Float> Function(ffi.Pointer<NarAudioBuffer>)>()
external ffi.Pointer<ffi.Float> nar_audio_buffer_data(
    ffi.Pointer<NarAudioBuffer> buffer);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<NarAudioBuffer>)>()
external int nar_audio_buffer_capacity_frames(
    ffi.Pointer<NarAudioBuffer> buffer);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<NarAudioBuffer>)>()
external int nar_audio_buffer_frame_count(ffi.Pointer<NarAudioBuffer> buffer);

/// Narrow (or restore) the number of valid frames. Returns status code.
@ffi.Native<ffi.Int32 Function(ffi.Pointer<NarAudioBuffer>, ffi.Int32)>()
external int nar_audio_buffer_set_frame_count(
    ffi.Pointer<NarAudioBuffer> buffer, int frameCount);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<NarAudioBuffer>)>()
external int nar_audio_buffer_channel_count(ffi.Pointer<NarAudioBuffer> buffer);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<NarAudioBuffer>)>()
external int nar_audio_buffer_sample_rate(ffi.Pointer<NarAudioBuffer> buffer);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<NarAudioBuffer>)>()
external int nar_audio_buffer_format(ffi.Pointer<NarAudioBuffer> buffer);

@ffi.Native<ffi.Int64 Function(ffi.Pointer<NarAudioBuffer>)>()
external int nar_audio_buffer_timestamp_us(ffi.Pointer<NarAudioBuffer> buffer);

@ffi.Native<ffi.Void Function(ffi.Pointer<NarAudioBuffer>, ffi.Int64)>()
external void nar_audio_buffer_set_timestamp_us(
    ffi.Pointer<NarAudioBuffer> buffer, int timestampUs);

// ── dsp_pipeline.h ────────────────────────────────────────────────────────────

/// Initialise the DSP pipeline. Idempotent.
@ffi.Native<ffi.Int32 Function()>()
external int nar_dsp_pipeline_init();

/// Returns 1 if the pipeline is initialised, 0 otherwise. Atomic load — safe from any thread.
@ffi.Native<ffi.Int32 Function()>()
external int nar_dsp_pipeline_is_initialized();

/// Process `buffer` through all enabled processors in order.
@ffi.Native<ffi.Int32 Function(ffi.Pointer<NarAudioBuffer>)>()
external int nar_dsp_pipeline_process(ffi.Pointer<NarAudioBuffer> buffer);

/// Reset all processor states.
@ffi.Native<ffi.Void Function()>()
external void nar_dsp_pipeline_reset();

/// Dispose the pipeline and all processors.
@ffi.Native<ffi.Void Function()>()
external void nar_dsp_pipeline_dispose();

/// Enable (1) or disable (0) a processor by id (UTF-8 C string).
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Int32)>()
external int nar_dsp_pipeline_set_enabled(
    ffi.Pointer<ffi.Char> id, int enabled);

/// Returns 1 if enabled, 0 if disabled, error code if not found.
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>()
external int nar_dsp_pipeline_is_enabled(ffi.Pointer<ffi.Char> id);

/// Total algorithmic latency across all registered processors, in frames.
@ffi.Native<ffi.Int32 Function()>()
external int nar_dsp_pipeline_total_latency_frames();

/// Number of registered processors.
@ffi.Native<ffi.Int32 Function()>()
external int nar_dsp_pipeline_processor_count();

/// Processor id at `index`, or nullptr if out of range.
@ffi.Native<ffi.Pointer<ffi.Char> Function(ffi.Int32)>()
external ffi.Pointer<ffi.Char> nar_dsp_pipeline_processor_id_at(int index);

// ── gain_processor.h ──────────────────────────────────────────────────────────

/// Register the gain processor with the DSP pipeline. Returns status code.
@ffi.Native<ffi.Int32 Function()>()
external int nar_gain_processor_register_internal();

/// Set gain in dBFS. Clamped to [-96, +24] internally. Thread-safe.
/// Note: C takes `float`; Dart passes `double` which is truncated by FFI.
@ffi.Native<ffi.Void Function(ffi.Float)>()
external void nar_gain_processor_set_gain_db(double gainDb);

/// Returns current gain in dBFS.
@ffi.Native<ffi.Float Function()>()
external double nar_gain_processor_get_gain_db();

/// Set bypass (1) or normal processing (0). Thread-safe.
@ffi.Native<ffi.Void Function(ffi.Int32)>()
external void nar_gain_processor_set_bypass(int bypass);

/// Returns 1 if bypass active, 0 otherwise.
@ffi.Native<ffi.Int32 Function()>()
external int nar_gain_processor_get_bypass();

// ── peq_processor.h ───────────────────────────────────────────────────────────
// Phase 5: Parametric Equalizer Processor.

/// Register the PEQ processor with the DSP pipeline. Returns status code.
@ffi.Native<ffi.Int32 Function()>()
external int nar_peq_processor_register_internal();

/// Configure a single EQ band (all parameters in one call).
/// [filterType]: 0=Peak, 1=LowShelf, 2=HighShelf, 3=LowPass, 4=HighPass,
///               5=BandPass, 6=Notch.
/// [freqHz], [q], [gainDb], [sampleRate]: float; Dart double truncated by FFI.
@ffi.Native<
    ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32,
        ffi.Float, ffi.Float, ffi.Float, ffi.Float)>()
external int nar_peq_set_band(
    int bandIndex,
    int enabled,
    int filterType,
    double freqHz,
    double q,
    double gainDb,
    double sampleRate);

/// Enable (1) or disable (0) a single band without recomputing coefficients.
@ffi.Native<ffi.Int32 Function(ffi.Int32, ffi.Int32)>()
external int nar_peq_set_band_enabled(int bandIndex, int enabled);

/// Returns 1 if the band is enabled, 0 if disabled, error code if out of range.
@ffi.Native<ffi.Int32 Function(ffi.Int32)>()
external int nar_peq_get_band_enabled(int bandIndex);

/// Enable (bypass=1) or disable (bypass=0) the global PEQ bypass. Thread-safe.
@ffi.Native<ffi.Void Function(ffi.Int32)>()
external void nar_peq_set_bypass(int bypass);

/// Returns 1 if global bypass is active, 0 otherwise.
@ffi.Native<ffi.Int32 Function()>()
external int nar_peq_get_bypass();

/// Maximum configurable bands (compile-time constant = 32).
@ffi.Native<ffi.Int32 Function()>()
external int nar_peq_max_bands();

/// Number of bands currently configured (0 until first nar_peq_set_band call).
@ffi.Native<ffi.Int32 Function()>()
external int nar_peq_band_count();

// ── comp_processor.h ──────────────────────────────────────────────────────────
// Phase 6: Feed-forward soft-knee compressor.

/// Register the compressor processor with the DSP pipeline. Returns status code.
@ffi.Native<ffi.Int32 Function()>()
external int nar_comp_processor_register_internal();

/// Configure all compressor parameters in one call.
/// Floats are truncated from Dart double → C float by the FFI layer.
@ffi.Native<
    ffi.Int32 Function(ffi.Float, ffi.Float, ffi.Float,
        ffi.Float, ffi.Float, ffi.Float, ffi.Float)>()
external int nar_comp_set_params(
    double thresholdDb,
    double ratio,
    double attackMs,
    double releaseMs,
    double kneeDb,
    double makeupGainDb,
    double sampleRate);

/// Enable (0) or bypass (1) the compressor.
@ffi.Native<ffi.Void Function(ffi.Int32)>()
external void nar_comp_set_bypass(int bypass);

/// Returns 1 if the compressor is bypassed, 0 otherwise.
@ffi.Native<ffi.Int32 Function()>()
external int nar_comp_get_bypass();

// ── limiter_processor.h ───────────────────────────────────────────────────────
// Phase 6: Look-ahead brickwall limiter.

/// Register the limiter processor with the DSP pipeline. Returns status code.
@ffi.Native<ffi.Int32 Function()>()
external int nar_limiter_processor_register_internal();

/// Configure limiter parameters (threshold, release, sample rate).
@ffi.Native<ffi.Int32 Function(ffi.Float, ffi.Float, ffi.Float)>()
external int nar_limiter_set_params(
    double thresholdDb, double releaseMs, double sampleRate);

/// Enable (0) or bypass (1) the limiter.
@ffi.Native<ffi.Void Function(ffi.Int32)>()
external void nar_limiter_set_bypass(int bypass);

/// Returns 1 if the limiter is bypassed, 0 otherwise.
@ffi.Native<ffi.Int32 Function()>()
external int nar_limiter_get_bypass();

/// Look-ahead delay in frames (NAR_LIMITER_LOOKAHEAD_FRAMES − 1 = 63).
@ffi.Native<ffi.Int32 Function()>()
external int nar_limiter_lookahead_frames();

// ── soft_clipper_processor.h ──────────────────────────────────────────────────
// Phase 6: Hyperbolic-tangent soft clipper.

/// Register the soft clipper processor with the DSP pipeline. Returns status code.
@ffi.Native<ffi.Int32 Function()>()
external int nar_soft_clipper_processor_register_internal();

/// Set the soft-clip threshold in dBFS. Default: −0.5 dBFS.
@ffi.Native<ffi.Void Function(ffi.Float)>()
external void nar_soft_clipper_set_threshold_db(double thresholdDb);

/// Returns the current soft-clip threshold in dBFS.
@ffi.Native<ffi.Float Function()>()
external double nar_soft_clipper_get_threshold_db();

/// Enable (0) or bypass (1) the soft clipper.
@ffi.Native<ffi.Void Function(ffi.Int32)>()
external void nar_soft_clipper_set_bypass(int bypass);

/// Returns 1 if the soft clipper is bypassed, 0 otherwise.
@ffi.Native<ffi.Int32 Function()>()
external int nar_soft_clipper_get_bypass();
