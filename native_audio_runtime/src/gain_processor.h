// Gain Processor — Phase 4.
//
// The first concrete NarDspProcessor: a gain stage that multiplies every
// interleaved float32 sample by a linear factor derived from a dBFS value.
//
// Design goals for Phase 4:
//   - Validate the DSP pipeline end-to-end (this processor is not exposed
//     in the final UI — it is a pipeline scaffold).
//   - Zero-copy bypass: when bypass is active, process() returns immediately
//     without touching any sample data.
//   - Thread-safe knobs: gain_db and bypass use atomic storage so a UI thread
//     can adjust them while process() runs on the audio thread.
//   - SIMD-ready inner loop: plain indexed multiply — the compiler will
//     auto-vectorize this with NEON on arm64. Future phases can drop in
//     explicit NEON intrinsics without changing the surrounding pipeline code.
//   - No clipping: the processor does not add artificial hard-limiting at its
//     output. Output amplitude is the caller's downstream responsibility.
//
// Lifecycle (called by the pipeline, not directly by Dart):
//   nar_gain_processor_register_internal() → pipeline.register_internal()
//     → vtable.init()    one-time setup (sets defaults, returns OK)
//     → vtable.process() called per buffer while enabled
//     → vtable.reset()   no-op (stateless processor)
//     → vtable.dispose() no-op (no dynamic memory owned internally)

#ifndef NATIVE_AUDIO_RUNTIME_GAIN_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_GAIN_PROCESSOR_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Register the gain processor with the DSP pipeline. Must be called AFTER
// nar_dsp_pipeline_init(). Calls pipeline's register_internal() which in
// turn calls vtable->init(). Returns NATIVE_RUNTIME_OK on success.
// The processor id is "dsp.gain".
FFI_PLUGIN_EXPORT int32_t nar_gain_processor_register_internal(void);

// Set the target gain in dBFS. Clamped to [-96.0, +24.0] internally.
// Thread-safe: may be called from any thread while process() is running.
FFI_PLUGIN_EXPORT void nar_gain_processor_set_gain_db(float gain_db);

// Returns the current gain in dBFS (after clamping).
FFI_PLUGIN_EXPORT float nar_gain_processor_get_gain_db(void);

// Enable (bypass=0, default) or bypass (bypass=1) the processor.
// When bypass is active, process() is a true zero-copy no-op.
// Thread-safe.
FFI_PLUGIN_EXPORT void nar_gain_processor_set_bypass(int32_t bypass);

// Returns 1 if bypass is active, 0 if gain is being applied.
FFI_PLUGIN_EXPORT int32_t nar_gain_processor_get_bypass(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_GAIN_PROCESSOR_H_
