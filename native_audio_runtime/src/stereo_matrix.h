// Stereo Matrix Framework — Phase 7.
//
// Header-only (all static inline). No corresponding .c file.
// Include from crossfeed_processor.c and any future stereo-processing module.
//
// A NarStereoMatrix is a 2×2 coefficient matrix applied to a stereo L/R pair:
//
//   [L_out]   [a00  a01] [L_in]
//   [R_out] = [a10  a11] [R_in]
//
// The matrix is stored in row-major order: a[row][col] where row selects the
// output channel and col selects the input channel.
//
// Common use cases (future-proof for Crossfeed, Width, M/S, Balance, Rotation):
//   nar_stereo_matrix_identity()   — pass through (L→L, R→R, no mixing)
//   nar_stereo_matrix_mono()       — full downmix to mono (M/S with side=0)
//   nar_stereo_matrix_width(w)     — stereo width scaling around the mid signal
//   nar_stereo_matrix_balance(pan) — pan law: unity gain on one side, zero on the other
//   nar_stereo_matrix_mid_side()   — M/S encode (M = (L+R)/2, S = (L-R)/2)
//
// Composition: matrices multiply (right-to-left application order):
//   Apply A first, then B:  result = B * A
//   Use nar_stereo_matrix_multiply() for chained effects.
//
// ── Thread safety ──────────────────────────────────────────────────────────────
//
// NarStereoMatrix is a plain 16-byte struct of four floats.
// It is safe to copy across threads as part of a larger double-buffer or
// atomic swap protocol (see crossfeed_processor.c). The matrix itself
// carries no mutable state — it is a pure coefficient bag.

#ifndef NATIVE_AUDIO_RUNTIME_STEREO_MATRIX_H_
#define NATIVE_AUDIO_RUNTIME_STEREO_MATRIX_H_

#ifdef __cplusplus
extern "C" {
#endif

// ── Stereo matrix type ────────────────────────────────────────────────────────

// 2×2 gain matrix for a stereo (L/R) signal pair.
// Layout: a[out_channel][in_channel].
// Stored as four floats (16 bytes) — fits in two 64-bit registers on arm64.
typedef struct {
  float a[2][2];  // a[0][0]=L→L, a[0][1]=R→L, a[1][0]=L→R, a[1][1]=R→R
} NarStereoMatrix;

// ── Application ───────────────────────────────────────────────────────────────

// Apply the 2×2 matrix to a single stereo frame (l_in, r_in) and write
// the result to (*l_out, *r_out). Both in-place (*l_out == &l_in is safe
// if the inputs are copied to temporaries first — the inline does this).
// Called once per stereo frame; inlined for SIMD compatibility.
static inline void nar_stereo_matrix_apply(
    const NarStereoMatrix* m,
    float l_in,  float r_in,
    float* l_out, float* r_out) {
  // Copy inputs first so in-place aliasing (*l_out == &l_in) is safe.
  const float l = l_in;
  const float r = r_in;
  *l_out = m->a[0][0] * l + m->a[0][1] * r;
  *r_out = m->a[1][0] * l + m->a[1][1] * r;
}

// ── Matrix composition ────────────────────────────────────────────────────────

// Multiply two 2×2 matrices: result = left × right.
// To apply right first then left: pass right as the second arg.
static inline NarStereoMatrix nar_stereo_matrix_multiply(
    const NarStereoMatrix* left,
    const NarStereoMatrix* right) {
  NarStereoMatrix out;
  for (int r = 0; r < 2; r++) {
    for (int c = 0; c < 2; c++) {
      out.a[r][c] = left->a[r][0] * right->a[0][c]
                  + left->a[r][1] * right->a[1][c];
    }
  }
  return out;
}

// ── Factory functions ─────────────────────────────────────────────────────────

// Identity: no mixing, unity gain on both channels.
//   L_out = L,  R_out = R
static inline NarStereoMatrix nar_stereo_matrix_identity(void) {
  return (NarStereoMatrix){{ {1.0f, 0.0f}, {0.0f, 1.0f} }};
}

// Full mono collapse: both outputs are the mono sum.
//   L_out = (L + R) / 2,  R_out = (L + R) / 2
static inline NarStereoMatrix nar_stereo_matrix_mono(void) {
  return (NarStereoMatrix){{ {0.5f, 0.5f}, {0.5f, 0.5f} }};
}

// Stereo width: scales the side (difference) component around the mid (sum).
//
// [width] : 0.0 = full mono collapse
//           1.0 = unity (identity), no change
//           2.0 = double width (exaggerated stereo)
//
// Derivation:
//   M = (L + R) / 2,  S = (L - R) / 2
//   L_out = M + w·S = ½(1+w)·L + ½(1−w)·R
//   R_out = M − w·S = ½(1−w)·L + ½(1+w)·R
static inline NarStereoMatrix nar_stereo_matrix_width(float w) {
  const float a = 0.5f * (1.0f + w);  // direct gain
  const float b = 0.5f * (1.0f - w);  // cross gain (may be negative for w>1)
  return (NarStereoMatrix){{ {a, b}, {b, a} }};
}

// Balance / pan: attenuates one channel linearly while the other stays at unity.
//
// [pan] : −1.0 = mute R (L only)
//          0.0 = center (identity)
//         +1.0 = mute L (R only)
//
// Uses a linear (not equal-power) pan law so the matrix remains a simple
// constant-coefficient multiplication. Equal-power panning requires sqrtf
// which does not belong in a data-structure factory.
static inline NarStereoMatrix nar_stereo_matrix_balance(float pan) {
  const float l_gain = (pan <= 0.0f) ? 1.0f : 1.0f - pan;
  const float r_gain = (pan >= 0.0f) ? 1.0f : 1.0f + pan;
  return (NarStereoMatrix){{ {l_gain, 0.0f}, {0.0f, r_gain} }};
}

// Mid/Side encode:
//   M_out = (L + R) / 2  (on the L output bus)
//   S_out = (L − R) / 2  (on the R output bus)
// Decode by applying another nar_stereo_matrix_mid_side_decode().
static inline NarStereoMatrix nar_stereo_matrix_mid_side_encode(void) {
  return (NarStereoMatrix){{ {0.5f, 0.5f}, {0.5f, -0.5f} }};
}

// Mid/Side decode: inverse of the encode matrix.
//   L_out = M + S
//   R_out = M − S
static inline NarStereoMatrix nar_stereo_matrix_mid_side_decode(void) {
  return (NarStereoMatrix){{ {1.0f, 1.0f}, {1.0f, -1.0f} }};
}

// Simple crossfeed blend matrix (no frequency dependence — for use when a
// processor wants a flat mix stage as part of a larger algorithm).
//
// [amount] : 0.0 = identity, 1.0 = full mono.
//            Clamped to [0, 1] by the caller.
//   L_out = (1−amount)·L + amount·R   (normalized by 1/(1+amount))
//   R_out = (1−amount)·R + amount·L
//
// Note: the frequency-dependent crossfeed in crossfeed_processor.c uses
// lowpass-filtered cross signals and applies the matrix itself — this
// flat-blend helper is for simpler mixing stages.
static inline NarStereoMatrix nar_stereo_matrix_crossblend(float amount) {
  if (amount < 0.0f) amount = 0.0f;
  if (amount > 1.0f) amount = 1.0f;
  const float norm   = 1.0f / (1.0f + amount);
  const float direct = norm;               // (1) * norm
  const float cross  = amount * norm;      // amount * norm
  return (NarStereoMatrix){{ {direct, cross}, {cross, direct} }};
}

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_STEREO_MATRIX_H_
