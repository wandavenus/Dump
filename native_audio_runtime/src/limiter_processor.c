// Limiter Processor implementation — Phase 6.
// See limiter_processor.h for the full contract and algorithm documentation.

#include "limiter_processor.h"

#include <stdatomic.h>
#include <math.h>
#include <string.h>

#include "audio_buffer.h"
#include "dynamics_common.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "dsp_stream.h"
#include "native_audio_runtime.h"
#include "native_audio_runtime_internal.h"

#if defined(__ANDROID__)
#include <android/log.h>
#define LIM_TAG "NarLimiterProcessor"
#define LIM_LOG(...) __android_log_print(ANDROID_LOG_DEBUG, LIM_TAG, __VA_ARGS__)
#else
#define LIM_LOG(...) ((void)0)
#endif

// ── Parameters struct (double-buffered) ───────────────────────────────────────
//
// Active params store PRE-COMPUTED values so the audio thread's dirty-flag
// swap requires no log/exp calls. The control thread (nar_limiter_set_params)
// computes threshold_linear and coeff_release before the release-store.

typedef struct {
  float threshold_linear;  // = 10^(threshold_db / 20)
  float release_ms;        // stored alongside coeff_release so a per-stream
                            // sample-rate change can re-derive it without
                            // control-thread involvement (see
                            // _lim_ensure_sample_rate below).
  float coeff_release;     // per-sample: exp(-1 / (release_ms * 0.001 * sr))
} NarLimiterParams;

// ── Module singleton ──────────────────────────────────────────────────────────
//
// SHARED control-plane: `pending`/`active` hold the user-configured ceiling
// and release time — one set of knobs for the whole app, applied uniformly
// to every stream.
//
// PER-STREAM runtime state (production-hardening pass): `dirty`,
// `gain_linear`, `delay_write_pos`, and `delay_buf` are now per-stream. The
// look-ahead delay buffer in particular holds actual recent PCM samples
// from a specific stream — sharing it between two concurrently-playing
// streams during crossfade would literally splice one track's audio into
// the other's output. `dirty` is per-stream for the same reason as the
// compressor (see comp_processor.c's NarCompState comment).

typedef struct {
  NarLimiterParams pending;                          // control-thread staging area (shared)
  NarLimiterParams active[NAR_DSP_MAX_STREAMS];       // audio-thread working copy, per stream
  _Atomic int32_t  dirty[NAR_DSP_MAX_STREAMS];
  _Atomic int32_t  bypass;                            // shared

  // Audio-thread-only state (no atomics needed) — per stream:
  float    gain_linear[NAR_DSP_MAX_STREAMS];          // smoothed gain [0, 1.0]; init 1.0
  int32_t  delay_write_pos[NAR_DSP_MAX_STREAMS];      // circular buffer write head [0, 63]
  // Per-channel look-ahead delay buffers, per stream.
  // Layout: delay_buf[stream][channel][position].
  float    delay_buf[NAR_DSP_MAX_STREAMS][NAR_LIMITER_MAX_CHANNELS][NAR_LIMITER_LOOKAHEAD_FRAMES];

  // Sample-rate correctness (production-hardening pass): mirrors
  // comp_processor.c's `last_sample_rate` — see that file's comment for the
  // full rationale (a stream's actual SR can change without a matching
  // nar_limiter_set_params() call, which would otherwise leave
  // coeff_release silently stale).
  int32_t  last_sample_rate[NAR_DSP_MAX_STREAMS];  // 0 = not yet seen
} NarLimiterState;

static NarLimiterState _lim;

// Re-derives stream `s`'s coeff_release from its cached release_ms if the
// buffer's actual sample rate no longer matches what it was computed for.
static void _lim_ensure_sample_rate(NarLimiterState* lim, int32_t s, int32_t sample_rate) {
  if (sample_rate <= 0) sample_rate = 48000;
  if (lim->last_sample_rate[s] == sample_rate) return;  // fast path
  lim->active[s].coeff_release = nar_time_coeff(lim->active[s].release_ms, (float)sample_rate);
  lim->last_sample_rate[s] = sample_rate;
}

// ── VTable implementations ────────────────────────────────────────────────────

static int32_t _lim_init(void* self) {
  (void)self;
  // Default: −1 dBFS ceiling, 50 ms release, 48000 Hz sample rate.
  const NarLimiterParams kDefault = {
      .threshold_linear = nar_db_to_linear(-1.0f),  // ≈ 0.8913
      .release_ms       = 50.0f,
      .coeff_release    = nar_time_coeff(50.0f, 48000.0f),
  };
  _lim.pending = kDefault;
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    _lim.active[s]          = kDefault;
    atomic_store(&_lim.dirty[s], 0);
    _lim.gain_linear[s]     = 1.0f;
    _lim.delay_write_pos[s] = 0;
    memset(_lim.delay_buf[s], 0, sizeof(_lim.delay_buf[s]));
    _lim.last_sample_rate[s] = 0;
  }
  atomic_store(&_lim.bypass, 0);
  LIM_LOG("_lim_init: ok (threshold=%.4f, lookahead=%d frames)",
          kDefault.threshold_linear, NAR_LIMITER_LOOKAHEAD_FRAMES);
  return NATIVE_RUNTIME_OK;
}

static int32_t _lim_process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
  (void)self;
  const int32_t s = nar_dsp_clamp_stream(stream_slot);

  // ── Global bypass ──────────────────────────────────────────────────────────
  if (atomic_load_explicit(&_lim.bypass, memory_order_relaxed)) {
    return NATIVE_RUNTIME_OK;
  }

  // ── Swap pending params if updated (per-stream dirty flag) ────────────────
  if (atomic_load_explicit(&_lim.dirty[s], memory_order_acquire)) {
    _lim.active[s] = _lim.pending;
    // Freshly-swapped coefficients came from Dart at a known SR — treat as
    // authoritative for this stream until proven otherwise on a later buffer.
    _lim.last_sample_rate[s] = 0;
    atomic_store_explicit(&_lim.dirty[s], 0, memory_order_relaxed);
  }

  float* data = nar_audio_buffer_data(buffer);
  if (data == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

  const int32_t frames   = nar_audio_buffer_frame_count(buffer);
  const int32_t channels = nar_audio_buffer_channel_count(buffer);
  if (frames <= 0 || channels <= 0) return NATIVE_RUNTIME_OK;

  // Buffer-driven sample-rate auto-detect — see NarLimiterState comment.
  _lim_ensure_sample_rate(&_lim, s, nar_audio_buffer_sample_rate(buffer));

  const float threshold_linear = _lim.active[s].threshold_linear;
  const float coeff_release    = _lim.active[s].coeff_release;

  // Number of channels we can delay-buffer (beyond this, apply gain only).
  const int32_t del_ch = channels < NAR_LIMITER_MAX_CHANNELS
                       ? channels : NAR_LIMITER_MAX_CHANNELS;

  // Look-ahead mask for the power-of-2 modulo: N & (64-1) = N % 64.
  const int32_t LA_MASK = NAR_LIMITER_LOOKAHEAD_FRAMES - 1;

  int32_t write_pos = _lim.delay_write_pos[s];
  float   gain      = _lim.gain_linear[s];

  // ── Per-sample loop ────────────────────────────────────────────────────────
  //
  // All arithmetic is in linear domain — no log/exp in this loop.
  // The only division occurs when a sample exceeds the threshold (rare).
  for (int32_t f = 0; f < frames; f++) {
    const int32_t base = f * channels;

    // 1. Sanitize non-finite input samples in place, then push into
    //    per-channel delay buffers — a NaN/Inf sample must never enter the
    //    look-ahead history (it would keep corrupting output for the next
    //    63 frames even after the source recovers).
    for (int32_t c = 0; c < del_ch; c++) {
      float x = data[base + c];
      if (!isfinite(x)) { x = 0.0f; data[base + c] = 0.0f; }
      _lim.delay_buf[s][c][write_pos] = x;
    }
    for (int32_t c = del_ch; c < channels; c++) {
      if (!isfinite(data[base + c])) data[base + c] = 0.0f;
    }

    // 2. Find peak absolute value across ALL channels (inter-channel linking).
    float peak = 0.0f;
    for (int32_t c = 0; c < channels; c++) {
      const float abs_s = fabsf(data[base + c]);
      if (abs_s > peak) peak = abs_s;
    }

    // 3. Compute desired gain: bring peak to exactly the threshold, or unity.
    const float desired_gain = (peak > threshold_linear && peak > 1e-9f)
                             ? threshold_linear / peak
                             : 1.0f;

    // 4. Gain state machine:
    //    - Attack: INSTANT (1 sample) — snap down to the required gain.
    //    - Release: smooth one-pole IIR recovery toward unity (1.0).
    //    The clamp after the release step prevents recovering past desired_gain,
    //    which handles the case where the signal is still above threshold.
    if (desired_gain <= gain) {
      gain = desired_gain;  // instant attack
    } else {
      gain = coeff_release * gain + (1.0f - coeff_release) * 1.0f;
      if (gain > desired_gain) gain = desired_gain;
    }
    if (!isfinite(gain)) gain = 1.0f;  // defensive fail-open

    // 5. Read the look-ahead delayed output.
    //    read_pos points to the sample written 63 frames ago (LOOKAHEAD_FRAMES − 1).
    const int32_t read_pos = (write_pos + 1) & LA_MASK;
    for (int32_t c = 0; c < del_ch; c++) {
      data[base + c] = _lim.delay_buf[s][c][read_pos] * gain;
    }
    // For extra channels beyond NAR_LIMITER_MAX_CHANNELS (never in practice):
    // apply same gain without delay (minor phase mismatch — acceptable).
    for (int32_t c = del_ch; c < channels; c++) {
      data[base + c] *= gain;
    }

    write_pos = (write_pos + 1) & LA_MASK;
  }

  _lim.delay_write_pos[s] = write_pos;
  _lim.gain_linear[s]     = gain;

  return NATIVE_RUNTIME_OK;
}

static void _lim_reset(void* self) {
  (void)self;
  // On seek/flush: clear the delay buffer and reset gain to unity, for
  // EVERY stream. The first NAR_LIMITER_LOOKAHEAD_FRAMES − 1 output samples
  // after a reset will be silence (delay buffer is zeros). At 48 kHz this
  // is ~1.3 ms — imperceptible and the correct behavior for a true
  // look-ahead buffer.
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    _lim.gain_linear[s]     = 1.0f;
    _lim.delay_write_pos[s] = 0;
    memset(_lim.delay_buf[s], 0, sizeof(_lim.delay_buf[s]));
  }
}

static void _lim_dispose(void* self) {
  (void)self;
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    _lim.gain_linear[s]     = 1.0f;
    _lim.delay_write_pos[s] = 0;
    memset(_lim.delay_buf[s], 0, sizeof(_lim.delay_buf[s]));
    _lim.last_sample_rate[s] = 0;
    atomic_store(&_lim.dirty[s], 0);
  }
  atomic_store(&_lim.bypass, 0);
}

static int32_t _lim_latency_frames(void* self) {
  (void)self;
  // The look-ahead introduces LOOKAHEAD_FRAMES − 1 frames of latency.
  // (The write and read heads are 63 positions apart in the 64-slot buffer.)
  return NAR_LIMITER_LOOKAHEAD_FRAMES - 1;
}

static const NarDspProcessorVTable kLimVTable = {
    .init           = _lim_init,
    .process        = _lim_process,
    .reset          = _lim_reset,
    .dispose        = _lim_dispose,
    .latency_frames = _lim_latency_frames,
};

// ── Registration ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_limiter_processor_register_internal(void) {
  const NarDspProcessorDescriptor desc = {
      .id     = "dsp.limiter",
      .self   = NULL,
      .vtable = &kLimVTable,
  };
  int32_t r = nar_dsp_pipeline_register_internal(&desc);
  if (r == NATIVE_RUNTIME_OK) {
    LIM_LOG("nar_limiter_processor_register_internal: ok (%d-frame look-ahead)",
            NAR_LIMITER_LOOKAHEAD_FRAMES);
  }
  return r;
}

// ── Parameter updates ─────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_limiter_set_params(
    float threshold_db,
    float release_ms,
    float sample_rate) {

  if (sample_rate   <= 0.0f)   sample_rate   = 48000.0f;
  if (threshold_db  >  -0.001f) threshold_db  = -0.001f;
  if (threshold_db  < -30.0f)  threshold_db  = -30.0f;
  if (release_ms    <   1.0f)  release_ms    =   1.0f;
  if (release_ms    > 1000.0f) release_ms    = 1000.0f;

  // Pre-compute on the control thread (no transcendentals on the audio thread).
  NarLimiterParams p;
  p.threshold_linear = nar_db_to_linear(threshold_db);
  p.release_ms       = release_ms;
  p.coeff_release    = nar_time_coeff(release_ms, sample_rate);

  _lim.pending = p;
  // Release-store dirty for EVERY stream — both concurrently-playing
  // streams must independently notice this update (see limiter_processor.c's
  // NarLimiterState comment / comp_processor.c's identical rationale).
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
    atomic_store_explicit(&_lim.dirty[s], 1, memory_order_release);
  }

  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT void nar_limiter_set_bypass(int32_t bypass) {
  atomic_store_explicit(&_lim.bypass, bypass ? 1 : 0, memory_order_relaxed);
}

FFI_PLUGIN_EXPORT int32_t nar_limiter_get_bypass(void) {
  return atomic_load_explicit(&_lim.bypass, memory_order_relaxed);
}

FFI_PLUGIN_EXPORT int32_t nar_limiter_lookahead_frames(void) {
  return NAR_LIMITER_LOOKAHEAD_FRAMES - 1;
}
