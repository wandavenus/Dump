// native_audio_runtime/tool/neon_diff_test.c
//
// Differential test for the four hand-written ARM64 NEON kernels in
// native_audio_runtime/src/*.S.
//
// Why this exists
// ---------------
// NEON selection in the C sources is compile-time (`#if defined(__aarch64__)`),
// and the .S files are guarded the same way. On an x86_64 host (the normal
// `dart test` / `flutter test` runner) they compile to empty translation units,
// so the existing suites never execute a single NEON instruction. This harness
// is the only place where the assembly is actually executed and compared
// against an independent reference.
//
// Build and run it with tools/neon_diff_regression.sh — it picks a native
// AArch64 compiler when the host is arm64, otherwise cross-compiles with clang
// and runs the result under qemu-aarch64.
//
// Freestanding by design: no libc and no libm are linked, so the same binary
// builds on any AArch64 host and under qemu. Only raw syscalls are used.
//
// The references below are NOT the repo's portable C paths. They mirror the
// kernels' exact instruction shape, because that shape is part of the contract:
//
//   * nar_biquad_stereo_neon uses fmls (fused) for the s1/s2 updates in steps 2
//     and 3, but a separate fmul + fadd for y in step 1.
//   * nar_automix_window_rms_neon accumulates four independent fused lanes
//     (fmla) and reduces them with faddp/faddp — not a sequential sum.
//   * nar_automix_tone_process_stereo_neon uses fmla in the one-pole filters and
//     in the band mix, but fmul + fadd for the 20 ms gain smoothing.
//
// A reference written with plain multiply/add therefore reports a mismatch even
// when the assembly is correct. Measured on this repo: for the stereo biquad at
// PCM level the plain-C shape differs from the kernel by up to ~1.1e-6
// (~19 * 2^-24, about -119 dBFS) after 5000 recursive steps. That is inaudible
// and expected, but it means cross-architecture tests must not assert
// bit-equality against the portable C path.

#include <stdint.h>

#if !defined(__aarch64__)
#error "neon_diff_test.c only compiles for AArch64 (see tools/neon_diff_regression.sh)"
#endif

// ─── Kernels under test ─────────────────────────────────────────────────────
extern void nar_gain_apply_neon(float* data, int32_t samples, float gain_linear);

extern void nar_biquad_stereo_neon(
    const float* coeffs,
    float x_l, float x_r,
    float* s1_l, float* s1_r,
    float* s2_l, float* s2_r,
    float* y_l,  float* y_r);

extern float nar_automix_window_rms_neon(
    const float* pcm, const float* hann, float* fft_real, int32_t count);

// Only the fields the assembly reads (offsets 0..100) are modelled; the
// true-peak limiter tail is never touched by the kernel. The offsets are
// asserted below and match the _Static_assert block in
// automix_tone_processor.c.
typedef struct {
  float   low_pass_state[8];     //   0
  float   high_cut_state[8];     //  32
  float   low_pass_alpha;        //  64
  float   high_cut_alpha;        //  68
  float   gain_smoothing_alpha;  //  72
  float   current_bass_gain;     //  76
  float   current_high_gain;     //  80
  int32_t sample_rate;           //  84
  int32_t channel_count;         //  88
  float   current_fade_gain;     //  92
  int32_t configured;            //  96
  float   current_mid_gain;      // 100
  char    tail[128];             // unused by the kernel
} ToneState;

_Static_assert(__builtin_offsetof(ToneState, low_pass_state)      ==   0, "offset 0");
_Static_assert(__builtin_offsetof(ToneState, high_cut_state)      ==  32, "offset 32");
_Static_assert(__builtin_offsetof(ToneState, low_pass_alpha)      ==  64, "offset 64");
_Static_assert(__builtin_offsetof(ToneState, high_cut_alpha)      ==  68, "offset 68");
_Static_assert(__builtin_offsetof(ToneState, gain_smoothing_alpha) ==  72, "offset 72");
_Static_assert(__builtin_offsetof(ToneState, current_bass_gain)   ==  76, "offset 76");
_Static_assert(__builtin_offsetof(ToneState, current_high_gain)   ==  80, "offset 80");
_Static_assert(__builtin_offsetof(ToneState, current_fade_gain)   ==  92, "offset 92");
_Static_assert(__builtin_offsetof(ToneState, current_mid_gain)    == 100, "offset 100");

extern void nar_automix_tone_process_stereo_neon(
    float* pcm, int32_t frames, ToneState* state,
    float target_bass, float target_mid, float target_high, float target_fade);

// ─── Freestanding runtime (raw syscalls only) ───────────────────────────────
static long sys_write(long fd, const void* buf, unsigned long n) {
  register long x8 __asm__("x8") = 64;   // __NR_write
  register long x0 __asm__("x0") = fd;
  register const void* x1 __asm__("x1") = buf;
  register unsigned long x2 __asm__("x2") = n;
  __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
  return x0;
}

static void sys_exit(int code) {
  register long x8 __asm__("x8") = 93;   // __NR_exit
  register long x0 __asm__("x0") = code;
  __asm__ volatile("svc #0" :: "r"(x8), "r"(x0));
  __builtin_unreachable();
}

static char out_buf[2048];
static unsigned out_len;

static void p_ch(char c) { if (out_len < sizeof out_buf) out_buf[out_len++] = c; }
static void p_str(const char* s) { while (*s) p_ch(*s++); }
static void p_u32(uint32_t v) {
  char tmp[12];
  int n = 0;
  if (!v) { p_ch('0'); return; }
  while (v) { tmp[n++] = (char)('0' + (v % 10u)); v /= 10u; }
  while (n) p_ch(tmp[--n]);
}
static void p_flush(void) { if (out_len) sys_write(1, out_buf, out_len); out_len = 0; }

// ─── Shared helpers ─────────────────────────────────────────────────────────
typedef union { float f; uint32_t u; } FBit;
static int bit_equal(float a, float b) { FBit x, y; x.f = a; y.f = b; return x.u == y.u; }
static float f_abs(float v) { return v < 0.0f ? -v : v; }

static const float kMaxFinite = 3.40282346638528859811704183484516925440e+38f;

static uint32_t g_rng = 0x9e3779b9u;
static uint32_t next_rand(void) {
  g_rng ^= g_rng << 13;
  g_rng ^= g_rng >> 17;
  g_rng ^= g_rng << 5;
  return g_rng;
}

// Finite float with an exponent in [emin, emax] — deterministic, and wide
// enough to cover denormals (exp 0) up to large finite values.
static float next_rnd_float(unsigned emin, unsigned emax) {
  FBit v;
  const unsigned e = emin + (next_rand() % (emax - emin + 1u));
  v.u = (next_rand() & 0x80000000u) | (e << 23) | (next_rand() & 0x007fffffu);
  return v.f;
}

// Input values that exercise the non-finite and out-of-range paths.
static float edge_input(int32_t i) {
  switch (i) {
    case 5:  return __builtin_nanf("");
    case 6:  return __builtin_inff();
    case 7:  return -__builtin_inff();
    case 8:  return 2.5f;   // above the sample-peak ceiling
    case 9:  return -3.0f;
    case 10: return 0.0f;
    default: return next_rnd_float(120u, 127u);   // about 2^-7 .. 1
  }
}

static uint32_t g_failures;

static void report(const char* name, uint32_t pcm_bad, uint32_t state_bad) {
  const uint32_t bad = pcm_bad + state_bad;
  g_failures += bad;
  p_str(name);
  p_str("  pcm-mismatch=");   p_u32(pcm_bad);
  p_str("  state-mismatch="); p_u32(state_bad);
  p_str(bad ? "  FAIL\n" : "  ok\n");
}

// ─── 1. nar_gain_apply_neon ─────────────────────────────────────────────────
// In-place multiply; the kernel has 16-sample vector iterations plus 16/8/4/1
// scalar tails, so every remainder must be covered.
static void test_gain(void) {
  float buf[64];
  float ref[64];
  uint32_t bad = 0;
  const float gain = 0.75f;

  for (int32_t n = 1; n <= 40; ++n) {
    for (int32_t i = 0; i < n; ++i) {
      buf[i] = next_rnd_float(0u, 150u);
      ref[i] = buf[i];
    }
    nar_gain_apply_neon(buf, n, gain);
    for (int32_t i = 0; i < n; ++i) {
      if (!bit_equal(buf[i], ref[i] * gain)) ++bad;
    }
  }
  report("gain          (1..40 samples)   ", bad, 0);
}

// ─── 2. nar_biquad_stereo_neon ──────────────────────────────────────────────
// TDF-II recurrence. Step 1 is a separate multiply + add; steps 2 and 3 use the
// fused multiply-subtract the assembly emits (fmls == fmaf(-a, y, acc)).
// Coefficients: RBJ low-pass, fc = 1 kHz, fs = 48 kHz, Q = 0.7071.
static const float kBiquadCoeffs[5] = {
    0.00391607f, 0.00783214f, 0.00391607f, -1.81534108f, 0.83100737f};

typedef struct { float s1l, s1r, s2l, s2r; } BiquadState;

static void biquad_reference(const float* c, float x_l, float x_r, BiquadState* s,
                             float* y_l, float* y_r) {
  const float out_l = c[0] * x_l + s->s1l;          // fmul + fadd
  const float out_r = c[0] * x_r + s->s1r;
  float n1_l = c[1] * x_l;                          // fmul
  n1_l = __builtin_fmaf(-c[3], out_l, n1_l);        // fmls
  n1_l = n1_l + s->s2l;                             // fadd
  float n1_r = c[1] * x_r;
  n1_r = __builtin_fmaf(-c[3], out_r, n1_r);
  n1_r = n1_r + s->s2r;
  float n2_l = c[2] * x_l;
  n2_l = __builtin_fmaf(-c[4], out_l, n2_l);        // fmls
  float n2_r = c[2] * x_r;
  n2_r = __builtin_fmaf(-c[4], out_r, n2_r);
  s->s1l = n1_l; s->s1r = n1_r; s->s2l = n2_l; s->s2r = n2_r;
  *y_l = out_l; *y_r = out_r;
}

static void test_biquad(void) {
  BiquadState kern = {0, 0, 0, 0};
  BiquadState ref  = {0, 0, 0, 0};
  uint32_t pcm_bad = 0, state_bad = 0;

  for (uint32_t i = 0; i < 5000u; ++i) {
    const float x_l = next_rnd_float(95u, 135u);
    const float x_r = next_rnd_float(95u, 135u);
    float y_l, y_r, r_l, r_r;

    nar_biquad_stereo_neon(kBiquadCoeffs, x_l, x_r,
                           &kern.s1l, &kern.s1r, &kern.s2l, &kern.s2r, &y_l, &y_r);
    biquad_reference(kBiquadCoeffs, x_l, x_r, &ref, &r_l, &r_r);

    if (!bit_equal(y_l, r_l) || !bit_equal(y_r, r_r)) ++pcm_bad;
    if (!bit_equal(kern.s1l, ref.s1l) || !bit_equal(kern.s1r, ref.s1r) ||
        !bit_equal(kern.s2l, ref.s2l) || !bit_equal(kern.s2r, ref.s2r)) ++state_bad;
  }
  report("biquad stereo (5000 steps)     ", pcm_bad, state_bad);
}

// ─── 3. nar_automix_window_rms_neon ─────────────────────────────────────────
// Hann window into fft_real (plain product) plus four independent fused
// power accumulators reduced with faddp/faddp. The name says "rms" but the
// kernel returns the power sum — the caller takes the square root.
static void window_reference(const float* pcm, const float* hann, float* dst,
                             int32_t n, float* out_sum) {
  float acc[4] = {0.0f, 0.0f, 0.0f, 0.0f};
  for (int32_t i = 0; i < n; ++i) {
    dst[i] = hann[i] * pcm[i];
    acc[i & 3] = __builtin_fmaf(pcm[i], pcm[i], acc[i & 3]);
  }
  *out_sum = (acc[0] + acc[1]) + (acc[2] + acc[3]);
}

static float g_pcm[2048], g_hann[2048], g_win[2048], g_ref[2048];

static void test_window(int32_t n) {
  for (int32_t i = 0; i < n; ++i) {
    g_pcm[i]  = next_rnd_float(120u, 127u);
    g_hann[i] = next_rnd_float(120u, 127u);
  }
  const float sum_kernel = nar_automix_window_rms_neon(g_pcm, g_hann, g_win, n);
  float sum_ref;
  window_reference(g_pcm, g_hann, g_ref, n, &sum_ref);

  uint32_t pcm_bad = 0;
  for (int32_t i = 0; i < n; ++i) {
    if (!bit_equal(g_win[i], g_ref[i])) ++pcm_bad;
  }
  const uint32_t state_bad = bit_equal(sum_kernel, sum_ref) ? 0u : 1u;

  char name[64];
  int k = 0;
  const char* prefix = "window+rms    (n=";
  while (*prefix) name[k++] = *prefix++;
  // n is always 256/1024/2048 in this harness; render it without printf.
  char digits[12];
  int d = 0;
  int32_t v = n;
  while (v) { digits[d++] = (char)('0' + (v % 10)); v /= 10; }
  while (d) name[k++] = digits[--d];
  name[k++] = ')';
  name[k] = '\0';
  report(name, pcm_bad, state_bad);
}

// ─── 4. nar_automix_tone_process_stereo_neon ────────────────────────────────
static void tone_init(ToneState* s, float bass, float mid, float high, float fade) {
  for (int i = 0; i < 8; ++i) { s->low_pass_state[i] = 0.0f; s->high_cut_state[i] = 0.0f; }
  s->low_pass_alpha      = 0.019f;   // 150 Hz one-pole at 48 kHz
  s->high_cut_alpha      = 0.145f;   // 1.2 kHz one-pole at 48 kHz
  s->gain_smoothing_alpha = 0.001f;  // 20 ms time constant
  s->current_bass_gain   = bass;
  s->current_high_gain   = high;
  s->current_mid_gain    = mid;
  s->current_fade_gain   = fade;
  s->sample_rate         = 48000;
  s->channel_count       = 2;
  s->configured          = 1;
  for (unsigned i = 0; i < sizeof s->tail; ++i) s->tail[i] = 0;
}

static void tone_reference(float* pcm, int32_t frames, ToneState* st,
                           float target_bass, float target_mid,
                           float target_high, float target_fade) {
  float bass = st->current_bass_gain;
  float mid  = st->current_mid_gain;
  float high = st->current_high_gain;
  float fade = st->current_fade_gain;
  float lp_l = st->low_pass_state[0],  lp_r = st->low_pass_state[1];
  float hc_l = st->high_cut_state[0], hc_r = st->high_cut_state[1];
  const float a_lp = st->low_pass_alpha;
  const float a_hc = st->high_cut_alpha;
  const float a_gs = st->gain_smoothing_alpha;

  if (frames <= 0) return;   // kernel writes the unchanged registers back

  const float fade_step = (target_fade - fade) / (float)frames;

  for (int32_t i = 0; i < frames; ++i) {
    // Gain smoothing: fmul + fadd, deliberately not fused.
    bass = bass + (target_bass - bass) * a_gs;
    mid  = mid  + (target_mid  - mid)  * a_gs;
    high = high + (target_high - high) * a_gs;
    fade = fade + fade_step;

    float x_l = pcm[2 * i];
    float x_r = pcm[2 * i + 1];
    x_l = (f_abs(x_l) <= kMaxFinite) ? x_l : 0.0f;   // fcmge + bsl
    x_r = (f_abs(x_r) <= kMaxFinite) ? x_r : 0.0f;

    lp_l = __builtin_fmaf(x_l - lp_l, a_lp, lp_l);   // fmla
    lp_r = __builtin_fmaf(x_r - lp_r, a_lp, lp_r);
    hc_l = __builtin_fmaf(x_l - hc_l, a_hc, hc_l);
    hc_r = __builtin_fmaf(x_r - hc_r, a_hc, hc_r);

    const float high_l = x_l - hc_l, high_r = x_r - hc_r;
    const float mid_l  = hc_l - lp_l, mid_r = hc_r - lp_r;

    float y_l = mid_l * mid;                         // fmul
    y_l = __builtin_fmaf(lp_l, bass, y_l);           // fmla
    y_l = __builtin_fmaf(high_l, high, y_l);         // fmla
    y_l = y_l * fade;                                // fmul
    float y_r = mid_r * mid;
    y_r = __builtin_fmaf(lp_r, bass, y_r);
    y_r = __builtin_fmaf(high_r, high, y_r);
    y_r = y_r * fade;

    y_l = (f_abs(y_l) <= kMaxFinite) ? y_l : 0.0f;   // non-finite becomes 0
    y_r = (f_abs(y_r) <= kMaxFinite) ? y_r : 0.0f;
    if (y_l < -1.0f) y_l = -1.0f; else if (y_l > 1.0f) y_l = 1.0f;   // fmax/fmin
    if (y_r < -1.0f) y_r = -1.0f; else if (y_r > 1.0f) y_r = 1.0f;

    pcm[2 * i]     = y_l;
    pcm[2 * i + 1] = y_r;
  }

  st->current_bass_gain  = bass;
  st->current_mid_gain   = mid;
  st->current_high_gain  = high;
  st->current_fade_gain  = fade;
  st->low_pass_state[0]  = lp_l;  st->low_pass_state[1]  = lp_r;
  st->high_cut_state[0]  = hc_l;  st->high_cut_state[1]  = hc_r;
}

static float g_tone_a[512], g_tone_b[512];

static void test_tone(int32_t frames) {
  ToneState kern, ref;
  tone_init(&kern, 1.0f, 1.0f, 1.0f, 0.0f);
  tone_init(&ref,  1.0f, 1.0f, 1.0f, 0.0f);

  for (int32_t i = 0; i < frames * 2; ++i) {
    g_tone_a[i] = edge_input(i);
    g_tone_b[i] = g_tone_a[i];
  }

  nar_automix_tone_process_stereo_neon(g_tone_a, frames, &kern, 1.4f, 0.6f, 1.2f, 0.8f);
  tone_reference(g_tone_b, frames, &ref, 1.4f, 0.6f, 1.2f, 0.8f);

  uint32_t pcm_bad = 0;
  for (int32_t i = 0; i < frames * 2; ++i) {
    if (!bit_equal(g_tone_a[i], g_tone_b[i])) ++pcm_bad;
  }
  uint32_t state_bad = 0;
  if (!bit_equal(kern.current_bass_gain, ref.current_bass_gain)) ++state_bad;
  if (!bit_equal(kern.current_mid_gain,  ref.current_mid_gain))  ++state_bad;
  if (!bit_equal(kern.current_high_gain, ref.current_high_gain)) ++state_bad;
  if (!bit_equal(kern.current_fade_gain, ref.current_fade_gain)) ++state_bad;
  if (!bit_equal(kern.low_pass_state[0], ref.low_pass_state[0])) ++state_bad;
  if (!bit_equal(kern.low_pass_state[1], ref.low_pass_state[1])) ++state_bad;
  if (!bit_equal(kern.high_cut_state[0], ref.high_cut_state[0])) ++state_bad;
  if (!bit_equal(kern.high_cut_state[1], ref.high_cut_state[1])) ++state_bad;

  char name[64];
  int k = 0;
  const char* prefix = "tone stereo   (frames=";
  while (*prefix) name[k++] = *prefix++;
  char digits[12];
  int d = 0;
  int32_t v = frames < 0 ? -frames : frames;
  if (v == 0) digits[d++] = '0';
  while (v) { digits[d++] = (char)('0' + (v % 10)); v /= 10; }
  if (frames < 0) name[k++] = '-';
  while (d) name[k++] = digits[--d];
  name[k++] = ')';
  name[k] = '\0';
  report(name, pcm_bad, state_bad);
}

// The kernel guards `frames <= 0` so a negative count cannot spin ~4 billion
// iterations. Both PCM and state must come back untouched.
static void test_tone_guard(int32_t frames) {
  ToneState st;
  tone_init(&st, 1.0f, 1.0f, 1.0f, 0.0f);
  for (int32_t i = 0; i < 16; ++i) g_tone_a[i] = edge_input(i);
  float before[16];
  for (int32_t i = 0; i < 16; ++i) before[i] = g_tone_a[i];

  nar_automix_tone_process_stereo_neon(g_tone_a, frames, &st, 1.4f, 0.6f, 1.2f, 0.8f);

  uint32_t pcm_bad = 0;
  for (int32_t i = 0; i < 16; ++i) {
    if (!bit_equal(g_tone_a[i], before[i])) ++pcm_bad;
  }
  uint32_t state_bad = 0;
  if (!bit_equal(st.current_bass_gain, 1.0f)) ++state_bad;
  if (!bit_equal(st.current_mid_gain,  1.0f)) ++state_bad;
  if (!bit_equal(st.current_high_gain, 1.0f)) ++state_bad;
  if (!bit_equal(st.current_fade_gain, 0.0f)) ++state_bad;

  report(frames == 0 ? "tone guard     (frames=0)      "
                     : "tone guard     (frames<0)      ", pcm_bad, state_bad);
}

// ─── Entry point ────────────────────────────────────────────────────────────
void _start(void) {
  p_str("NEON differential test (AArch64, freestanding)\n");

  test_gain();
  test_biquad();
  test_window(256);
  test_window(1024);
  test_window(2048);
  test_tone(1);
  test_tone(2);
  test_tone(3);
  test_tone(64);
  test_tone(128);
  test_tone_guard(0);
  test_tone_guard(-5);

  if (g_failures) {
    p_str("FAILURES: ");
    p_u32(g_failures);
    p_ch('\n');
  } else {
    p_str("all kernels bit-exact against their references\n");
  }
  p_flush();
  sys_exit(g_failures ? 1 : 0);
}
