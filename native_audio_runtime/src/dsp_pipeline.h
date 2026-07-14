// DSP Pipeline — Phase 4.
//
// Ordered chain of NarDspProcessor instances. Processors run in registration
// order; disabled processors are skipped entirely (process() is never called
// on them — that is the pipeline's enabled flag, distinct from a processor's
// own optional "bypass" concept, e.g. gain_processor.h's bypass flag).
//
// Threading model:
//   nar_dsp_pipeline_process() / reset() — call only from the single audio
//   processing thread (mirrors Media3/ExoPlayer's audio-thread contract).
//   nar_dsp_pipeline_set_enabled() — safe from any thread concurrently with
//   process() because the enabled flag is an atomic store/load per slot.
//   nar_dsp_pipeline_register_internal() / dispose() — must NOT be called
//   concurrently with process() or reset().
//
// Extension: adding a new processor in a future phase only requires:
//   1. Implementing NarDspProcessorVTable in a new .c file.
//   2. Calling nar_dsp_pipeline_register_internal() from that module's init.
//   No changes to dsp_pipeline.c or dsp_pipeline.h.

#ifndef NATIVE_AUDIO_RUNTIME_DSP_PIPELINE_H_
#define NATIVE_AUDIO_RUNTIME_DSP_PIPELINE_H_

#include <stdint.h>

#include "audio_buffer.h"
#include "dsp_processor.h"
#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Initialise the DSP pipeline. Must be called while the native runtime is
// NAR_STATE_INITIALIZED (i.e. after native_runtime_init()). Idempotent —
// a second call while already initialised returns NATIVE_RUNTIME_OK.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_init(void);

// Returns 1 if the pipeline has been initialised, 0 otherwise.
// Safe to call at any time from any thread (atomic load).
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_is_initialized(void);

// Process `buffer` through every ENABLED processor in registration order,
// for stream slot 0 (the primary/legacy single-stream caller — Dart's own
// pipeline calls always target slot 0). Equivalent to
// nar_dsp_pipeline_process_stream(buffer, 0) — kept as a distinct exported
// symbol so existing callers' behavior and binary signature never change.
//
// Production-hardening pass: a non-OK return from one processor no longer
// stops the chain — every subsequent processor still runs (see
// nar_dsp_pipeline_process_stream() for the full rationale). The return
// value is still the FIRST non-OK code observed, for diagnostics.
// buffer must not be NULL.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_process(NarAudioBuffer* buffer);

// Process `buffer` through every ENABLED processor in registration order,
// for the given `stream_slot` (see dsp_stream.h) — the stream identifier is
// threaded down into every stateful processor's per-stream runtime state so
// that two concurrently-playing streams (e.g. Media3PlaybackService.kt's
// primary + crossfade-standby ExoPlayer instances) never share the same
// envelope followers / delay lines / filter histories.
//
// Robustness (production-hardening pass): unlike the pre-hardening
// contract, a non-OK return from one processor does NOT stop the chain —
// the pipeline always continues through every remaining slot, guaranteeing
// the limiter and soft-clipper (registered last) always run as the final
// safety net even if an earlier processor fails. The function still
// returns the FIRST non-OK code it observed (0/NATIVE_RUNTIME_OK if none),
// for diagnostics — callers must not treat a non-OK return as "the buffer
// was left unprocessed", since later stages may still have run.
// buffer must not be NULL.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_process_stream(
    NarAudioBuffer* buffer, int32_t stream_slot);

// Process a raw interleaved float32 PCM buffer in-place, for stream slot 0.
// No heap allocation. `data` points to frame_count × channel_count floats.
// Kept as a distinct exported symbol with its original signature for
// existing single-stream JNI/FFI callers. Equivalent to
// nar_dsp_pipeline_process_raw_stream(data, frame_count, channel_count,
// sample_rate, 0). Returns NATIVE_RUNTIME_ERROR_NOT_INITIALIZED if the
// pipeline has not been initialised yet (audio passes unchanged —
// fail-open).
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_process_raw(
    float* data, int32_t frame_count, int32_t channel_count, int32_t sample_rate);

// Process a raw interleaved float32 PCM buffer in-place for the given
// `stream_slot` (see dsp_stream.h). No heap allocation. This is the JNI
// entry point called by NativeDspAudioProcessor.kt on EACH ExoPlayer
// instance's own audio rendering thread — primary player passes
// stream_slot=0, the secondary/crossfade-standby player passes
// stream_slot=1. Must not lock or allocate. Returns
// NATIVE_RUNTIME_ERROR_NOT_INITIALIZED if the pipeline has not been
// initialised yet (audio passes unchanged — fail-open).
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_process_raw_stream(
    float* data, int32_t frame_count, int32_t channel_count,
    int32_t sample_rate, int32_t stream_slot);

// Reset all registered processors (clear filter history, envelope followers,
// etc.) without re-initialising. Calls reset() on each processor, enabled
// or not. Not thread-safe — same audio-thread requirement as process().
FFI_PLUGIN_EXPORT void nar_dsp_pipeline_reset(void);

// Dispose all processors (calling vtable->dispose() on each in registration
// order) and tear down the pipeline. After this call, nar_dsp_pipeline_init()
// must be called before any other pipeline function.
FFI_PLUGIN_EXPORT void nar_dsp_pipeline_dispose(void);

// Register a processor. The pipeline copies the descriptor fields — `desc`
// and `desc->vtable` need only outlive this call (though `desc->self` must
// outlive the pipeline — see dsp_processor.h). Calls vtable->init() here;
// a non-OK return from init() aborts registration (processor NOT added).
// Returns NATIVE_RUNTIME_ERROR_MODULE_LIMIT_REACHED if the table is full,
// or NATIVE_RUNTIME_ERROR_DUPLICATE_MODULE if the id is already registered.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_register_internal(
    const NarDspProcessorDescriptor* desc);

// Enable (`enabled`=1) or disable (`enabled`=0) a processor by id.
// Thread-safe (atomic write). Returns NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT
// if the id is not found.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_set_enabled(
    const char* id, int32_t enabled);

// Returns 1 if the named processor is enabled, 0 if disabled.
// Returns NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT (-1 equivalent cast) if not
// found — callers should compare against known positive values only.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_is_enabled(const char* id);

// Sum of latency_frames() across ALL registered processors (enabled or not).
// Zero in Phase 4 (gain processor has zero latency). Reserved for future
// A/V-sync-aware callers.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_total_latency_frames(void);

// Number of processors currently registered.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_processor_count(void);

// Processor id at `index` in registration order. Returns NULL if out of range.
// Owned by the pipeline — do not free.
FFI_PLUGIN_EXPORT const char* nar_dsp_pipeline_processor_id_at(int32_t index);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_DSP_PIPELINE_H_
