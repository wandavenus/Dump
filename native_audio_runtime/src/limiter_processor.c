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
  float coeff_release;     // per-sample: exp(-1 / (release_ms * 0.001 * sr))
} NarLimiterParams;

// ── Module singleton ──────────────────────────────────────────────────────────

typedef struct {
  NarLimiterParams pending;
  NarLimiterParams active;
  _Atomic int32_t  dirty;
  _Atomic int32_t  bypass;

  // Audio-thread-only state (no atomics needed):
  float    gain_linear;          // current smoothed gain [0, 1.0]; init 1.0
  int32_t  delay_write_pos;      // circular buffer write head [0, 63]
  // Per-channel look-ahead delay buffers.
  // Layout: delay_buf[channel][position] — channel-major for per-channel access.
  float    delay_buf[NAR_LIMITER_MAX_CHANNELS][NAR_LIMITER_LOOKAHEAD_FRAMES];
} NarLimiterState;

static NarLimiterState _lim;

// ── VTable implementations ────────────────────────────────────────────────────

static int32_t _lim_init(void* self) {
  (void)self;
  // Default: −1 dBFS ceiling, 50 ms release, 48000 Hz sample rate.
  const NarLimiterParams kDefault = {
      .threshold_linear = nar_db_to_linear(-1.0f),  // ≈ 0.8913
      .coeff_release    = nar_time_coeff(50.0f, 48000.0f),
  };
  _lim.pending         = kDefault;
  _lim.active          = kDefault;
  atomic_store(&_lim.dirty,  0);
  atomic_store(&_lim.bypass, 0);
  _lim.gain_linear     = 1.0f;
  _lim.delay_write_pos = 0;
  memset(_lim.delay_buf, 0, sizeof(_lim.delay_buf));
  LIM_LOG("_lim_init: ok (threshold=%.4f, lookahead=%d frames)",
          kDefault.threshold_linear, NAR_LIMITER_LOOKAHEAD_FRAMES);
  return NATIVE_RUNTIME_OK;
}

static int32_t _lim_process(void* self, NarAudioBuffer* buffer) {
  (void)self;

  // ── Global bypass ──────────────────────────────────────────────────────────
  if (atomic_load_explicit(&_lim.bypass, memory_order_relaxed)) {
    return NATIVE_RUNTIME_OK;
  }

  // ── Swap pending params if updated ────────────────────────────────────────
  if (atomic_load_explicit(&_lim.dirty, memory_order_acquire)) {
    _lim.active = _lim.pending;
    atomic_store_explicit(&_lim.dirty, 0, memory_order_relaxed);
  }

  float* data = nar_audio_buffer_data(buffer);
  if (data == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

  const int32_t frames   = nar_audio_buffer_frame_count(buffer);
  const int32_t channels = nar_audio_buffer_channel_count(buffer);
  if (frames <= 0 || channels <= 0) return NATIVE_RUNTIME_OK;

  const float threshold_linear = _lim.active.threshold_linear;
  const float coeff_release    = _lim.active.coeff_release;

  // Number of channels we can delay-buffer (beyond this, apply gain only).
  const int32_t del_ch = channels < NAR_LIMITER_MAX_CHANNELS
                       ? channels : NAR_LIMITER_MAX_CHANNELS;

  // Look-ahead mask for the power-of-2 modulo: N & (64-1) = N % 64.
  const int32_t LA_MASK = NAR_LIMITER_LOOKAHEAD_FRAMES - 1;

  int32_t write_pos = _lim.delay_write_pos;
  float   gain      = _lim.gain_linear;

  // ── Per-sample loop ────────────────────────────────────────────────────────
  //
  // All arithmetic is in linear domain — no log/exp in this loop.
  // The only division occurs when a sample exceeds the threshold (rare).
  for (int32_t f = 0; f < frames; f++) {
    const int32_t base = f * channels;

    // 1. Push current samples into per-channel delay buffers.
    for (int32_t c = 0; c < del_ch; c++) {
      _lim.delay_buf[c][write_pos] = data[base + c];
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

    // 5. Read the look-ahead delayed output.
    //    read_pos points to the sample written 63 frames ago (LOOKAHEAD_FRAMES − 1).
    const int32_t read_pos = (write_pos + 1) & LA_MASK;
    for (int32_t c = 0; c < del_ch; c++) {
      data[base + c] = _lim.delay_buf[c][read_pos] * gain;
    }
    // For extra channels beyond NAR_LIMITER_MAX_CHANNELS (never in practice):
    // apply same gain without delay (minor phase mismatch — acceptable).
    for (int32_t c = del_ch; c < channels; c++) {
      data[base + c] *= gain;
    }

    write_pos = (write_pos + 1) & LA_MASK;
  }

  _lim.delay_write_pos = write_pos;
  _lim.gain_linear     = gain;

  return NATIVE_RUNTIME_OK;
}

static void _lim_reset(void* self) {
  (void)self;
  // On seek/flush: clear the delay buffer and reset gain to unity.
  // The first NAR_LIMITER_LOOKAHEAD_FRAMES − 1 output samples after a reset
  // will be silence (delay buffer is zeros). At 48 kHz this is ~1.3 ms —
  // imperceptible and the correct behavior for a true look-ahead buffer.
  _lim.gain_linear     = 1.0f;
  _lim.delay_write_pos = 0;
  memset(_lim.delay_buf, 0, sizeof(_lim.delay_buf));
}

static void _lim_dispose(void* self) {
  (void)self;
  _lim.gain_linear     = 1.0f;
  _lim.delay_write_pos = 0;
  memset(_lim.delay_buf, 0, sizeof(_lim.delay_buf));
  atomic_store(&_lim.bypass, 0);
  atomic_store(&_lim.dirty,  0);
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
  p.coeff_release    = nar_time_coeff(release_ms, sample_rate);

  _lim.pending = p;
  atomic_store_explicit(&_lim.dirty, 1, memory_order_release);

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
