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
    ffi.Int32,
    ffi.Int32,
    ffi.Int32,
    ffi.Int32,
  )
>()
external ffi.Pointer<NarAudioBuffer> nar_audio_buffer_create(
  int capacityFrames,
  int channelCount,
  int sampleRate,
  int format,
);

/// Free a buffer. Safe to call with nullptr (no-op).
@ffi.Native<ffi.Void Function(ffi.Pointer<NarAudioBuffer>)>()
external void nar_audio_buffer_destroy(ffi.Pointer<NarAudioBuffer> buffer);

/// Direct pointer to interleaved float32 sample data. Returns nullptr for
/// a null buffer or non-FLOAT32 format.
@ffi.Native<ffi.Pointer<ffi.Float> Function(ffi.Pointer<NarAudioBuffer>)>()
external ffi.Pointer<ffi.Float> nar_audio_buffer_data(
  ffi.Pointer<NarAudioBuffer> buffer,
);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<NarAudioBuffer>)>()
external int nar_audio_buffer_capacity_frames(
  ffi.Pointer<NarAudioBuffer> buffer,
);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<NarAudioBuffer>)>()
external int nar_audio_buffer_frame_count(ffi.Pointer<NarAudioBuffer> buffer);

/// Narrow (or restore) the number of valid frames. Returns status code.
@ffi.Native<ffi.Int32 Function(ffi.Pointer<NarAudioBuffer>, ffi.Int32)>()
external int nar_audio_buffer_set_frame_count(
  ffi.Pointer<NarAudioBuffer> buffer,
  int frameCount,
);

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
  ffi.Pointer<NarAudioBuffer> buffer,
  int timestampUs,
);

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
  ffi.Pointer<ffi.Char> id,
  int enabled,
);

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

// ── comp_processor.h ──────────────────────────────────────────────────────────
// Phase 6: Feed-forward soft-knee compressor.

/// Register the compressor processor with the DSP pipeline. Returns status code.
@ffi.Native<ffi.Int32 Function()>()
external int nar_comp_processor_register_internal();

/// Configure all compressor parameters in one call.
/// Floats are truncated from Dart double → C float by the FFI layer.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
  )
>()
external int nar_comp_set_params(
  double thresholdDb,
  double ratio,
  double attackMs,
  double releaseMs,
  double kneeDb,
  double makeupGainDb,
  double sampleRate,
);

/// Enable (0) or bypass (1) the compressor.
@ffi.Native<ffi.Void Function(ffi.Int32)>()
external void nar_comp_set_bypass(int bypass);

/// Returns 1 if the compressor is bypassed, 0 otherwise.
@ffi.Native<ffi.Int32 Function()>()
external int nar_comp_get_bypass();

// ── replaygain_processor.h ────────────────────────────────────────────────────
// Phase 8: Metadata-driven ReplayGain transparent gain stage (pipeline slot 1).

/// Register the ReplayGain processor with the DSP pipeline. Returns status code.
@ffi.Native<ffi.Int32 Function()>()
external int nar_replaygain_processor_register_internal();

/// Set the ReplayGain gain.
/// [gainDb]: gain in dBFS from metadata (clamped to [-24, +24]).
/// [peakLinear]: track/album peak in linear scale; 0.0 if unknown.
/// [useClippingProtection]: 1 = cap gain so peak never exceeds 0 dBFS.
/// Effective gain is pre-computed and stored atomically. Returns 0 (OK).
@ffi.Native<ffi.Int32 Function(ffi.Float, ffi.Float, ffi.Int32)>()
external int nar_replaygain_set_gain(
  double gainDb,
  double peakLinear,
  int useClippingProtection,
);

/// Enable (0) or bypass (1) the ReplayGain processor.
@ffi.Native<ffi.Void Function(ffi.Int32)>()
external void nar_replaygain_set_bypass(int bypass);

/// Returns 1 if the ReplayGain processor is bypassed, 0 otherwise.
@ffi.Native<ffi.Int32 Function()>()
external int nar_replaygain_get_bypass();

// ── loudness_processor.h ──────────────────────────────────────────────────────
// Phase 8.5: EBU R128 real-time loudness normalization (pipeline slot 2).

/// Register the Loudness Normalization processor. Returns status code.
@ffi.Native<ffi.Int32 Function()>()
external int nar_loudness_processor_register_internal();

/// Set the target output loudness in LUFS. Clamped to [−36, −6]. Default: −23.
@ffi.Native<ffi.Void Function(ffi.Float)>()
external void nar_loudness_set_target_lufs(double targetLufs);

/// Enable (0) or bypass (1) the Loudness Normalization processor.
@ffi.Native<ffi.Void Function(ffi.Int32)>()
external void nar_loudness_set_bypass(int bypass);

/// Returns 1 if the processor is currently bypassed, 0 if active.
@ffi.Native<ffi.Int32 Function()>()
external int nar_loudness_get_bypass();

/// Update the playback sample rate and recompute K-weighting coefficients.
/// Call on track transitions when the sample rate changes.
@ffi.Native<ffi.Void Function(ffi.Int32)>()
external void nar_loudness_set_sample_rate(int sampleRate);

/// Current short-term LUFS measurement. −99.0 before first update or when bypassed.
@ffi.Native<ffi.Float Function()>()
external double nar_loudness_get_measured_lufs();

/// Current smooth gain applied to the stream in dBFS. 0.0 when bypassed.
@ffi.Native<ffi.Float Function()>()
external double nar_loudness_get_applied_gain_db();

/// Reset analyzer state (filter history, power accumulator, smooth gain).
/// Call on every track change so the new track is measured fresh.
@ffi.Native<ffi.Void Function()>()
external void nar_loudness_reset();

// ── crossfeed_processor.h ─────────────────────────────────────────────────────
// Phase 7: Frequency-dependent headphone crossfeed.

/// Register the crossfeed processor with the DSP pipeline. Returns status code.
@ffi.Native<ffi.Int32 Function()>()
external int nar_crossfeed_processor_register_internal();

/// Configure all crossfeed parameters in one call.
/// [amount]: blend [0,1]. [cutoffHz]: LP cutoff [100,2000] Hz.
/// [hfCompDb]: HF shelf gain [0,12] dB. [hfCompHz]: shelf corner [1000,16000] Hz.
/// [width]: stereo width [0,2]. [sampleRate]: playback rate (0 → 48000).
@ffi.Native<
  ffi.Int32 Function(
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
  )
>()
external int nar_crossfeed_set_params(
  double amount,
  double cutoffHz,
  double hfCompDb,
  double hfCompHz,
  double width,
  double sampleRate,
);

/// Enable (0) or bypass (1) the crossfeed processor.
@ffi.Native<ffi.Void Function(ffi.Int32)>()
external void nar_crossfeed_set_bypass(int bypass);

/// Returns 1 if the crossfeed is bypassed, 0 otherwise.
@ffi.Native<ffi.Int32 Function()>()
external int nar_crossfeed_get_bypass();

// ── limiter_processor.h ───────────────────────────────────────────────────────
// Phase 6: Look-ahead brickwall limiter.

/// Register the limiter processor with the DSP pipeline. Returns status code.
@ffi.Native<ffi.Int32 Function()>()
external int nar_limiter_processor_register_internal();

/// Configure limiter parameters (threshold, release, sample rate).
@ffi.Native<ffi.Int32 Function(ffi.Float, ffi.Float, ffi.Float)>()
external int nar_limiter_set_params(
  double thresholdDb,
  double releaseMs,
  double sampleRate,
);

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

// ── aaudio_probe.h ─────────────────────────────────────────────────────────────
// Diagnostic-only: probes what AAudio actually grants when this app asks
// for SHARING_MODE_EXCLUSIVE + PERFORMANCE_MODE_LOW_LATENCY. Not part of the
// DSP pipeline — no register_internal(), no pipeline slot.

/// Opens a real AAudio stream requesting exclusive/low-latency, reads back
/// what was actually granted, then closes it. Returns a NarAAudioProbeResult
/// (0 = ok; negative = specific failure — see src/aaudio_probe.h).
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_aaudio_probe();

/// Sharing mode granted by the last probe (0 = EXCLUSIVE, 1 = SHARED),
/// or -1 if the last probe did not reach a successful open.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_aaudio_last_sharing_mode();

/// Performance mode granted by the last probe (10 = NONE, 11 = POWER_SAVING,
/// 12 = LOW_LATENCY), or -1 if unavailable.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_aaudio_last_performance_mode();

/// Human-readable detail for the last probe (empty string on success).
/// Owned by native code — do not free.
@ffi.Native<ffi.Pointer<ffi.Char> Function()>()
external ffi.Pointer<ffi.Char> native_runtime_aaudio_last_error();
