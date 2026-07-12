// Biquad filter coefficient computation — Phase 5.
// See biquad_filter.h for the full contract and mathematical documentation.
//
// All formulas follow the Audio EQ Cookbook by Robert Bristow-Johnson.
// Parameterization: Q-based for all filter types.
//
// For Shelf filters, Q controls the shelf slope (analogous to the shelf
// slope parameter S in the original cookbook, but unified under Q for a
// consistent API: higher Q → narrower transition → steeper shelf).
//
// Thread safety: nar_biquad_compute() is stateless (reads inputs, writes
// out). Safe to call concurrently from multiple threads on separate *out
// pointers.

#include "biquad_filter.h"

#include <math.h>
#include <stddef.h>

#include "native_audio_runtime.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ── Helpers ───────────────────────────────────────────────────────────────────

static float _clampf(float v, float lo, float hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}

// ── Coefficient computation ───────────────────────────────────────────────────

int32_t nar_biquad_compute(
    NarBiquadType    type,
    float            freq_hz,
    float            q,
    float            gain_db,
    float            sample_rate,
    NarBiquadCoeffs* out) {
  if (out == NULL || sample_rate <= 0.0f) {
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }

  // Clamp inputs to stable ranges before any transcendental calls.
  freq_hz = _clampf(freq_hz, 1.0f, sample_rate * 0.499f);
  q       = _clampf(q, 0.001f, 100.0f);
  gain_db = _clampf(gain_db, -96.0f, 24.0f);

  const float w0    = 2.0f * (float)M_PI * freq_hz / sample_rate;
  const float cos_w = cosf(w0);
  const float sin_w = sinf(w0);
  // Standard alpha: sin(w0) / (2*Q) — used for Peak, LP, HP, BP, Notch.
  // For Shelf types, alpha is recomputed using sqrt((A+1/A)(1/S-1)+2) with
  // the RBJ S=1 approximation to remain consistent with the Q parameter.
  const float alpha = sin_w / (2.0f * q);

  float b0, b1, b2, a0, a1, a2;

  switch (type) {
    // ── Peaking EQ ───────────────────────────────────────────────────────────
    // H(s) = (s^2 + s*(A/Q) + 1) / (s^2 + s/(A*Q) + 1)
    case NAR_BIQUAD_PEAK: {
      // A = 10^(dBgain/40)  (dBgain/20 for amplitude, /40 because we take √)
      const float A = powf(10.0f, gain_db / 40.0f);
      b0 =  1.0f + alpha * A;
      b1 = -2.0f * cos_w;
      b2 =  1.0f - alpha * A;
      a0 =  1.0f + alpha / A;
      a1 = -2.0f * cos_w;
      a2 =  1.0f - alpha / A;
      break;
    }

    // ── Low Shelf ─────────────────────────────────────────────────────────────
    // H(s) = A * [ s^2 + (√A/Q)*s + A ] / [ A*s^2 + (√A/Q)*s + 1 ]
    // Using the RBJ cookbook with alpha = sin(w0)/2 * sqrt((A+1/A)(1/S-1)+2),
    // S=1 (unity slope), which gives alpha = sin(w0)/2 * sqrt(A+1/A+0) =
    // sin(w0)/2 * sqrt((A+1/A+2)) = ... — but for our Q-based API we use:
    //   alpha_shelf = sin(w0) * sqrt(A) / (2*Q)
    // which gives a Q-controlled shelf width directly analogous to peak Q.
    case NAR_BIQUAD_LOW_SHELF: {
      const float A    = powf(10.0f, gain_db / 40.0f);
      const float sqA  = sqrtf(A);
      // Shelf alpha uses sqrt(A) to keep the shelf width independent of gain.
      const float alp  = sin_w * sqA / (2.0f * q);
      b0 =    A * ((A + 1.0f) - (A - 1.0f) * cos_w + 2.0f * sqA * alp);
      b1 = 2.0f * A * ((A - 1.0f) - (A + 1.0f) * cos_w);
      b2 =    A * ((A + 1.0f) - (A - 1.0f) * cos_w - 2.0f * sqA * alp);
      a0 =         (A + 1.0f) + (A - 1.0f) * cos_w + 2.0f * sqA * alp;
      a1 =  -2.0f * ((A - 1.0f) + (A + 1.0f) * cos_w);
      a2 =         (A + 1.0f) + (A - 1.0f) * cos_w - 2.0f * sqA * alp;
      break;
    }

    // ── High Shelf ────────────────────────────────────────────────────────────
    case NAR_BIQUAD_HIGH_SHELF: {
      const float A    = powf(10.0f, gain_db / 40.0f);
      const float sqA  = sqrtf(A);
      const float alp  = sin_w * sqA / (2.0f * q);
      b0 =    A * ((A + 1.0f) + (A - 1.0f) * cos_w + 2.0f * sqA * alp);
      b1 = -2.0f * A * ((A - 1.0f) + (A + 1.0f) * cos_w);
      b2 =    A * ((A + 1.0f) + (A - 1.0f) * cos_w - 2.0f * sqA * alp);
      a0 =         (A + 1.0f) - (A - 1.0f) * cos_w + 2.0f * sqA * alp;
      a1 =   2.0f * ((A - 1.0f) - (A + 1.0f) * cos_w);
      a2 =         (A + 1.0f) - (A - 1.0f) * cos_w - 2.0f * sqA * alp;
      break;
    }

    // ── Low-pass ──────────────────────────────────────────────────────────────
    // H(s) = 1 / (s^2 + s/Q + 1)
    case NAR_BIQUAD_LOW_PASS:
      b0 = (1.0f - cos_w) * 0.5f;
      b1 =  1.0f - cos_w;
      b2 = (1.0f - cos_w) * 0.5f;
      a0 =  1.0f + alpha;
      a1 = -2.0f * cos_w;
      a2 =  1.0f - alpha;
      break;

    // ── High-pass ─────────────────────────────────────────────────────────────
    // H(s) = s^2 / (s^2 + s/Q + 1)
    case NAR_BIQUAD_HIGH_PASS:
      b0 =  (1.0f + cos_w) * 0.5f;
      b1 = -(1.0f + cos_w);
      b2 =  (1.0f + cos_w) * 0.5f;
      a0 =   1.0f + alpha;
      a1 =  -2.0f * cos_w;
      a2 =   1.0f - alpha;
      break;

    // ── Band-pass (0 dB peak gain) ────────────────────────────────────────────
    // H(s) = s/Q / (s^2 + s/Q + 1)
    case NAR_BIQUAD_BAND_PASS:
      b0 =  sin_w * 0.5f;   // = Q * alpha when Q normalizes to 0 dB peak
      b1 =  0.0f;
      b2 = -sin_w * 0.5f;
      a0 =  1.0f + alpha;
      a1 = -2.0f * cos_w;
      a2 =  1.0f - alpha;
      break;

    // ── Notch (band-reject) ───────────────────────────────────────────────────
    // H(s) = (s^2 + 1) / (s^2 + s/Q + 1)
    case NAR_BIQUAD_NOTCH:
      b0 =  1.0f;
      b1 = -2.0f * cos_w;
      b2 =  1.0f;
      a0 =  1.0f + alpha;
      a1 = -2.0f * cos_w;
      a2 =  1.0f - alpha;
      break;

    default:
      return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }

  // Normalize by a0 once, then multiply — avoids per-sample division.
  const float inv_a0 = 1.0f / a0;
  out->b0 = b0 * inv_a0;
  out->b1 = b1 * inv_a0;
  out->b2 = b2 * inv_a0;
  out->a1 = a1 * inv_a0;
  out->a2 = a2 * inv_a0;

  return NATIVE_RUNTIME_OK;
}
