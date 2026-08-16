// Soft Clipper Processor — Phase 6.
//
// Lightweight hyperbolic-tangent waveshaper that prevents digital clipping.
// Registers as "dsp.soft_clipper" at pipeline slot 6 (0-indexed, last in the
// chain: gain=0, replaygain=1, loudness=2, comp=3, crossfeed=4, limiter=5).
//
// Algorithm:
//   - Samples with |x| ≤ threshold pass through UNCHANGED (transparent).
//   - Samples with |x| > threshold are shaped by:
//
//       y = threshold + range · tanh((|x| − threshold) / range) · sign(x)
//
//     where range = 1.0 − threshold_linear (distance from threshold to 0 dBFS).
//
// Properties:
//   - C¹ continuous at the threshold (derivative = 1.0 from both sides).
//   - Output approaches 1.0 (0 dBFS) asymptotically — truly soft limiting.
//   - No DC offset.
//   - tanhf() is only called for samples that EXCEED the threshold.
//     Well-mastered audio rarely exceeds −0.5 dBFS; overhead is near zero.
//
// Parameters:
//   threshold_db : Level above which soft clipping begins. Default: −0.5 dBFS.
//                  Clamped to [−12, −0.001). The "ceiling" is always 0 dBFS.
//
// Thread-safety: atomic float bit-pattern trick (same as gain_processor.c).
// Only one configurable parameter, so the simple atomic trick suffices without
// needing the heavier double-buffer protocol.

#ifndef NATIVE_AUDIO_RUNTIME_SOFT_CLIPPER_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_SOFT_CLIPPER_PROCESSOR_H_

#include <stdint.h>
#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Register the soft clipper processor with the DSP pipeline.
// Must be called after nar_limiter_processor_register_internal().
FFI_PLUGIN_EXPORT int32_t nar_soft_clipper_processor_register_internal(void);

// Set the soft-clip threshold in dBFS.
// Above this level, the tanh curve is applied. Below it, signal is transparent.
// [threshold_db] : Default: −0.5 dBFS. Clamped to [−12, −0.001).
FFI_PLUGIN_EXPORT void  nar_soft_clipper_set_threshold_db(float threshold_db);
FFI_PLUGIN_EXPORT float nar_soft_clipper_get_threshold_db(void);

// Enable (bypass=0) or bypass (bypass=1). Thread-safe.
FFI_PLUGIN_EXPORT void    nar_soft_clipper_set_bypass(int32_t bypass);
FFI_PLUGIN_EXPORT int32_t nar_soft_clipper_get_bypass(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_SOFT_CLIPPER_PROCESSOR_H_
