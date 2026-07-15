// neon_kernels.h — ARM64 NEON audio kernel declarations
//
// Compiled only for AArch64 (arm64-v8a).  All declarations are guarded by
// __aarch64__ so that x86_64 host builds (unit tests, web) never reference
// these symbols.
//
// Usage in C:
//   #if defined(__aarch64__)
//   #include "neon_kernels.h"
//   // ... call nar_gain_apply_neon() / nar_biquad_stereo_neon()
//   #endif
//
// The implementations live in neon_kernels.S (ARM64 NEON Assembly).

#ifndef NATIVE_AUDIO_RUNTIME_NEON_KERNELS_H_
#define NATIVE_AUDIO_RUNTIME_NEON_KERNELS_H_

#include <stdint.h>

#ifdef __aarch64__

#ifdef __cplusplus
extern "C" {
#endif

// ─────────────────────────────────────────────────────────────────────────────
// nar_gain_apply_neon
//
// Multiply every sample in data[0..samples-1] by gain_linear (in-place).
//
//   data        — pointer to interleaved float32 PCM buffer (L/R/L/R/…)
//   samples     — total sample count (frames × channels)
//   gain_linear — pre-computed linear gain scalar (finite, non-negative)
//
// Performance:  16 samples per main-loop iteration using four fmul v.4s
//               instructions.  Falls back to scalar for samples % 16 != 0.
//
// Thread safety: caller ensures exclusive access to [data].
//
// Note: non-finite samples in the buffer are NOT sanitized by this kernel —
// the C caller's isfinite() guard is skipped for NEON throughput, consistent
// with how the compiler would auto-vectorize the scalar hot-loop. The
// soft_clipper at the end of the DSP chain is the pipeline safety net.
// ─────────────────────────────────────────────────────────────────────────────
void nar_gain_apply_neon(float* data, int32_t samples, float gain_linear);

// ─────────────────────────────────────────────────────────────────────────────
// nar_biquad_stereo_neon
//
// Process LEFT and RIGHT channels simultaneously through the same biquad
// using 2-lane NEON vectors (v.2s).
//
// Implements the Transposed Direct Form II (TDF-II) recurrence for two
// independent channels sharing the same coefficients:
//
//   y    = b0·x + s1
//   s1'  = b1·x − a1·y + s2
//   s2'  = b2·x − a2·y
//
// Arguments:
//   coeffs  — pointer to float[5] = {b0, b1, b2, a1, a2} (normalized, a0=1)
//   x_l     — left  channel input sample
//   x_r     — right channel input sample
//   s1_l    — left  channel delay state 1 (read and updated in-place)
//   s1_r    — right channel delay state 1 (read and updated in-place)
//   s2_l    — left  channel delay state 2 (read and updated in-place)
//   s2_r    — right channel delay state 2 (read and updated in-place)
//   y_l     — left  channel output (written)
//   y_r     — right channel output (written)
//
// This replaces two sequential calls to nar_biquad_process_sample() (one for
// L, one for R), halving the biquad compute cost on stereo content.
//
// Intended call sites:
//   • loudness_processor.c: K-weighting Stage 1 + Stage 2 on stereo frames
//   • crossfeed_processor.c: LP and HF shelf biquads (after refactor)
//
// Thread safety: caller ensures exclusive access to the state pointers.
// ─────────────────────────────────────────────────────────────────────────────
void nar_biquad_stereo_neon(
    const float* coeffs,
    float  x_l,
    float  x_r,
    float* s1_l,
    float* s1_r,
    float* s2_l,
    float* s2_r,
    float* y_l,
    float* y_r);

#ifdef __cplusplus
}
#endif

#endif  // __aarch64__
#endif  // NATIVE_AUDIO_RUNTIME_NEON_KERNELS_H_
