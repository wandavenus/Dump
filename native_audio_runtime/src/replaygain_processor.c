// ReplayGain Processor implementation — Phase 8.
// See replaygain_processor.h for the contract.
//
// Architecture: pipeline slot 1 (after dsp.gain).
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
#include "dsp_stream.h"              // NAR_DSP_MAX_STREAMS
#include "native_audio_runtime_internal.h"

#if defined(__aarch64__)
#include "neon_kernels.h"
#endif

// ── Module-private state ──────────────────────────────────────────────────────
//
// Both knobs use the IEEE 754 bit-pattern trick (same as gain_processor.c)
// so the atomic load/store is guaranteed lock-free on every ABI this
// codebase targets (arm64-v8a, x86_64 host).  A plain _Atomic float is
// legal C11 but may use a mutex on rare ABIs; the bit-pattern trick avoids
// that.
//
// FIX NAR-4: _gain_bits is now per-stream (array, indexed by stream_slot).
// During crossfade, two ExoPlayer instances play concurrently with potentially
// different ReplayGain metadata. Previously both streams shared a single gain
// knob, so whichever track Dart last called _applyReplayGain() for "won" for
// BOTH streams — the other stream silently used the wrong track's gain.
// With per-stream storage, _rg_process() reads _gain_bits[stream_slot]; Dart
// calls nar_replaygain_set_gain_for_stream() with the correct slot; each
// stream maintains its own independently-settable gain value.
// _bypass remains shared (it is a global "ReplayGain feature on/off" switch).

static _Atomic int32_t _gain_bits[NAR_DSP_MAX_STREAMS];  // per-stream linear gain bits
static _Atomic int32_t _bypass;                           // 1 = bypass, 0 = active (shared)

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
    // FIX NAR-4: initialize unity gain for all stream slots.
    for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
        atomic_store(&_gain_bits[s], _float_to_bits(1.0f));
    }
    atomic_store(&_bypass, 1);  // start bypassed until set_gain() is called
    return NATIVE_RUNTIME_OK;
}

// FIX NAR-4: each stream now reads from its own gain slot. Dart should call
// nar_replaygain_set_gain_for_stream(stream_slot, ...) to set the correct
// gain for each concurrently-playing stream during crossfade.
static int32_t _rg_process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
    (void)self;

    // True zero-copy bypass: return immediately, no samples touched.
    if (atomic_load(&_bypass)) return NATIVE_RUNTIME_OK;

    // Clamp stream_slot to valid range — should never be needed in practice
    // (pipeline enforces this), but prevents array OOB if ever called directly.
    if (stream_slot < 0 || stream_slot >= NAR_DSP_MAX_STREAMS) stream_slot = 0;

    float g = _bits_to_float(atomic_load(&_gain_bits[stream_slot]));
    if (!isfinite(g)) g = 1.0f;  // defensive fail-open

    // Unity gain optimisation: skip the loop entirely.
    if (g == 1.0f) return NATIVE_RUNTIME_OK;

    float* data = nar_audio_buffer_data(buffer);
    if (!data) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

    const int32_t frames   = nar_audio_buffer_frame_count(buffer);
    const int32_t channels = nar_audio_buffer_channel_count(buffer);
    const int32_t total    = frames * channels;

    // Hot loop — plain scalar multiply.
    //
    // AArch64: delegate to the same hand-written NEON kernel gain_processor.c
    // uses (neon_kernels.S) — this loop has the exact same shape ("multiply
    // every sample by one scalar gain, in place"), so the kernel is a
    // drop-in reuse, not new assembly. The NEON path skips the per-sample
    // isfinite() check for throughput; this is safe for the same reason
    // gain_processor.c's NEON path is: the soft_clipper at the end of the
    // pipeline sanitizes any non-finite sample before it reaches the output.
    //
    // All other targets: scalar loop with in-place NaN/Inf sanitization so a
    // single corrupt decoded sample cannot propagate to downstream processors.
#if defined(__aarch64__)
    nar_gain_apply_neon(data, total, g);
#else
    for (int32_t i = 0; i < total; ++i) {
        float x = data[i];
        if (!isfinite(x)) x = 0.0f;
        data[i] = x * g;
    }
#endif

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

// Sets gain for BOTH stream slots simultaneously (backward-compatible API).
// Existing callers that don't distinguish between streams continue to work;
// both streams get the same gain value. Use nar_replaygain_set_gain_for_stream()
// for per-stream control during crossfade.
FFI_PLUGIN_EXPORT int32_t nar_replaygain_set_gain(float gain_db,
                                                    float peak_linear,
                                                    int32_t use_clipping_protection) {
    const float g = _compute_effective_gain(gain_db, peak_linear,
                                            use_clipping_protection);
    // FIX NAR-4: store into all stream slots so neither stream reads stale
    // unity gain from a stream that was never individually updated.
    for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
        atomic_store(&_gain_bits[s], _float_to_bits(g));
    }
    return NATIVE_RUNTIME_OK;
}

// FIX NAR-4: per-stream variant — allows Dart to set different gains for
// the primary and standby crossfade streams independently.
FFI_PLUGIN_EXPORT int32_t nar_replaygain_set_gain_for_stream(int32_t stream_slot,
                                                               float gain_db,
                                                               float peak_linear,
                                                               int32_t use_clipping_protection) {
    if (stream_slot < 0 || stream_slot >= NAR_DSP_MAX_STREAMS) stream_slot = 0;
    const float g = _compute_effective_gain(gain_db, peak_linear,
                                            use_clipping_protection);
    atomic_store(&_gain_bits[stream_slot], _float_to_bits(g));
    return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT void nar_replaygain_set_bypass(int32_t bypass) {
    atomic_store(&_bypass, bypass ? 1 : 0);
}

FFI_PLUGIN_EXPORT int32_t nar_replaygain_get_bypass(void) {
    return atomic_load(&_bypass);
}
