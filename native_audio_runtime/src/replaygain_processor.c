// ReplayGain Processor implementation — Phase 8.
// See replaygain_processor.h for the contract.
//
// Architecture: pipeline slot 1 (after dsp.gain, before dsp.peq).
// The effective linear gain is pre-computed on the control thread
// (including dB-to-linear conversion and optional clipping protection).
// The audio thread's hot path is a single atomic load + scalar multiply loop —
// no transcendentals, no branches per sample.

#include "replaygain_processor.h"

#include <math.h>
#include <stdatomic.h>
#include <string.h>

#include "audio_buffer.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "native_audio_runtime_internal.h"

// ── Module-private state ──────────────────────────────────────────────────────
//
// Both knobs use the IEEE 754 bit-pattern trick (same as gain_processor.c)
// so the atomic load/store is guaranteed lock-free on every ABI this
// codebase targets (arm64-v8a, x86_64 host).  A plain _Atomic float is
// legal C11 but may use a mutex on rare ABIs; the bit-pattern trick avoids
// that.

static _Atomic int32_t _gain_bits;  // effective linear gain (IEEE 754 bits)
static _Atomic int32_t _bypass;     // 1 = bypass, 0 = active

// Safe float ↔ int32 conversion via memcpy (avoids strict-aliasing UB).
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

// ── Clipping protection ───────────────────────────────────────────────────────
//
// Called ONLY from nar_replaygain_set_gain() on the control thread.
// May use powf() freely — not on the audio hot-path.

static float _compute_effective_gain(float gain_db, float peak_linear,
                                      int32_t use_clipping) {
    // 1. dB → linear.
    float g = powf(10.0f, gain_db / 20.0f);

    // 2. Clipping protection: cap gain so g × peak ≤ 1.0.
    //    This prevents any sample from exceeding 0 dBFS when peak is known.
    if (use_clipping && peak_linear > 0.0f && g * peak_linear > 1.0f) {
        g = 1.0f / peak_linear;
    }

    // 3. Safety clamp to ±24 dB — covers all real-world ReplayGain values.
    //    Rejects corrupt or out-of-range metadata gracefully.
    const float kMaxGain = 15.8489f;  // powf(10,  24/20) — pre-computed
    const float kMinGain =  0.0631f;  // powf(10, -24/20) — pre-computed
    if (g > kMaxGain) g = kMaxGain;
    if (g < kMinGain) g = kMinGain;

    return g;
}

// ── VTable callbacks ──────────────────────────────────────────────────────────

static int32_t _rg_init(void* self) {
    (void)self;  // All state lives in module-level atomics.
    atomic_store(&_gain_bits, _float_to_bits(1.0f));  // unity gain
    atomic_store(&_bypass, 1);  // start bypassed until set_gain() is called
    return NATIVE_RUNTIME_OK;
}

static int32_t _rg_process(void* self, NarAudioBuffer* buffer) {
    (void)self;

    // True zero-copy bypass: return immediately, no samples touched.
    if (atomic_load(&_bypass)) return NATIVE_RUNTIME_OK;

    const float g = _bits_to_float(atomic_load(&_gain_bits));

    // Unity gain optimisation: skip the loop entirely.
    if (g == 1.0f) return NATIVE_RUNTIME_OK;

    float* data = nar_audio_buffer_data(buffer);
    if (!data) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

    const int32_t frames   = nar_audio_buffer_frame_count(buffer);
    const int32_t channels = nar_audio_buffer_channel_count(buffer);
    const int32_t total    = frames * channels;

    // Hot loop — plain scalar multiply.
    // Same form as gain_processor.c so the compiler can auto-vectorize with NEON
    // on arm64 without any processor-specific intrinsics.
    for (int32_t i = 0; i < total; ++i) {
        data[i] *= g;
    }

    return NATIVE_RUNTIME_OK;
}

static void _rg_reset(void* self) {
    (void)self;
    // Stateless processor — no IIR history or envelope follower to clear.
}

static void _rg_dispose(void* self) {
    (void)self;
    // No dynamic memory owned by this processor.
}

static int32_t _rg_latency_frames(void* self) {
    (void)self;
    return 0;  // Sample-synchronous: zero algorithmic latency.
}

static const NarDspProcessorVTable kRgVTable = {
    .init           = _rg_init,
    .process        = _rg_process,
    .reset          = _rg_reset,
    .dispose        = _rg_dispose,
    .latency_frames = _rg_latency_frames,
};

// ── Registration ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_replaygain_processor_register_internal(void) {
    // `self` is NULL — all state lives in module-level atomics.
    // The vtable is static const — it outlives the pipeline.
    const NarDspProcessorDescriptor desc = {
        .id     = "dsp.replaygain",
        .self   = NULL,
        .vtable = &kRgVTable,
    };
    return nar_dsp_pipeline_register_internal(&desc);
}

// ── Public knobs ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_replaygain_set_gain(float gain_db,
                                                    float peak_linear,
                                                    int32_t use_clipping_protection) {
    const float g = _compute_effective_gain(gain_db, peak_linear,
                                            use_clipping_protection);
    atomic_store(&_gain_bits, _float_to_bits(g));
    return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT void nar_replaygain_set_bypass(int32_t bypass) {
    atomic_store(&_bypass, bypass ? 1 : 0);
}

FFI_PLUGIN_EXPORT int32_t nar_replaygain_get_bypass(void) {
    return atomic_load(&_bypass);
}
