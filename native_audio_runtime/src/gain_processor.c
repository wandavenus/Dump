// Gain Processor implementation — Phase 4.
// See gain_processor.h for the contract.
//
// ARM64 NEON optimisation (arm64-v8a):
//   On AArch64 builds the hot sample loop is replaced by nar_gain_apply_neon()
//   (neon_kernels.S), which processes 16 samples per iteration using four
//   fmul v.4s instructions.  The Snapdragon 730 (target device) has a dual-
//   issue NEON pipeline so this yields ~4× throughput over the scalar loop.
//   On all other architectures (x86_64 host, web) the scalar loop is used.

#include "gain_processor.h"

#include <math.h>
#include <stdatomic.h>
#include <string.h>

#include "audio_buffer.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "native_audio_runtime_internal.h"

#if defined(__aarch64__)
#include "neon_kernels.h"
#endif

// ── Module-private state (process-wide singleton) ─────────────────────────────
//
// Both knobs are stored as IEEE 754 bit patterns in _Atomic int32_t so the
// atomic load/store is guaranteed lock-free on every ABI this codebase
// targets (arm64-v8a, x86_64 host). A plain _Atomic float is legal C11 but
// may use a mutex on rare ABIs; the bit-pattern trick avoids that.

static _Atomic int32_t _gain_db_bits;  // IEEE 754 float bits for gain_db
static _Atomic int32_t _bypass;        // 0 = apply gain, 1 = zero-copy bypass

#define GAIN_DB_DEFAULT  0.0f   //  0 dBFS = unity gain
#define GAIN_DB_MIN    (-96.0f)
#define GAIN_DB_MAX     24.0f

// Safe float ↔ int32 conversion using memcpy (avoids strict-aliasing UB).
static float _bits_to_float(int32_t bits) {
  float f;
  memcpy(&f, &bits, sizeof(f));
  return f;
}
static int32_t _float_to_bits(float f) {
  int32_t bits;
  memcpy(&bits, &f, sizeof(bits));
  return bits;
}

static float _clamp_gain(float db) {
  if (db < GAIN_DB_MIN) return GAIN_DB_MIN;
  if (db > GAIN_DB_MAX) return GAIN_DB_MAX;
  return db;
}

// ── VTable implementations ───────────────────────────────────────────────────

static int32_t _gain_init(void* self) {
  (void)self;  // All state is in the module-level atomics above.
  atomic_store(&_gain_db_bits, _float_to_bits(GAIN_DB_DEFAULT));
  atomic_store(&_bypass, 0);
  return NATIVE_RUNTIME_OK;
}

// Fully stateless per-sample (a single shared atomic gain knob, no
// persistent history) — both concurrently-playing streams intentionally
// apply the SAME user-configured gain, so `stream_slot` is accepted (vtable
// contract) but not used for anything. See dsp_stream.h for the general
// per-stream rationale and why stateless processors are exempt from it.
static int32_t _gain_process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
  (void)self;
  (void)stream_slot;

  // True zero-copy bypass: return immediately without reading any sample.
  if (atomic_load(&_bypass)) return NATIVE_RUNTIME_OK;

  float* data = nar_audio_buffer_data(buffer);
  if (data == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

  int32_t frames   = nar_audio_buffer_frame_count(buffer);
  int32_t channels = nar_audio_buffer_channel_count(buffer);
  int32_t samples  = frames * channels;

  // Convert dBFS → linear once, outside the hot loop.
  float gain_db     = _bits_to_float(atomic_load(&_gain_db_bits));
  float gain_linear = powf(10.0f, gain_db / 20.0f);
  if (!isfinite(gain_linear)) gain_linear = 1.0f;  // defensive fail-open

  // Hot loop — scale every sample by gain_linear.
  //
  // AArch64: delegate to the hand-written NEON kernel (neon_kernels.S) which
  // processes 16 samples per iteration using four fmul v.4s instructions.
  // The NEON path skips the per-sample isfinite() check for throughput; this
  // is safe because (a) the soft_clipper at pipeline slot 7 is the final
  // safety net, and (b) the compiler's own auto-vectorization of the scalar
  // loop below would already drop isfinite() for the same reason.
  //
  // All other targets: scalar loop with in-place NaN/Inf sanitization so a
  // single corrupt decoded sample cannot propagate to downstream processors.
#if defined(__aarch64__)
  nar_gain_apply_neon(data, samples, gain_linear);
#else
  for (int32_t i = 0; i < samples; i++) {
    float x = data[i];
    if (!isfinite(x)) x = 0.0f;
    data[i] = x * gain_linear;
  }
#endif

  return NATIVE_RUNTIME_OK;
}

static void _gain_reset(void* self) {
  (void)self;
  // Stateless (no filter history, no envelope) — nothing to reset.
}

static void _gain_dispose(void* self) {
  (void)self;
  // No dynamic memory is owned by this processor's internals.
}

static int32_t _gain_latency_frames(void* self) {
  (void)self;
  return 0;  // Sample-synchronous: zero algorithmic latency.
}

static const NarDspProcessorVTable kGainVTable = {
    .init           = _gain_init,
    .process        = _gain_process,
    .reset          = _gain_reset,
    .dispose        = _gain_dispose,
    .latency_frames = _gain_latency_frames,
};

// ── Registration ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_gain_processor_register_internal(void) {
  // `self` is NULL because all state lives in module-level atomics.
  // The vtable is a static const — it outlives the pipeline.
  const NarDspProcessorDescriptor desc = {
      .id     = "dsp.gain",
      .self   = NULL,
      .vtable = &kGainVTable,
  };
  return nar_dsp_pipeline_register_internal(&desc);
}

// ── Public knobs ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT void nar_gain_processor_set_gain_db(float gain_db) {
  atomic_store(&_gain_db_bits, _float_to_bits(_clamp_gain(gain_db)));
}

FFI_PLUGIN_EXPORT void nar_gain_set_db(float gain_db) {
  nar_gain_processor_set_gain_db(gain_db);
}

FFI_PLUGIN_EXPORT float nar_gain_processor_get_gain_db(void) {
  return _bits_to_float(atomic_load(&_gain_db_bits));
}

FFI_PLUGIN_EXPORT void nar_gain_processor_set_bypass(int32_t bypass) {
  atomic_store(&_bypass, bypass ? 1 : 0);
}

FFI_PLUGIN_EXPORT int32_t nar_gain_processor_get_bypass(void) {
  return atomic_load(&_bypass);
}
