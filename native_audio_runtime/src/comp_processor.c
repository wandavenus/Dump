// Compressor Processor implementation — Phase 6.
// See comp_processor.h for the full contract and algorithm documentation.

#include "comp_processor.h"

#include <stdatomic.h>
#include <string.h>
#include <math.h>

#include "audio_buffer.h"
#include "dynamics_common.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "native_audio_runtime.h"
#include "native_audio_runtime_internal.h"

#if defined(__ANDROID__)
#include <android/log.h>
#define COMP_TAG "NarCompProcessor"
#define COMP_LOG(...) __android_log_print(ANDROID_LOG_DEBUG, COMP_TAG, __VA_ARGS__)
#else
#define COMP_LOG(...) ((void)0)
#endif

// ── Parameters struct (double-buffered for thread-safe updates) ───────────────
//
// All pre-computed values are stored here so the audio thread's dirty-flag
// swap (20-byte memcpy) requires no transcendental math.

typedef struct {
  float threshold_db;    // dBFS; default -20.0
  float ratio;           // N:1; default 4.0
  float knee_db;         // soft-knee half-width; default 6.0
  float makeup_gain_db;  // post-compression gain; default 0.0
  float coeff_attack;    // per-sample: exp(-1 / (attack_ms  * 0.001 * sr))
  float coeff_release;   // per-sample: exp(-1 / (release_ms * 0.001 * sr))
} NarCompParams;

// ── Module singleton ──────────────────────────────────────────────────────────

typedef struct {
  NarCompParams   pending;      // control-thread staging area
  NarCompParams   active;       // audio-thread working copy
  _Atomic int32_t dirty;        // acquire/release dirty flag (same as PEQ)
  _Atomic int32_t bypass;       // 1 = zero-copy pass-through

  // Audio-thread-only state (no atomics needed):
  float envelope_db;  // smoothed peak level; init = NAR_SILENCE_DB
} NarCompState;

static NarCompState _comp;

// ── Soft-knee gain computer ───────────────────────────────────────────────────
//
// Returns the gain REDUCTION in dB (positive = gain is reduced).
// Formula from the AES standard for soft-knee compression:
//
//   over = level - threshold
//   Knee region: |over| < knee_half
//
//   Below knee:  gc = 0
//   In knee:     gc = (over + knee_half)² / (2·knee_db) · (1 − 1/ratio)
//   Above knee:  gc = over · (1 − 1/ratio)
//
// At the knee boundaries, both pieces have equal value AND equal derivative,
// giving a C¹ (smooth) response. The quadratic interpolation ensures the
// compressor "breathes" into gain reduction rather than snapping.

static float _gain_reduction_db(float level_db,
                                  const NarCompParams* p) {
  const float over      = level_db - p->threshold_db;
  const float knee_half = p->knee_db * 0.5f;

  if (over < -knee_half) {
    return 0.0f;  // below knee — no reduction
  }
  if (over > knee_half) {
    // Above knee — full ratio compression
    return over * (1.0f - 1.0f / p->ratio);
  }
  // In the soft-knee region
  const float t = (over + knee_half) / p->knee_db;
  return t * t * p->knee_db * 0.5f * (1.0f - 1.0f / p->ratio);
}

// ── VTable implementations ───────────────────────────────────────────────────

static int32_t _comp_init(void* self) {
  (void)self;
  // Default parameters
  static const NarCompParams kDefault = {
      .threshold_db   = -20.0f,
      .ratio          =   4.0f,
      .knee_db        =   6.0f,
      .makeup_gain_db =   0.0f,
      .coeff_attack   =   0.0f,  // instant attack (0 ms) until first set_params
      .coeff_release  =   0.0f,
  };
  _comp.pending     = kDefault;
  _comp.active      = kDefault;
  atomic_store(&_comp.dirty,    0);
  atomic_store(&_comp.bypass,   0);
  _comp.envelope_db = NAR_SILENCE_DB;
  COMP_LOG("_comp_init: ok (threshold=%.1f dB, ratio=%.1f:1)", kDefault.threshold_db, kDefault.ratio);
  return NATIVE_RUNTIME_OK;
}

static int32_t _comp_process(void* self, NarAudioBuffer* buffer) {
  (void)self;

  // ── Global bypass ──────────────────────────────────────────────────────────
  if (atomic_load_explicit(&_comp.bypass, memory_order_relaxed)) {
    return NATIVE_RUNTIME_OK;
  }

  // ── Swap pending params if updated ────────────────────────────────────────
  if (atomic_load_explicit(&_comp.dirty, memory_order_acquire)) {
    _comp.active = _comp.pending;
    atomic_store_explicit(&_comp.dirty, 0, memory_order_relaxed);
  }

  float* data = nar_audio_buffer_data(buffer);
  if (data == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

  const int32_t frames   = nar_audio_buffer_frame_count(buffer);
  const int32_t channels = nar_audio_buffer_channel_count(buffer);
  if (frames <= 0 || channels <= 0) return NATIVE_RUNTIME_OK;

  const NarCompParams* p = &_comp.active;

  // ── Per-frame processing ───────────────────────────────────────────────────
  //
  // Processing is frame-major (one envelope/gain update per multi-channel
  // frame). This costs 1×logf + 1×expf per frame (not per sample) while
  // maintaining sample-accurate gain application. For a 1024-frame buffer
  // at 48 kHz the overhead is ~2 µs — negligible against a 21 ms deadline.
  for (int32_t f = 0; f < frames; f++) {
    const int32_t base = f * channels;

    // 1. Find peak absolute value across all channels at this frame.
    float peak = 0.0f;
    for (int32_t c = 0; c < channels; c++) {
      const float abs_s = fabsf(data[base + c]);
      if (abs_s > peak) peak = abs_s;
    }

    // 2. Instantaneous level in dBFS.
    const float level_db = nar_linear_to_db(peak);

    // 3. Smooth envelope (attack when rising, release when falling).
    const float ca = (level_db > _comp.envelope_db)
                   ? p->coeff_attack : p->coeff_release;
    _comp.envelope_db = ca * _comp.envelope_db + (1.0f - ca) * level_db;

    // 4. Gain reduction from soft-knee gain computer.
    const float gc_db = _gain_reduction_db(_comp.envelope_db, p);

    // 5. Total gain = makeup − reduction. Convert to linear (one expf).
    const float gain_linear = nar_db_to_linear(p->makeup_gain_db - gc_db);

    // 6. Scale all channels — stereo-linked (same gain on L+R preserves image).
    for (int32_t c = 0; c < channels; c++) {
      data[base + c] *= gain_linear;
    }
  }

  return NATIVE_RUNTIME_OK;
}

static void _comp_reset(void* self) {
  (void)self;
  // Clear envelope state on seek/flush so the compressor starts from silence.
  // Runs on the audio thread — no atomics needed for envelope_db.
  _comp.envelope_db = NAR_SILENCE_DB;
}

static void _comp_dispose(void* self) {
  (void)self;
  _comp.envelope_db = NAR_SILENCE_DB;
  atomic_store(&_comp.bypass, 0);
  atomic_store(&_comp.dirty,  0);
}

static int32_t _comp_latency_frames(void* self) {
  (void)self;
  return 0;  // Feed-forward compressor: zero algorithmic latency.
}

static const NarDspProcessorVTable kCompVTable = {
    .init           = _comp_init,
    .process        = _comp_process,
    .reset          = _comp_reset,
    .dispose        = _comp_dispose,
    .latency_frames = _comp_latency_frames,
};

// ── Registration ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_comp_processor_register_internal(void) {
  const NarDspProcessorDescriptor desc = {
      .id     = "dsp.compressor",
      .self   = NULL,
      .vtable = &kCompVTable,
  };
  int32_t r = nar_dsp_pipeline_register_internal(&desc);
  if (r == NATIVE_RUNTIME_OK) {
    COMP_LOG("nar_comp_processor_register_internal: ok");
  }
  return r;
}

// ── Parameter updates ─────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_comp_set_params(
    float threshold_db,
    float ratio,
    float attack_ms,
    float release_ms,
    float knee_db,
    float makeup_gain_db,
    float sample_rate) {

  // Clamp all inputs before computing coefficients.
  if (sample_rate <= 0.0f) sample_rate = 48000.0f;
  if (threshold_db <  -96.0f) threshold_db  = -96.0f;
  if (threshold_db >    0.0f) threshold_db  =   0.0f;
  if (ratio        <  1.001f) ratio         =  1.001f;
  if (ratio        > 100.0f)  ratio         = 100.0f;
  if (attack_ms    <  0.1f)   attack_ms     =  0.1f;
  if (attack_ms    > 500.0f)  attack_ms     = 500.0f;
  if (release_ms   <   1.0f)  release_ms    =   1.0f;
  if (release_ms   > 2000.0f) release_ms    = 2000.0f;
  if (knee_db      <   0.0f)  knee_db       =   0.0f;
  if (knee_db      >  24.0f)  knee_db       =  24.0f;
  if (makeup_gain_db < -24.0f) makeup_gain_db = -24.0f;
  if (makeup_gain_db >  24.0f) makeup_gain_db =  24.0f;

  // Pre-compute time coefficients on the control thread (never on audio thread).
  NarCompParams p;
  p.threshold_db   = threshold_db;
  p.ratio          = ratio;
  p.knee_db        = knee_db;
  p.makeup_gain_db = makeup_gain_db;
  p.coeff_attack   = nar_time_coeff(attack_ms,  sample_rate);
  p.coeff_release  = nar_time_coeff(release_ms, sample_rate);

  // Commit: write pending, release-store dirty.
  _comp.pending = p;
  atomic_store_explicit(&_comp.dirty, 1, memory_order_release);

  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT void nar_comp_set_bypass(int32_t bypass) {
  atomic_store_explicit(&_comp.bypass, bypass ? 1 : 0, memory_order_relaxed);
}

FFI_PLUGIN_EXPORT int32_t nar_comp_get_bypass(void) {
  return atomic_load_explicit(&_comp.bypass, memory_order_relaxed);
}
