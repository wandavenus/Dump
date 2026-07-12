// Biquad (second-order IIR) filter — Phase 5.
//
// Coefficient computation follows the Audio EQ Cookbook by Robert Bristow-
// Johnson (https://webaudio.github.io/Audio-EQ-Cookbook/audio-eq-cookbook.html).
// Frequency response is parameterized by centre / corner frequency f0, quality
// factor Q, and (for Peak/Shelf types) a gain in dBFS.
//
// Processing uses Transposed Direct Form II (TDF-II):
//
//   y    = b0·x + s1
//   s1'  = b1·x − a1·y + s2
//   s2'  = b2·x − a2·y
//
// TDF-II is numerically superior to Direct Form I (no cancellation in the
// feedback path) and is SIMD-friendly: once the state variables s1/s2 are
// in registers, each sample requires only 5 multiplies + 4 adds with no
// data dependencies that prevent auto-vectorization of the outer loop.
//
// All coefficient structs store NORMALIZED coefficients (b0/a0, b1/a0 …)
// so the hot loop needs no additional division.
//
// This header is INTERNAL to native_audio_runtime. It is NOT exported via
// FFI_PLUGIN_EXPORT — callers use the higher-level peq_processor.h API.

#ifndef NATIVE_AUDIO_RUNTIME_BIQUAD_FILTER_H_
#define NATIVE_AUDIO_RUNTIME_BIQUAD_FILTER_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// ── Filter topologies ─────────────────────────────────────────────────────────

// Supported filter types. Integer values are part of the public Dart API
// (PeqFilterType enum in runtime_types.dart) — do NOT reorder.
typedef enum {
  NAR_BIQUAD_PEAK       = 0,  // Peaking EQ: boost/cut at centre frequency
  NAR_BIQUAD_LOW_SHELF  = 1,  // Low shelf: boost/cut below corner frequency
  NAR_BIQUAD_HIGH_SHELF = 2,  // High shelf: boost/cut above corner frequency
  NAR_BIQUAD_LOW_PASS   = 3,  // Low-pass (gain ignored)
  NAR_BIQUAD_HIGH_PASS  = 4,  // High-pass (gain ignored)
  NAR_BIQUAD_BAND_PASS  = 5,  // Band-pass, 0 dB peak gain (gain ignored)
  NAR_BIQUAD_NOTCH      = 6,  // Notch / band-reject (gain ignored)
} NarBiquadType;

// ── Coefficient struct ────────────────────────────────────────────────────────

// Normalized biquad coefficients (a0 already divided out).
// Layout: 5 × float32 = 20 bytes, 4-byte aligned — safe for atomic memcpy
// patterns on arm64 (individual 4-byte stores are naturally atomic).
//
// Positive sign convention: the TDF-II recurrence subtracts a1 and a2,
// so they are stored positive here (the denominator's sign is already
// accounted for in coefficient generation).
typedef struct {
  float b0, b1, b2;  // feed-forward
  float a1, a2;      // feed-back (positive; subtracted in the recurrence)
} NarBiquadCoeffs;

// ── Per-channel TDF-II delay state ───────────────────────────────────────────

// Maximum channels supported by the biquad state arrays. Must match
// NAR_PEQ_MAX_CHANNELS in peq_processor.h.
#define NAR_BIQUAD_MAX_CHANNELS 8

typedef struct {
  float s1[NAR_BIQUAD_MAX_CHANNELS];
  float s2[NAR_BIQUAD_MAX_CHANNELS];
} NarBiquadState;

// ── Coefficient computation ───────────────────────────────────────────────────

// Compute normalized biquad coefficients from first-principles parameters.
//
// [type]        : Filter topology (NarBiquadType).
// [freq_hz]     : Centre / corner frequency in Hz. Clamped to (1, Fs/2).
// [q]           : Quality factor (bandwidth control). Clamped to [0.001, 100].
//                 Q = 0.707 (1/√2) gives maximally flat (Butterworth) response
//                 for LP/HP; a standard starting point for Peak bands.
//                 For shelf filters, Q also controls the shelf slope
//                 (higher Q → steeper shelf).
// [gain_db]     : Gain in dBFS for Peak and Shelf types. Ignored for
//                 LP/HP/BP/Notch. Clamped to [-96, +24].
// [sample_rate] : Playback sample rate in Hz (e.g. 44100, 48000). Must be > 0.
// [out]         : Output struct; written only on success (return == OK).
//
// Returns NATIVE_RUNTIME_OK on success, or NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT
// if any argument is out of range (out == NULL, sample_rate <= 0, unknown type).
int32_t nar_biquad_compute(
    NarBiquadType    type,
    float            freq_hz,
    float            q,
    float            gain_db,
    float            sample_rate,
    NarBiquadCoeffs* out);

// ── Inline per-sample processing ─────────────────────────────────────────────

// Process one float32 sample x through the biquad, updating channel state
// [s1] and [s2] in place. Returns the filtered sample y.
//
// Called once per sample per band — must be inlined to avoid function-call
// overhead in the inner processing loop. The compiler will auto-vectorize
// the surrounding outer (frame) loop on arm64 once this is inlined.
static inline float nar_biquad_process_sample(
    const NarBiquadCoeffs* c,
    float* s1, float* s2,
    float x) {
  float y = c->b0 * x + *s1;
  *s1 = c->b1 * x - c->a1 * y + *s2;
  *s2 = c->b2 * x - c->a2 * y;
  return y;
}

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_BIQUAD_FILTER_H_
