// Crossfeed Processor implementation — Phase 7.
// See crossfeed_processor.h for the full contract and algorithm documentation.

#include "crossfeed_processor.h"

#include <stdatomic.h>
#include <string.h>
#include <math.h>

#include "audio_buffer.h"
#include "biquad_filter.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "dsp_stream.h"
#include "native_audio_runtime.h"
#include "native_audio_runtime_internal.h"
#include "stereo_matrix.h"

#if defined(__aarch64__)
#include "neon_kernels.h"
#endif

#if defined(__ANDROID__)
#include <android/log.h>
#define XF_TAG "NarCrossfeedProcessor"
#define XF_LOG(...) __android_log_print(ANDROID_LOG_DEBUG, XF_TAG, __VA_ARGS__)
#else
#define XF_LOG(...) ((void)0)
#endif

// ── Single-channel biquad state ───────────────────────────────────────────────
//
// The crossfeed processor uses 4 independent mono biquad instances (lp_l,
// lp_r, hf_l, hf_r). Using a compact 2-float struct instead of the
// NAR_BIQUAD_MAX_CHANNELS-element NarBiquadState arrays saves 4 × (8-1) × 4 = 112
// bytes and keeps all 4 states contiguous in the NarCrossfeedState struct —
// cache-friendly for the audio thread.

typedef struct { float s1, s2; } NarCfBiquadState;

static inline float _cf_biquad(
    const NarBiquadCoeffs* c, NarCfBiquadState* s, float x) {
  const float y = c->b0 * x + s->s1;
  s->s1 = c->b1 * x - c->a1 * y + s->s2;
  s->s2 = c->b2 * x - c->a2 * y;
  return y;
}

// ── Parameters struct (double-buffered) ───────────────────────────────────────
//
// All biquad coefficients and the stereo-width matrix are pre-computed on the
// control thread (nar_crossfeed_set_params) so the audio thread's dirty-flag
// swap does zero transcendental math.

typedef struct {
  float           amount;  // crossfeed blend amount [0, 1]
  float           norm;    // = 1 / (1 + amount)  — equal-loudness normalizer
  NarBiquadCoeffs lp;      // lowpass coefficients for the cross-channel path
  NarBiquadCoeffs hf;      // high-shelf coefficients for HF compensation
  NarStereoMatrix width_m; // pre-computed stereo width matrix
} NarCrossfeedParams;

// ── Module singleton ──────────────────────────────────────────────────────────
//
// SHARED control-plane: `pending`/`active` hold the user-configured
// amount/cutoff/width knobs — one crossfeed curve for the whole app,
// applied uniformly to every stream.
//
// PER-STREAM runtime state (production-hardening pass): `dirty` and the 4
// biquad states (lp_l/lp_r/hf_l/hf_r) are now per-stream. The biquad states
// hold actual IIR filter history derived from a specific stream's audio —
// sharing them between two concurrently-playing streams would corrupt each
// other's filtering (audible artifacts during crossfade). `dirty` is
// per-stream for the same reason as comp/limiter/peq.

typedef struct {
  NarCrossfeedParams pending;                       // shared
  NarCrossfeedParams active[NAR_DSP_MAX_STREAMS];   // per stream
  _Atomic int32_t    dirty[NAR_DSP_MAX_STREAMS];
  _Atomic int32_t    bypass;                        // shared

  // Audio-thread-only biquad state (no atomics), per stream:
  NarCfBiquadState lp_l[NAR_DSP_MAX_STREAMS];  // LP state: R → L cross path
  NarCfBiquadState lp_r[NAR_DSP_MAX_STREAMS];  // LP state: L → R cross path
  NarCfBiquadState hf_l[NAR_DSP_MAX_STREAMS];  // HF shelf state: L direct path
  NarCfBiquadState hf_r[NAR_DSP_MAX_STREAMS];  // HF shelf state: R direct path
} NarCrossfeedState;

static NarCrossfeedState _xf;

// ── Default parameter values ──────────────────────────────────────────────────

#define XF_DEFAULT_AMOUNT      0.3f
#define XF_DEFAULT_CUTOFF_HZ   700.0f
#define XF_DEFAULT_HF_COMP_DB  3.0f
#define XF_DEFAULT_HF_COMP_HZ  4000.0f
#define XF_DEFAULT_WIDTH       1.0f
#define XF_DEFAULT_SAMPLE_RATE 48000.0f

// ── Helper: build a NarCrossfeedParams from user-facing values ────────────────
//
// All biquad coefficient computation (cosf, sinf, powf from biquad_filter.c)
// and the stereo-matrix computation happen here, on the control thread.
// The audio thread only copies a 92-byte struct.

static NarCrossfeedParams _build_params(
    float amount, float cutoff_hz, float hf_comp_db, float hf_comp_hz,
    float width, float sample_rate) {

  NarCrossfeedParams p;

  p.amount = amount;
  p.norm   = 1.0f / (1.0f + amount);  // equal-loudness normalization

  // Cross-path lowpass: Butterworth (Q = 1/√2 ≈ 0.7071, maximally flat).
  nar_biquad_compute(NAR_BIQUAD_LOW_PASS,
      cutoff_hz, 0.7071f, 0.0f, sample_rate, &p.lp);

  // HF compensation: high shelf applied to the direct (un-crossed) path.
  if (hf_comp_db > 0.0001f) {
    nar_biquad_compute(NAR_BIQUAD_HIGH_SHELF,
        hf_comp_hz, 0.7071f, hf_comp_db, sample_rate, &p.hf);
  } else {
    // Zero-dB shelf = identity biquad (b0=1, b1=b2=a1=a2=0).
    p.hf.b0 = 1.0f; p.hf.b1 = 0.0f; p.hf.b2 = 0.0f;
    p.hf.a1 = 0.0f; p.hf.a2 = 0.0f;
  }

  // Stereo width matrix (pre-compute the 4 coefficients).
  p.width_m = nar_stereo_matrix_width(width);

  return p;
}

// ── VTable implementations ────────────────────────────────────────────────────

static int32_t _xf_init(void* self) {
  (void)self;

  _xf.pending = _build_params(
      XF_DEFAULT_AMOUNT, XF_DEFAULT_CUTOFF_HZ,
      XF_DEFAULT_HF_COMP_DB, XF_DEFAULT_HF_COMP_HZ,
      XF_DEFAULT_WIDTH, XF_DEFAULT_SAMPLE_RATE);

  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    _xf.active[s] = _xf.pending;
    atomic_store(&_xf.dirty[s], 0);
    // Clear biquad state (zeroed = silence = correct initial state).
    memset(&_xf.lp_l[s], 0, sizeof(_xf.lp_l[s]));
    memset(&_xf.lp_r[s], 0, sizeof(_xf.lp_r[s]));
    memset(&_xf.hf_l[s], 0, sizeof(_xf.hf_l[s]));
    memset(&_xf.hf_r[s], 0, sizeof(_xf.hf_r[s]));
  }
  atomic_store(&_xf.bypass, 0);

  XF_LOG("_xf_init: ok (amount=%.2f, lp_cutoff=%.0f Hz, hf_comp=%.1f dB @ %.0f Hz, width=%.2f)",
         XF_DEFAULT_AMOUNT, XF_DEFAULT_CUTOFF_HZ,
         XF_DEFAULT_HF_COMP_DB, XF_DEFAULT_HF_COMP_HZ, XF_DEFAULT_WIDTH);

  return NATIVE_RUNTIME_OK;
}

static int32_t _xf_process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
  (void)self;
  const int32_t s = nar_dsp_clamp_stream(stream_slot);

  // ── Global bypass ──────────────────────────────────────────────────────────
  if (atomic_load_explicit(&_xf.bypass, memory_order_relaxed)) {
    return NATIVE_RUNTIME_OK;
  }

  // ── Swap pending params if updated (per-stream dirty flag) ────────────────
  if (atomic_load_explicit(&_xf.dirty[s], memory_order_acquire)) {
    _xf.active[s] = _xf.pending;
    // Note: biquad state is NOT reset on a parameter update — resetting would
    // produce a discontinuity (audible click). The IIR state from the old
    // coefficients is a graceful transient that decays within milliseconds.
    atomic_store_explicit(&_xf.dirty[s], 0, memory_order_relaxed);
  }

  float* data = nar_audio_buffer_data(buffer);
  if (data == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

  const int32_t frames   = nar_audio_buffer_frame_count(buffer);
  const int32_t channels = nar_audio_buffer_channel_count(buffer);

  if (frames <= 0 || channels <= 0) return NATIVE_RUNTIME_OK;

  // ── Mono / insufficient channels — pass through unchanged ─────────────────
  // Crossfeed requires at least 2 channels. For mono, the processor is a no-op
  // (mono signals don't have a stereo image to improve).
  if (channels < 2) return NATIVE_RUNTIME_OK;

  const NarCrossfeedParams* p = &_xf.active[s];

  // ── Per-frame stereo processing ───────────────────────────────────────────
  //
  // Processing is frame-major. For each stereo frame:
  //   1. Cross-path lowpass:   xfeed_L = LP(R),  xfeed_R = LP(L)
  //   2. HF compensation:      direct_L = HF_shelf(L),  direct_R = HF_shelf(R)
  //   3. Mix + normalize:      L_mixed = (direct_L + amount * xfeed_L) * norm
  //                            R_mixed = (direct_R + amount * xfeed_R) * norm
  //   4. Stereo width matrix:  [L_out, R_out] = width_matrix * [L_mixed, R_mixed]
  //
  // Channels beyond index 1 (surround etc.) are written back unchanged.
  // This costs 8 multiplies + 4 adds per frame from the biquads, plus the
  // mix and matrix — well within the 21 ms audio render deadline.

  const float  amount   = p->amount;
  const float  norm     = p->norm;

  for (int32_t f = 0; f < frames; f++) {
    const int32_t base = f * channels;
    float L_in = data[base + 0];
    float R_in = data[base + 1];
    // Sanitize non-finite input samples before they enter any biquad's
    // recursive state — an unsanitized NaN/Inf would poison the filter
    // history for every subsequent frame.
    if (!isfinite(L_in)) { L_in = 0.0f; data[base + 0] = 0.0f; }
    if (!isfinite(R_in)) { R_in = 0.0f; data[base + 1] = 0.0f; }

#if defined(__aarch64__)
    // 1+2. Cross-path lowpass and direct-path HF shelf via the 2-lane NEON
    // stereo biquad kernel (neon_kernels.S) — this is the documented
    // "intended call site" from neon_kernels.h's nar_biquad_stereo_neon
    // comment. Each call processes both channels' independent delay state
    // through ONE shared coefficient set in parallel, replacing two
    // sequential scalar _cf_biquad() calls with one NEON call.
    //
    // LP's inputs are intentionally cross-routed (R_in feeds the state that
    // becomes xfeed_L, L_in feeds the state that becomes xfeed_R) — the
    // kernel only cares that two independent state pairs share one
    // coefficient set; it has no notion of which physical channel is
    // "left"/"right", so cross-routing the inputs is safe and produces the
    // exact same math as the two separate scalar calls it replaces.
    float xfeed_L, xfeed_R;
    nar_biquad_stereo_neon((const float*)&p->lp, R_in, L_in,
                            &_xf.lp_l[s].s1, &_xf.lp_r[s].s1,
                            &_xf.lp_l[s].s2, &_xf.lp_r[s].s2,
                            &xfeed_L, &xfeed_R);

    float direct_L, direct_R;
    nar_biquad_stereo_neon((const float*)&p->hf, L_in, R_in,
                            &_xf.hf_l[s].s1, &_xf.hf_r[s].s1,
                            &_xf.hf_l[s].s2, &_xf.hf_r[s].s2,
                            &direct_L, &direct_R);
#else
    // 1. Cross-path lowpass filters.
    const float xfeed_L = _cf_biquad(&p->lp, &_xf.lp_l[s], R_in);  // filtered R → L
    const float xfeed_R = _cf_biquad(&p->lp, &_xf.lp_r[s], L_in);  // filtered L → R

    // 2. HF compensation on the direct path.
    const float direct_L = _cf_biquad(&p->hf, &_xf.hf_l[s], L_in);
    const float direct_R = _cf_biquad(&p->hf, &_xf.hf_r[s], R_in);
#endif

    // 3. Mix and normalize to equal loudness.
    float L_mixed = (direct_L + amount * xfeed_L) * norm;
    float R_mixed = (direct_R + amount * xfeed_R) * norm;

    // 4. Stereo width matrix.
    float L_out, R_out;
    nar_stereo_matrix_apply(&p->width_m, L_mixed, R_mixed, &L_out, &R_out);

    // Defensive: if any biquad's recursive state has gone unstable (e.g. an
    // extreme parameter combination), fail open on that frame rather than
    // emit NaN/Inf, and reset the offending states so the corruption cannot
    // persist into subsequent frames.
    if (!isfinite(L_out) || !isfinite(R_out)) {
      memset(&_xf.lp_l[s], 0, sizeof(_xf.lp_l[s]));
      memset(&_xf.lp_r[s], 0, sizeof(_xf.lp_r[s]));
      memset(&_xf.hf_l[s], 0, sizeof(_xf.hf_l[s]));
      memset(&_xf.hf_r[s], 0, sizeof(_xf.hf_r[s]));
      L_out = L_in;
      R_out = R_in;
    }

    data[base + 0] = L_out;
    data[base + 1] = R_out;
    // Channels 2+ pass through unchanged (loop not needed if channels==2).
  }

  return NATIVE_RUNTIME_OK;
}

static void _xf_reset(void* self) {
  (void)self;
  // On seek/flush: clear the biquad state for EVERY stream so transient
  // history from the previous track does not bleed into the next track.
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    memset(&_xf.lp_l[s], 0, sizeof(_xf.lp_l[s]));
    memset(&_xf.lp_r[s], 0, sizeof(_xf.lp_r[s]));
    memset(&_xf.hf_l[s], 0, sizeof(_xf.hf_l[s]));
    memset(&_xf.hf_r[s], 0, sizeof(_xf.hf_r[s]));
  }
}

static void _xf_dispose(void* self) {
  (void)self;
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    memset(&_xf.lp_l[s], 0, sizeof(_xf.lp_l[s]));
    memset(&_xf.lp_r[s], 0, sizeof(_xf.lp_r[s]));
    memset(&_xf.hf_l[s], 0, sizeof(_xf.hf_l[s]));
    memset(&_xf.hf_r[s], 0, sizeof(_xf.hf_r[s]));
    atomic_store(&_xf.dirty[s], 0);
  }
  atomic_store(&_xf.bypass, 0);
}

static int32_t _xf_latency_frames(void* self) {
  (void)self;
  return 0;  // IIR filters: zero algorithmic latency (causal, sample-synchronous).
}

static const NarDspProcessorVTable kCrossfeedVTable = {
    .init           = _xf_init,
    .process        = _xf_process,
    .reset          = _xf_reset,
    .dispose        = _xf_dispose,
    .latency_frames = _xf_latency_frames,
};

// ── Registration ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_crossfeed_processor_register_internal(void) {
  const NarDspProcessorDescriptor desc = {
      .id     = "dsp.crossfeed",
      .self   = NULL,
      .vtable = &kCrossfeedVTable,
  };
  int32_t r = nar_dsp_pipeline_register_internal(&desc);
  if (r == NATIVE_RUNTIME_OK) {
    XF_LOG("nar_crossfeed_processor_register_internal: ok");
  }
  return r;
}

// ── Parameter updates ─────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_crossfeed_set_params(
    float amount,
    float cutoff_hz,
    float hf_comp_db,
    float hf_comp_hz,
    float width,
    float sample_rate) {

  // Clamp all inputs.
  if (sample_rate  <= 0.0f)    sample_rate  = 48000.0f;
  if (amount       < 0.0f)     amount       = 0.0f;
  if (amount       > 1.0f)     amount       = 1.0f;
  if (cutoff_hz    < 100.0f)   cutoff_hz    = 100.0f;
  if (cutoff_hz    > 2000.0f)  cutoff_hz    = 2000.0f;
  if (hf_comp_db   < 0.0f)     hf_comp_db   = 0.0f;
  if (hf_comp_db   > 12.0f)    hf_comp_db   = 12.0f;
  if (hf_comp_hz   < 1000.0f)  hf_comp_hz   = 1000.0f;
  if (hf_comp_hz   > 16000.0f) hf_comp_hz   = 16000.0f;
  if (width        < 0.0f)     width        = 0.0f;
  if (width        > 2.0f)     width        = 2.0f;

  // Pre-compute all derived values on the control thread.
  _xf.pending = _build_params(
      amount, cutoff_hz, hf_comp_db, hf_comp_hz, width, sample_rate);

  // Commit with release-store, for EVERY stream, so each stream's audio
  // thread independently sees the full pending struct (see NarCrossfeedState
  // comment for why a single shared dirty flag would starve one stream).
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    atomic_store_explicit(&_xf.dirty[s], 1, memory_order_release);
  }

  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT void nar_crossfeed_set_bypass(int32_t bypass) {
  atomic_store_explicit(&_xf.bypass, bypass ? 1 : 0, memory_order_relaxed);
}

FFI_PLUGIN_EXPORT int32_t nar_crossfeed_get_bypass(void) {
  return atomic_load_explicit(&_xf.bypass, memory_order_relaxed);
}
