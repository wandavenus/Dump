// Compressor Processor — Phase 6.
//
// Feed-forward, soft-knee dynamic range compressor.
// Registers as "dsp.compressor" at pipeline slot 2 (after dsp.peq).
//
// Signal path inside process():
//   1. For each frame: find peak absolute value across all channels.
//   2. Convert to dBFS. Smooth via log-domain attack/release envelope.
//   3. Compute gain reduction using the soft-knee gain computer.
//   4. Add makeup gain. Convert to linear.
//   5. Apply the same linear gain to all channels at that frame (stereo-linked).
//
// Parameter updates are thread-safe (acquire/release dirty-flag protocol, same
// as the PEQ). Coefficients (coeff_attack, coeff_release) are pre-computed on
// the control thread via nar_time_coeff(); the audio thread does no
// transcendental math for parameter adoption.

#ifndef NATIVE_AUDIO_RUNTIME_COMP_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_COMP_PROCESSOR_H_

#include <stdint.h>
#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Register the compressor processor with the DSP pipeline.
// Must be called after nar_peq_processor_register_internal().
// Idempotent (returns NATIVE_RUNTIME_ERROR_DUPLICATE_MODULE if already registered).
FFI_PLUGIN_EXPORT int32_t nar_comp_processor_register_internal(void);

// Configure all compressor parameters in one atomic call.
//
// [threshold_db]   : Level above which compression begins. Default: -20.0 dBFS.
//                    Clamped to (−96, 0).
// [ratio]          : Compression ratio N:1. Default: 4.0. Clamped to [1.001, 100].
//                    1.0 = no compression (unity); ∞ ≈ brickwall (use the Limiter).
// [attack_ms]      : Envelope rise time (1/e). Default: 10.0 ms. [0.1, 500].
// [release_ms]     : Envelope fall time (1/e). Default: 100.0 ms. [1, 2000].
// [knee_db]        : Soft-knee half-width. Default: 6.0 dB. [0, 24].
//                    0 = hard knee. Larger values give smoother onset.
// [makeup_gain_db] : Post-compression gain offset. Default: 0.0 dBFS. [−24, 24].
// [sample_rate]    : Current playback sample rate. ≤ 0 → 48000 Hz fallback.
//
// Thread-safe: may be called from any thread while process() is running.
FFI_PLUGIN_EXPORT int32_t nar_comp_set_params(
    float threshold_db,
    float ratio,
    float attack_ms,
    float release_ms,
    float knee_db,
    float makeup_gain_db,
    float sample_rate);

// Enable (bypass=0) or bypass (bypass=1) the compressor.
// When bypassed, process() is a zero-copy early return. Thread-safe.
FFI_PLUGIN_EXPORT void    nar_comp_set_bypass(int32_t bypass);
FFI_PLUGIN_EXPORT int32_t nar_comp_get_bypass(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_COMP_PROCESSOR_H_
