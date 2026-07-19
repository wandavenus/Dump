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
#include "dsp_stream.h"
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
  float attack_ms;       // stored alongside the derived coeff so a per-stream
  float release_ms;      // sample-rate change can re-derive coeff_attack/release
                          // without needing the control thread (see
                          // _comp_ensure_sample_rate below).
  float coeff_attack;    // per-sample: exp(-1 / (attack_ms  * 0.001 * sr))
  float coeff_release;   // per-sample: exp(-1 / (release_ms * 0.001 * sr))
} NarCompParams;

// ── Module singleton ──────────────────────────────────────────────────────────
//
// SHARED control-plane: `pending`/`active` are the user-configured
// threshold/ratio/knee/makeup values. There is only one set of user-facing
// compressor knobs in the app, and both concurrently-playing streams are
// meant to apply the SAME configured settings — so these stay shared.
//
// PER-STREAM runtime state (production-hardening pass): `dirty` and
// `envelope_db` are now arrays of NAR_DSP_MAX_STREAMS. `dirty` must be
// per-stream (not shared) because a shared flag would be consumed by
// whichever stream's audio thread observed it first, permanently starving
// the other stream of that parameter update. `envelope_db` is the
// audio-thread-only smoothed level follower — it MUST be isolated per
// stream, or two concurrently-playing tracks (main + crossfade-standby)
// would corrupt each other's gain-reduction history.

typedef struct {
  NarCompParams   pending;                          // control-thread staging area (shared)
  NarCompParams   active[NAR_DSP_MAX_STREAMS];       // audio-thread working copy, per stream
  _Atomic int32_t dirty[NAR_DSP_MAX_STREAMS];        // per-stream acquire/release dirty flag
  _Atomic int32_t bypass;                            // 1 = zero-copy pass-through (shared)

  // Audio-thread-only state (no atomics needed) — per stream:
  float envelope_db[NAR_DSP_MAX_STREAMS];  // smoothed peak level; init = NAR_SILENCE_DB

  // Sample-rate correctness (production-hardening pass): each stream caches
  // the sample rate its coeff_attack/coeff_release were last derived from.
  // nar_comp_set_params() bakes coefficients using whatever sample rate
  // Dart passes at that moment; if a stream's actual playback sample rate
  // later changes (e.g. a track change to a different-SR file) WITHOUT a
  // matching set_params() call, attack/release times would silently drift
  // from their configured millisecond values. Detecting the change directly
  // from each buffer's own sample_rate field (already passed into every
  // process() call) closes that gap with zero Dart/Kotlin involvement.
  int32_t last_sample_rate[NAR_DSP_MAX_STREAMS];  // 0 = not yet seen
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

// Re-derives stream `s`'s coeff_attack/coeff_release from its cached
// attack_ms/release_ms if the buffer's actual sample rate no longer matches
// what they were computed for. Cost is one nar_time_coeff() call (a single
// expf) per stream, only on the rare frame where sample rate changes — a
// simple int comparison on every other frame.
static void _comp_ensure_sample_rate(NarCompState* comp, int32_t s, int32_t sample_rate) {
  if (sample_rate <= 0) sample_rate = 48000;
  if (comp->last_sample_rate[s] == sample_rate) return;  // fast path
  comp->active[s].coeff_attack  = nar_time_coeff(comp->active[s].attack_ms,  (float)sample_rate);
  comp->active[s].coeff_release = nar_time_coeff(comp->active[s].release_ms, (float)sample_rate);
  comp->last_sample_rate[s] = sample_rate;
}

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
  // Hard-knee short-circuit: when knee_db is zero (or effectively zero),
  // the soft-knee formula reduces to 0/0 at the threshold boundary
  // (over == 0.0). Return the correct hard-knee result instead — this is
  // the mathematical limit of the soft-knee formula as knee_db → 0, so
  // it produces the right DSP behaviour with no continuity break.
  // (NEW-02 guard in dsp_pipeline.c covers the structural race; this guard
  // covers the arithmetic degenerate case here.)
  if (p->knee_db < 1e-6f) {
    return (over <= 0.0f) ? 0.0f : over * (1.0f - 1.0f / p->ratio);
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
      .attack_ms      =   0.1f,
      .release_ms     =   1.0f,
      .coeff_attack   =   0.0f,  // instant attack (0 ms) until first set_params
      .coeff_release  =   0.0f,
  };
  _comp.pending = kDefault;
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    _comp.active[s]          = kDefault;
    atomic_store(&_comp.dirty[s], 0);
    _comp.envelope_db[s]     = NAR_SILENCE_DB;
    _comp.last_sample_rate[s] = 0;
  }
  atomic_store(&_comp.bypass,   0);
  COMP_LOG("_comp_init: ok (threshold=%.1f dB, ratio=%.1f:1)", kDefault.threshold_db, kDefault.ratio);
  return NATIVE_RUNTIME_OK;
}

static int32_t _comp_process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
  (void)self;
  const int32_t s = nar_dsp_clamp_stream(stream_slot);

  // ── Global bypass ──────────────────────────────────────────────────────────
  if (atomic_load_explicit(&_comp.bypass, memory_order_relaxed)) {
    return NATIVE_RUNTIME_OK;
  }

  // ── Swap pending params if updated (per-stream dirty flag — see the
  //    NarCompState comment for why this must not be a single shared flag) ──
  if (atomic_load_explicit(&_comp.dirty[s], memory_order_acquire)) {
    _comp.active[s] = _comp.pending;
    // A fresh params swap already carries coefficients derived from the SR
    // Dart passed at that moment — treat it as authoritative for this
    // stream until proven otherwise on a later buffer.
    _comp.last_sample_rate[s] = 0;
    atomic_store_explicit(&_comp.dirty[s], 0, memory_order_relaxed);
  }

  float* data = nar_audio_buffer_data(buffer);
  if (data == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

  const int32_t frames   = nar_audio_buffer_frame_count(buffer);
  const int32_t channels = nar_audio_buffer_channel_count(buffer);
  if (frames <= 0 || channels <= 0) return NATIVE_RUNTIME_OK;

  // Buffer-driven sample-rate auto-detect — see NarCompState comment.
  _comp_ensure_sample_rate(&_comp, s, nar_audio_buffer_sample_rate(buffer));

  const NarCompParams* p = &_comp.active[s];
  float envelope_db = _comp.envelope_db[s];

  // ── Per-frame processing ───────────────────────────────────────────────────
  //
  // Processing is frame-major (one envelope/gain update per multi-channel
  // frame). This costs 1×logf + 1×expf per frame (not per sample) while
  // maintaining sample-accurate gain application. For a 1024-frame buffer
  // at 48 kHz the overhead is ~2 µs — negligible against a 21 ms deadline.
  for (int32_t f = 0; f < frames; f++) {
    const int32_t base = f * channels;

    // 1. Find peak absolute value across all channels at this frame.
    //    Non-finite input samples are sanitized in place so a single
    //    corrupt sample cannot poison the envelope follower or propagate
    //    to every downstream processor.
    float peak = 0.0f;
    for (int32_t c = 0; c < channels; c++) {
      float x = data[base + c];
      if (!isfinite(x)) {
        x = 0.0f;
        data[base + c] = 0.0f;
      }
      const float abs_s = fabsf(x);
      if (abs_s > peak) peak = abs_s;
    }

    // 2. Instantaneous level in dBFS.
    const float level_db = nar_linear_to_db(peak);

    // 3. Smooth envelope (attack when rising, release when falling).
    const float ca = (level_db > envelope_db) ? p->coeff_attack : p->coeff_release;
    envelope_db = ca * envelope_db + (1.0f - ca) * level_db;
    if (!isfinite(envelope_db)) envelope_db = NAR_SILENCE_DB;  // defensive fail-open

    // 4. Gain reduction from soft-knee gain computer.
    const float gc_db = _gain_reduction_db(envelope_db, p);

    // 5. Total gain = makeup − reduction. Convert to linear (one expf).
    float gain_linear = nar_db_to_linear(p->makeup_gain_db - gc_db);
    if (!isfinite(gain_linear)) gain_linear = 1.0f;  // defensive fail-open

    // 6. Scale all channels — stereo-linked (same gain on L+R preserves image).
    for (int32_t c = 0; c < channels; c++) {
      data[base + c] *= gain_linear;
    }
  }

  _comp.envelope_db[s] = envelope_db;

  return NATIVE_RUNTIME_OK;
}

static void _comp_reset(void* self) {
  (void)self;
  // Clear envelope state for ALL streams on seek/flush so the compressor
  // starts from silence. Runs on the audio thread — no atomics needed for
  // envelope_db (audio-thread-only).
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    _comp.envelope_db[s] = NAR_SILENCE_DB;
  }
}

static void _comp_dispose(void* self) {
  (void)self;
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    _comp.envelope_db[s] = NAR_SILENCE_DB;
    _comp.last_sample_rate[s] = 0;
    atomic_store(&_comp.dirty[s], 0);
  }
  atomic_store(&_comp.bypass, 0);
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
  p.attack_ms      = attack_ms;
  p.release_ms     = release_ms;
  p.coeff_attack   = nar_time_coeff(attack_ms,  sample_rate);
  p.coeff_release  = nar_time_coeff(release_ms, sample_rate);

  // Commit: write shared pending struct, then release-store dirty for
  // EVERY stream slot — both concurrently-playing streams must notice this
  // update independently (see the NarCompState comment for why a single
  // shared dirty flag would starve one of them).
  _comp.pending = p;
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    atomic_store_explicit(&_comp.dirty[s], 1, memory_order_release);
  }

  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT void nar_comp_set_bypass(int32_t bypass) {
  atomic_store_explicit(&_comp.bypass, bypass ? 1 : 0, memory_order_relaxed);
}

FFI_PLUGIN_EXPORT int32_t nar_comp_get_bypass(void) {
  return atomic_load_explicit(&_comp.bypass, memory_order_relaxed);
}
