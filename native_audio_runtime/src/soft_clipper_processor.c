// Soft Clipper Processor implementation — Phase 6.
// See soft_clipper_processor.h for the full contract and algorithm documentation.

#include "soft_clipper_processor.h"

#include <stdatomic.h>
#include <math.h>

#include "audio_buffer.h"
#include "dynamics_common.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "native_audio_runtime.h"
#include "native_audio_runtime_internal.h"

#if defined(__ANDROID__)
#include <android/log.h>
#define SC_TAG "NarSoftClipProcessor"
#define SC_LOG(...) __android_log_print(ANDROID_LOG_DEBUG, SC_TAG, __VA_ARGS__)
#else
#define SC_LOG(...) ((void)0)
#endif

// ── Module-level state (atomic bit-pattern trick, same as gain_processor.c) ───
//
// Only two parameters: threshold_linear and bypass.
// Using the bit-pattern atomic trick avoids the heavier double-buffer protocol
// for this simple single-parameter processor.

static _Atomic int32_t _sc_threshold_bits;  // IEEE 754 bit pattern of threshold_linear
static _Atomic int32_t _sc_threshold_db_bits;  // kept for get_threshold_db() readback
static _Atomic int32_t _sc_bypass;

#define SC_THRESHOLD_DB_DEFAULT  (-0.5f)
#define SC_THRESHOLD_DB_MIN      (-12.0f)
#define SC_THRESHOLD_DB_MAX      (-0.001f)

// ── Inline soft-clip kernel ───────────────────────────────────────────────────
//
// Applied to a single float sample. Only called when |x| > threshold.
// Formula: y = (threshold + range · tanh(excess / range)) · sign(x)
// where range = 1.0 − threshold, excess = |x| − threshold.
//
// C¹ continuous at threshold (derivative = sech²(0) = 1.0 ✓).
// Output bounded by threshold + range = 1.0 (0 dBFS) ✓.
// tanhf is called only for exceeding samples — transparent for the rest ✓.

static inline float _soft_clip(float x, float threshold, float range) {
  const float sign  = x < 0.0f ? -1.0f : 1.0f;
  const float abs_x = x < 0.0f ? -x : x;
  const float excess = abs_x - threshold;
  // range * tanh(excess / range): asymptotes to ±range ≈ ±(1 - threshold)
  return sign * (threshold + range * tanhf(excess / range));
}

// ── VTable implementations ────────────────────────────────────────────────────

static int32_t _sc_init(void* self) {
  (void)self;
  const float threshold_linear = nar_db_to_linear(SC_THRESHOLD_DB_DEFAULT);
  atomic_store(&_sc_threshold_bits,    nar_float_to_bits(threshold_linear));
  atomic_store(&_sc_threshold_db_bits, nar_float_to_bits(SC_THRESHOLD_DB_DEFAULT));
  // Start bypassed. The native -0.5 dBFS threshold is only a parameter
  // default; it must not become an audible effect before Dart syncs settings.
  atomic_store(&_sc_bypass, 1);
  SC_LOG("_sc_init: threshold=%.4f linear (%.1f dBFS)", threshold_linear, SC_THRESHOLD_DB_DEFAULT);
  return NATIVE_RUNTIME_OK;
}

// Stateless waveshaper (no persistent history — each sample's output
// depends only on that sample and the shared threshold knob), so
// `stream_slot` is accepted (vtable contract) but unused. See
// dsp_stream.h.
static int32_t _sc_process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
  (void)self;
  (void)stream_slot;

  if (atomic_load_explicit(&_sc_bypass, memory_order_relaxed)) {
    return NATIVE_RUNTIME_OK;  // zero-copy bypass
  }

  float* data = nar_audio_buffer_data(buffer);
  if (data == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

  const int32_t frames   = nar_audio_buffer_frame_count(buffer);
  const int32_t channels = nar_audio_buffer_channel_count(buffer);
  if (frames <= 0 || channels <= 0) return NATIVE_RUNTIME_OK;

  // Load threshold once per buffer (atomic load outside the hot loop).
  const float threshold = nar_bits_to_float(
      atomic_load_explicit(&_sc_threshold_bits, memory_order_relaxed));
  const float range = 1.0f - threshold;  // distance to 0 dBFS ceiling

  const int32_t total = frames * channels;

  // ── Sample loop ────────────────────────────────────────────────────────────
  //
  // Branch prediction strongly favors the transparent path (|x| ≤ threshold)
  // on well-mastered music. tanhf is only called for exceeding samples.
  // The compiler auto-vectorizes the comparison and the linear copy path on
  // arm64; the tanhf branch breaks vectorization only for the rare clips.
  if (range > 1e-6f) {
    for (int32_t i = 0; i < total; i++) {
      float x = data[i];
      if (!isfinite(x)) {
        // Sanitize a non-finite INPUT sample in place — otherwise it would
        // multiply/propagate straight through as the final stage of the
        // chain (soft_clipper is the pipeline's safety net).
        data[i] = 0.0f;
        continue;
      }
      const float abs_x = x < 0.0f ? -x : x;
      if (abs_x > threshold) {
        data[i] = _soft_clip(x, threshold, range);
      }
      // else: transparent pass-through (no-op)
    }
  }

  return NATIVE_RUNTIME_OK;
}

static void _sc_reset(void* self) {
  (void)self;
  // Stateless (no history) — nothing to reset.
}

static void _sc_dispose(void* self) {
  (void)self;
  // Atomics will be re-initialized on next _sc_init() call.
}

static int32_t _sc_latency_frames(void* self) {
  (void)self;
  return 0;  // Sample-synchronous waveshaper: zero latency.
}

static const NarDspProcessorVTable kSoftClipperVTable = {
    .init           = _sc_init,
    .process        = _sc_process,
    .reset          = _sc_reset,
    .dispose        = _sc_dispose,
    .latency_frames = _sc_latency_frames,
};

// ── Registration ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_soft_clipper_processor_register_internal(void) {
  const NarDspProcessorDescriptor desc = {
      .id     = "dsp.soft_clipper",
      .self   = NULL,
      .vtable = &kSoftClipperVTable,
  };
  int32_t r = nar_dsp_pipeline_register_internal(&desc);
  if (r == NATIVE_RUNTIME_OK) {
    SC_LOG("nar_soft_clipper_processor_register_internal: ok");
  }
  return r;
}

// ── Parameter updates ─────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT void nar_soft_clipper_set_threshold_db(float threshold_db) {
  if (threshold_db > SC_THRESHOLD_DB_MAX) threshold_db = SC_THRESHOLD_DB_MAX;
  if (threshold_db < SC_THRESHOLD_DB_MIN) threshold_db = SC_THRESHOLD_DB_MIN;
  const float threshold_linear = nar_db_to_linear(threshold_db);
  atomic_store(&_sc_threshold_bits,    nar_float_to_bits(threshold_linear));
  atomic_store(&_sc_threshold_db_bits, nar_float_to_bits(threshold_db));
}

FFI_PLUGIN_EXPORT float nar_soft_clipper_get_threshold_db(void) {
  return nar_bits_to_float(atomic_load(&_sc_threshold_db_bits));
}

FFI_PLUGIN_EXPORT void nar_soft_clipper_set_bypass(int32_t bypass) {
  atomic_store_explicit(&_sc_bypass, bypass ? 1 : 0, memory_order_relaxed);
}

FFI_PLUGIN_EXPORT int32_t nar_soft_clipper_get_bypass(void) {
  return atomic_load_explicit(&_sc_bypass, memory_order_relaxed);
}
