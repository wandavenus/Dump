// Shared dynamics processing utilities — Phase 6.
//
// Header-only (all static inline). No corresponding .c file.
// Include from comp_processor.c, limiter_processor.c, soft_clipper_processor.c.
//
// Contents:
//   - Fast dB ↔ linear conversions (expf/logf based)
//   - One-pole IIR time-constant coefficient helper
//   - Safe float ↔ int32 bit-cast utilities (avoids strict-aliasing UB)
//   - NarEnvelopeDetector — log-domain level follower with attack/release

#ifndef NATIVE_AUDIO_RUNTIME_DYNAMICS_COMMON_H_
#define NATIVE_AUDIO_RUNTIME_DYNAMICS_COMMON_H_

#include <math.h>
#include <stdint.h>
#include <string.h>

// ── Fast dB ↔ linear ─────────────────────────────────────────────────────────

// ln(10)/20  — for dBFS → linear: linear = exp(db * LN10_OVER_20)
#define NAR_LN10_OVER_20  0.11512925465f
// 20/ln(10)  — for linear → dBFS: db = log(linear) * NAR_20_OVER_LN10
#define NAR_20_OVER_LN10  8.68588963807f
// −144 dBFS ≈ floor for 24-bit audio; returned for linear ≤ 1.585e-8
#define NAR_SILENCE_DB    (-144.0f)

static inline float nar_db_to_linear(float db) {
  return expf(db * NAR_LN10_OVER_20);
}

// Maps a non-negative linear amplitude to dBFS.
// Returns NAR_SILENCE_DB for values at or below the digital silence floor.
static inline float nar_linear_to_db(float linear) {
  if (linear < 1.5849e-7f) return NAR_SILENCE_DB;  // 10^(−144/20)
  return logf(linear) * NAR_20_OVER_LN10;
}

// ── One-pole IIR time constant ────────────────────────────────────────────────

// Returns the per-sample coefficient for a one-pole smoother with the
// given time constant [ms] milliseconds at [sample_rate] Hz:
//
//   c = exp(-1 / (ms * 0.001 * Fs))
//
// Smoother recurrence: y[n] = c·y[n-1] + (1-c)·x[n]
// The 1/e time (≈ 63% step response) equals ms milliseconds.
//
// For ms ≤ 0 or sample_rate ≤ 0 returns 0.0 (instant response / no delay).
static inline float nar_time_coeff(float ms, float sample_rate) {
  if (ms <= 0.0f || sample_rate <= 0.0f) return 0.0f;
  return expf(-1.0f / (ms * 0.001f * sample_rate));
}

// ── Safe float ↔ int32 bit-cast ───────────────────────────────────────────────
// memcpy avoids strict-aliasing UB when type-punning. Identical pattern to
// gain_processor.c; shared here so each processor doesn't redeclare it.

static inline float nar_bits_to_float(int32_t bits) {
  float f; memcpy(&f, &bits, 4); return f;
}
static inline int32_t nar_float_to_bits(float f) {
  int32_t b; memcpy(&b, &f, 4); return b;
}

// ── Log-domain envelope detector ─────────────────────────────────────────────
//
// A simple one-pole IIR follower that tracks a signal's peak level in dBFS.
// Attack and release have independent time constants, allowing fast onset
// detection with slow recovery — typical for compressor side-chains.
//
// Usage:
//   NarEnvelopeDetector env;
//   nar_envelope_init(&env, 10.0f, 100.0f, 48000.0f);
//   float level_db = nar_envelope_update(&env, instantaneous_db);

typedef struct {
  float coeff_attack;   // one-pole coefficient for rising level
  float coeff_release;  // one-pole coefficient for falling level
  float value_db;       // current smoothed level in dBFS
} NarEnvelopeDetector;

static inline void nar_envelope_init(NarEnvelopeDetector* e,
                                      float attack_ms,
                                      float release_ms,
                                      float sample_rate) {
  e->coeff_attack  = nar_time_coeff(attack_ms,  sample_rate);
  e->coeff_release = nar_time_coeff(release_ms, sample_rate);
  e->value_db      = NAR_SILENCE_DB;
}

// Process one level sample and return the new smoothed value.
// Choose the attack coefficient when the level is rising, release otherwise.
static inline float nar_envelope_update(NarEnvelopeDetector* e, float level_db) {
  const float c = level_db > e->value_db ? e->coeff_attack : e->coeff_release;
  e->value_db = c * e->value_db + (1.0f - c) * level_db;
  return e->value_db;
}

#endif  // NATIVE_AUDIO_RUNTIME_DYNAMICS_COMMON_H_
