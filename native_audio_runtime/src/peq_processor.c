// Parametric Equalizer Processor implementation — Phase 5.
// See peq_processor.h for the public contract and thread-safety notes.

#include "peq_processor.h"

#include <math.h>
#include <stdatomic.h>
#include <string.h>

#include "audio_buffer.h"
#include "biquad_filter.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "dsp_stream.h"
#include "native_audio_runtime.h"
#include "native_audio_runtime_internal.h"

#if defined(__ANDROID__)
#include <android/log.h>
#define PEQ_TAG "NarPeqProcessor"
#define PEQ_LOG(...) __android_log_print(ANDROID_LOG_DEBUG, PEQ_TAG, __VA_ARGS__)
#else
#define PEQ_LOG(...) ((void)0)
#endif

// ── Per-band state ────────────────────────────────────────────────────────────
//
// Each band has two coefficient sets:
//
//   pending — written exclusively by the CONTROL thread via nar_peq_set_band().
//   active  — read exclusively by the AUDIO thread during process().
//
// Synchronization: a C11 _Atomic dirty flag with release/acquire semantics.
//
//   Control thread writes:
//     1. Compute new coefficients into band.pending (plain struct assignment).
//     2. atomic_store(&band.dirty, 1, memory_order_release).
//        The release store ensures all writes to band.pending are visible to
//        any thread that subsequently observes dirty == 1 via an acquire load.
//
//   Audio thread reads (at top of process(), before the band loop):
//     1. if (atomic_load(&band.dirty, memory_order_acquire) == 1)
//     2.   band.active = band.pending;   // 20-byte copy after acquire barrier
//     3.   atomic_store(&band.dirty, 0, memory_order_relaxed);
//
// The filter history arrays (s1, s2) are touched exclusively by the audio
// thread — no atomics required.
//
// Production-hardening pass: `dirty` and the TDF-II history (`s1`/`s2`) are
// now per-stream (NAR_DSP_MAX_STREAMS slots). `s1`/`s2` hold actual
// filter-history samples from a specific stream's audio — sharing them
// between two concurrently-playing streams would corrupt each other's
// filtering. `pending`/`active`/`enabled` (the user-configured band
// coefficients) stay shared: one EQ curve applies uniformly to every
// stream. `dirty` must be per-stream for the same reason as comp/limiter
// (a shared flag would starve whichever stream's audio thread didn't
// happen to observe it first).

typedef struct {
  NarBiquadCoeffs pending;                     // control thread: staging area for next coefficients (shared)
  NarBiquadCoeffs active[NAR_DSP_MAX_STREAMS]; // audio thread: current working coefficients, per stream
  _Atomic int32_t dirty[NAR_DSP_MAX_STREAMS];  // 1 = pending has new data for that stream's audio thread
  _Atomic int32_t enabled;                     // 1 = process this band; 0 = skip (zero cost) (shared)
  // TDF-II state, one slot per channel per stream, audio-thread-only (no atomics needed).
  float s1[NAR_DSP_MAX_STREAMS][NAR_PEQ_MAX_CHANNELS];
  float s2[NAR_DSP_MAX_STREAMS][NAR_PEQ_MAX_CHANNELS];
} NarPeqBand;

// ── Module-level singleton ────────────────────────────────────────────────────

typedef struct {
  NarPeqBand      bands[NAR_PEQ_MAX_BANDS];
  _Atomic int32_t band_count;  // bands[0..band_count-1] have been configured
  _Atomic int32_t bypass;      // 1 = zero-copy global bypass
} NarPeqState;

// Zero-initialized at program load (C guarantees this for static storage).
// Zero → band_count=0, bypass=0, all bands disabled and dirty=0.
static NarPeqState _peq;

// ── Unity-gain coefficients (used to initialise unconfigured bands) ───────────
//
// b0=1, b1=0, b2=0, a1=0, a2=0 → y[n] = x[n] (pass-through / identity).
// This ensures that if a band is somehow enabled before nar_peq_set_band()
// is called, audio is not corrupted.
static const NarBiquadCoeffs kUnityCoeffs = {
    .b0 = 1.0f, .b1 = 0.0f, .b2 = 0.0f,
    .a1 = 0.0f, .a2 = 0.0f,
};

// ── VTable implementations ───────────────────────────────────────────────────

static int32_t _peq_init(void* self) {
  (void)self;
  // Initialise all bands to unity-gain pass-through, for every stream.
  for (int32_t b = 0; b < NAR_PEQ_MAX_BANDS; b++) {
    _peq.bands[b].pending = kUnityCoeffs;
    atomic_store(&_peq.bands[b].enabled, 0);
    for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
      _peq.bands[b].active[s] = kUnityCoeffs;
      atomic_store(&_peq.bands[b].dirty[s], 0);
      memset(_peq.bands[b].s1[s], 0, sizeof(_peq.bands[b].s1[s]));
      memset(_peq.bands[b].s2[s], 0, sizeof(_peq.bands[b].s2[s]));
    }
  }
  atomic_store(&_peq.band_count, 0);
  atomic_store(&_peq.bypass,     0);
  PEQ_LOG("_peq_init: ok (%d bands pre-allocated)", NAR_PEQ_MAX_BANDS);
  return NATIVE_RUNTIME_OK;
}

static int32_t _peq_process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
  (void)self;
  const int32_t s = nar_dsp_clamp_stream(stream_slot);

  // ── Global bypass ──────────────────────────────────────────────────────────
  // Zero-copy early return: buffer is untouched.
  if (atomic_load_explicit(&_peq.bypass, memory_order_relaxed)) {
    return NATIVE_RUNTIME_OK;
  }

  float* data = nar_audio_buffer_data(buffer);
  if (data == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

  const int32_t frames     = nar_audio_buffer_frame_count(buffer);
  const int32_t channels   = nar_audio_buffer_channel_count(buffer);
  const int32_t band_count = atomic_load_explicit(&_peq.band_count,
                                                   memory_order_relaxed);

  if (frames <= 0 || channels <= 0 || band_count <= 0) {
    return NATIVE_RUNTIME_OK;
  }

  // Clamp channel count to our maximum (supports up to 7.1).
  const int32_t proc_ch = channels < NAR_PEQ_MAX_CHANNELS
                        ? channels : NAR_PEQ_MAX_CHANNELS;

  // ── Coefficient swap (once per process() call, not per sample) ────────────
  //
  // For each band: if the control thread has written new coefficients for
  // THIS stream (dirty[s] == 1 via acquire), copy pending → active[s]. This
  // is the only per-buffer work for disabled bands; enabled bands then
  // iterate samples.
  for (int32_t b = 0; b < band_count; b++) {
    if (atomic_load_explicit(&_peq.bands[b].dirty[s], memory_order_acquire)) {
      _peq.bands[b].active[s] = _peq.bands[b].pending;
      atomic_store_explicit(&_peq.bands[b].dirty[s], 0, memory_order_relaxed);
    }
  }

  // ── Per-band processing ────────────────────────────────────────────────────
  //
  // Band-major order: we iterate all frames for band[0], then all frames for
  // band[1], etc. This keeps s1/s2 state for the current band warm in
  // registers and is more cache-friendly than sample-major order for small
  // band counts.
  for (int32_t b = 0; b < band_count; b++) {
    if (!atomic_load_explicit(&_peq.bands[b].enabled, memory_order_relaxed)) {
      continue;  // zero-cost skip for disabled bands
    }

    const NarBiquadCoeffs* c = &_peq.bands[b].active[s];
    float* s1 = _peq.bands[b].s1[s];
    float* s2 = _peq.bands[b].s2[s];

    // Inner loop: interleaved sample processing.
    // Frame f, channel c_idx → sample index = f * channels + c_idx.
    // Written in a form that Clang auto-vectorizes to NEON on arm64.
    for (int32_t f = 0; f < frames; f++) {
      for (int32_t c_idx = 0; c_idx < proc_ch; c_idx++) {
        const int32_t idx = f * channels + c_idx;
        float x = data[idx];
        if (!isfinite(x)) x = 0.0f;  // sanitize input before it enters filter history
        float y = nar_biquad_process_sample(c, &s1[c_idx], &s2[c_idx], x);
        if (!isfinite(y)) {
          // A non-finite output means the filter history itself has gone
          // unstable (extreme Q/gain combination) — clear it and pass the
          // sanitized input through rather than propagate NaN/Inf downstream.
          s1[c_idx] = 0.0f;
          s2[c_idx] = 0.0f;
          y = x;
        }
        data[idx] = y;
      }
    }
  }

  return NATIVE_RUNTIME_OK;
}

static void _peq_reset(void* self) {
  (void)self;
  // Clear all filter history, for EVERY stream. Called by the pipeline on
  // seek/flush. Runs on the audio thread — no locking needed for s1/s2
  // (audio-thread-only).
  const int32_t band_count = atomic_load_explicit(&_peq.band_count,
                                                   memory_order_relaxed);
  for (int32_t b = 0; b < band_count; b++) {
    for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
      memset(_peq.bands[b].s1[s], 0, sizeof(float) * NAR_PEQ_MAX_CHANNELS);
      memset(_peq.bands[b].s2[s], 0, sizeof(float) * NAR_PEQ_MAX_CHANNELS);
    }
  }
}

static void _peq_dispose(void* self) {
  (void)self;
  // All state is in the static _peq singleton — no heap to free.
  // Re-zero so a re-register after dispose starts clean.
  for (int32_t b = 0; b < NAR_PEQ_MAX_BANDS; b++) {
    _peq.bands[b].pending = kUnityCoeffs;
    atomic_store(&_peq.bands[b].enabled, 0);
    for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
      _peq.bands[b].active[s] = kUnityCoeffs;
      atomic_store(&_peq.bands[b].dirty[s], 0);
      memset(_peq.bands[b].s1[s], 0, sizeof(_peq.bands[b].s1[s]));
      memset(_peq.bands[b].s2[s], 0, sizeof(_peq.bands[b].s2[s]));
    }
  }
  atomic_store(&_peq.band_count, 0);
  atomic_store(&_peq.bypass,     0);
}

static int32_t _peq_latency_frames(void* self) {
  (void)self;
  // Biquad filters are sample-synchronous (no algorithmic delay).
  return 0;
}

static const NarDspProcessorVTable kPeqVTable = {
    .init           = _peq_init,
    .process        = _peq_process,
    .reset          = _peq_reset,
    .dispose        = _peq_dispose,
    .latency_frames = _peq_latency_frames,
};

// ── Registration ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_peq_processor_register_internal(void) {
  const NarDspProcessorDescriptor desc = {
      .id     = "dsp.peq",
      .self   = NULL,  // all state lives in the module-level _peq singleton
      .vtable = &kPeqVTable,
  };
  int32_t r = nar_dsp_pipeline_register_internal(&desc);
  if (r == NATIVE_RUNTIME_OK) {
    PEQ_LOG("nar_peq_processor_register_internal: ok (%d bands)", NAR_PEQ_MAX_BANDS);
  }
  return r;
}

// ── Band configuration ────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_peq_set_band(
    int32_t band_index,
    int32_t enabled,
    int32_t filter_type,
    float   freq_hz,
    float   q,
    float   gain_db,
    float   sample_rate) {

  if (band_index < 0 || band_index >= NAR_PEQ_MAX_BANDS) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT);
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }

  // Default sample rate if caller doesn't know it yet.
  if (sample_rate <= 0.0f) sample_rate = 48000.0f;

  // Compute coefficients on the control thread (sinf/cosf/powf — NOT on audio
  // thread). Only recomputed when the caller explicitly updates parameters.
  NarBiquadCoeffs new_coeffs;
  const int32_t r = nar_biquad_compute(
      (NarBiquadType)filter_type, freq_hz, q, gain_db, sample_rate, &new_coeffs);
  if (r != NATIVE_RUNTIME_OK) {
    nar_runtime_set_last_status(r);
    return r;
  }

  // Write pending coefficients, then release-store dirty for EVERY stream to
  // synchronize with each stream's acquire-load in _peq_process() — both
  // concurrently-playing streams must independently notice this update.
  _peq.bands[band_index].pending = new_coeffs;
  atomic_store_explicit(&_peq.bands[band_index].enabled, enabled ? 1 : 0,
                        memory_order_relaxed);
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    atomic_store_explicit(&_peq.bands[band_index].dirty[s], 1, memory_order_release);
  }

  // Grow band_count to cover this index (monotonically; bands are not removed).
  const int32_t required = band_index + 1;
  int32_t current = atomic_load(&_peq.band_count);
  while (current < required) {
    // CAS loop: only one thread wins the increment; racing writes just retry.
    if (atomic_compare_exchange_weak(&_peq.band_count, &current, required)) {
      break;
    }
  }

  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT int32_t nar_peq_set_band_enabled(
    int32_t band_index, int32_t enabled) {
  if (band_index < 0 || band_index >= NAR_PEQ_MAX_BANDS) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT);
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  atomic_store_explicit(&_peq.bands[band_index].enabled, enabled ? 1 : 0,
                        memory_order_relaxed);
  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT int32_t nar_peq_get_band_enabled(int32_t band_index) {
  if (band_index < 0 || band_index >= NAR_PEQ_MAX_BANDS) {
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  return atomic_load_explicit(&_peq.bands[band_index].enabled,
                              memory_order_relaxed);
}

// ── Global bypass ─────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT void nar_peq_set_bypass(int32_t bypass) {
  atomic_store_explicit(&_peq.bypass, bypass ? 1 : 0, memory_order_relaxed);
}

FFI_PLUGIN_EXPORT int32_t nar_peq_get_bypass(void) {
  return atomic_load_explicit(&_peq.bypass, memory_order_relaxed);
}

// ── Metadata ──────────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_peq_max_bands(void) {
  return NAR_PEQ_MAX_BANDS;
}

FFI_PLUGIN_EXPORT int32_t nar_peq_band_count(void) {
  return atomic_load(&_peq.band_count);
}
