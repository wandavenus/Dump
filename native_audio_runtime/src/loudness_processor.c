// Loudness Normalization Processor — Phase 8.5.
// See loudness_processor.h for the full contract and design rationale.
//
// EBU R128 / ITU-R BS.1770-4 K-weighting:
//   Stage 1 — pre-filter:  high shelf, f0=1681.97 Hz, G=+3.9998 dB, Q=0.7072
//   Stage 2 — RLB filter:  high pass,  f0=38.135  Hz,                Q=0.5003
//
// Coefficients are computed via nar_biquad_compute() (biquad_filter.h).
// The hot loop (per sample) calls nar_biquad_process_sample() which is
// inlined and auto-vectorizes with NEON on arm64.
//
// Gain smoothing: first-order IIR with tau = SMOOTHING_TAU_SEC (3 s).
// alpha = 1 − exp(−1 / (sample_rate × tau)), applied per FRAME.
// This produces roughly 63 % convergence in 3 s — intentionally slow to
// prevent audible pumping. Both attack and release share the same constant.

#include "loudness_processor.h"

#include <math.h>
#include <stdatomic.h>
#include <string.h>

#include "audio_buffer.h"
#include "biquad_filter.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "native_audio_runtime_internal.h"

#if defined(__ANDROID__)
#include <android/log.h>
#define LN_TAG "NarLoudness"
#define LN_LOG(...) __android_log_print(ANDROID_LOG_DEBUG, LN_TAG, __VA_ARGS__)
#else
#define LN_LOG(...) ((void)0)
#endif

// ── Constants ─────────────────────────────────────────────────────────────────

// EBU R128 LUFS offset term:  LUFS = -0.691 + 10*log10(power_sum)
#define LUFS_OFFSET         (-0.691f)
// Loudness update interval (frames). At 48 kHz ≈ 85 ms.
#define UPDATE_FRAMES       4096
// Tiny power floor to prevent log10(0)
#define POWER_FLOOR         1e-7f
// Default target loudness (EBU R128 broadcast reference)
#define DEFAULT_TARGET_LUFS (-23.0f)
// Absolute gate (EBU R128): skip gain update on very quiet content
#define GATE_ABS_LUFS       (-70.0f)
// Maximum boost  (dB, linear ≈ +2×)
#define MAX_GAIN_DB          6.0f
// Maximum cut    (dB, linear ≈ 0.25×)
#define MIN_GAIN_DB        (-12.0f)
// Gain smoothing time constant (seconds). 3 s is intentionally slow.
#define SMOOTHING_TAU_SEC    3.0f
// Maximum supported channels
#define MAX_CHANNELS         8

// ── Float ↔ int32 bit-pattern trick (same as gain_processor.c) ───────────────

static inline float  _bits_to_float(int32_t b) { float  f; memcpy(&f, &b, 4); return f; }
static inline int32_t _float_to_bits(float f)   { int32_t b; memcpy(&b, &f, 4); return b; }

// ── Module-private state ──────────────────────────────────────────────────────

// K-weighting biquad coefficients (written by control thread via set_sample_rate,
// read by audio thread). Protected by a transient bypass during updates.
static NarBiquadCoeffs _kw1;   // Stage 1: pre-filter (high-shelf)
static NarBiquadCoeffs _kw2;   // Stage 2: RLB      (high-pass)

// Per-channel biquad state (audio thread only — never read by control thread).
static NarBiquadState _st1;    // Stage 1 delay state
static NarBiquadState _st2;    // Stage 2 delay state

// IIR power accumulator and frame counter (audio thread only).
static double   _power_acc;    // running K-weighted mean-square accumulator
static int32_t  _frame_count;  // frames accumulated since last LUFS update

// Smooth gain (linear). Audio thread only — no atomic needed.
static float _gain_smooth;

// Per-frame smoothing coefficient (precomputed from sample rate + tau).
static float _alpha;

// ── Atomics for cross-thread communication ────────────────────────────────────

static _Atomic int32_t _target_lufs_bits;      // control → audio
static _Atomic int32_t _measured_lufs_bits;    // audio → control (UI display)
static _Atomic int32_t _applied_gain_db_bits;  // audio → control (UI display)
static _Atomic int32_t _gain_target_bits;      // audio thread: last computed target
static _Atomic int32_t _bypass;                // control → audio (1=bypass)
static _Atomic int32_t _enabled;               // control: is user-enabled?

// ── K-weighting coefficient computation ──────────────────────────────────────

static void _compute_kw_coeffs(float sr) {
    // Stage 1: pre-filter — high-shelf at 1681.97 Hz, +3.9998 dB, Q=0.7072
    nar_biquad_compute(NAR_BIQUAD_HIGH_SHELF, 1681.97f, 0.7072f,  3.9998f, sr, &_kw1);
    // Stage 2: RLB filter — high-pass at 38.135 Hz, Q=0.5003
    nar_biquad_compute(NAR_BIQUAD_HIGH_PASS,   38.135f, 0.5003f,  0.0f,   sr, &_kw2);
    // Smoothing coefficient: 1 frame step along a 3 s RC time constant
    _alpha = 1.0f - expf(-1.0f / (sr * SMOOTHING_TAU_SEC));
    LN_LOG("coeffs updated: sr=%.0f alpha=%.2e", (double)sr, (double)_alpha);
}

// ── Internal reset (no atomic changes — caller owns bypass state) ─────────────

static void _reset_internal(void) {
    memset(&_st1, 0, sizeof _st1);
    memset(&_st2, 0, sizeof _st2);
    _power_acc   = 0.0;
    _frame_count = 0;
    _gain_smooth = 1.0f;
    atomic_store(&_gain_target_bits,      _float_to_bits(1.0f));
    atomic_store(&_measured_lufs_bits,    _float_to_bits(-99.0f));
    atomic_store(&_applied_gain_db_bits,  _float_to_bits(0.0f));
}

// ── VTable callbacks ──────────────────────────────────────────────────────────

static int32_t _ln_init(void* self) {
    (void)self;
    _compute_kw_coeffs(48000.0f);
    _reset_internal();
    atomic_store(&_bypass,           1);  // start bypassed
    atomic_store(&_enabled,          0);
    atomic_store(&_target_lufs_bits, _float_to_bits(DEFAULT_TARGET_LUFS));
    LN_LOG("init ok");
    return NATIVE_RUNTIME_OK;
}

static int32_t _ln_process(void* self, NarAudioBuffer* buffer) {
    (void)self;

    // Zero-copy bypass: return immediately, audio unchanged.
    if (atomic_load(&_bypass)) return NATIVE_RUNTIME_OK;

    float*        data     = nar_audio_buffer_data(buffer);
    if (!data) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

    const int32_t frames   = nar_audio_buffer_frame_count(buffer);
    const int32_t channels = nar_audio_buffer_channel_count(buffer);
    if (channels < 1 || channels > MAX_CHANNELS)
        return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

    // Load current gain target (written by audio thread; atomic for consistency).
    float gain_target = _bits_to_float(atomic_load(&_gain_target_bits));
    const float target_lufs = _bits_to_float(atomic_load(&_target_lufs_bits));

    // ── Per-frame loop ────────────────────────────────────────────────────────
    for (int32_t f = 0; f < frames; ++f) {
        float* frame = data + (size_t)f * (size_t)channels;

        // 1. K-weighting + power accumulation (per channel).
        //    ITU-R BS.1770 sums channels with equal weight (for stereo L+R).
        double frame_power = 0.0;
        for (int32_t ch = 0; ch < channels; ++ch) {
            float x = frame[ch];
            x = nar_biquad_process_sample(&_kw1, &_st1.s1[ch], &_st1.s2[ch], x);
            x = nar_biquad_process_sample(&_kw2, &_st2.s1[ch], &_st2.s2[ch], x);
            frame_power += (double)x * x;
        }
        // Normalize by channel count → mean channel power.
        _power_acc += frame_power / (double)channels;
        _frame_count += 1;

        // 2. Periodic loudness estimate + gain target update.
        //    Transcendentals (log10f, powf) are here, NOT per sample.
        if (_frame_count >= UPDATE_FRAMES) {
            const float mean_sq = (float)(_power_acc / _frame_count);
            const float lufs    = LUFS_OFFSET + 10.0f * log10f(mean_sq + POWER_FLOOR);

            atomic_store(&_measured_lufs_bits, _float_to_bits(lufs));

            // Apply absolute gate: ignore very quiet / silent sections so
            // we don't chase noise and cause pumping artefacts.
            if (lufs > GATE_ABS_LUFS) {
                float gain_db = target_lufs - lufs;
                // Clamp: limit boost to MAX_GAIN_DB, limit cut to MIN_GAIN_DB.
                if (gain_db > MAX_GAIN_DB)  gain_db = MAX_GAIN_DB;
                if (gain_db < MIN_GAIN_DB)  gain_db = MIN_GAIN_DB;
                gain_target = powf(10.0f, gain_db / 20.0f);
                atomic_store(&_gain_target_bits, _float_to_bits(gain_target));
            }
            // Also update displayed applied gain here (avoids extra log10f per buffer).
            const float applied_db = 20.0f * log10f(_gain_smooth + 1e-10f);
            atomic_store(&_applied_gain_db_bits, _float_to_bits(applied_db));

            _power_acc   = 0.0;
            _frame_count = 0;
        }

        // 3. Smooth gain interpolation (per frame — gradual, no clicks).
        //    _alpha ≈ 6.9e-6 at 48 kHz for tau=3 s → ~63 % reach in 3 s.
        _gain_smooth += _alpha * (gain_target - _gain_smooth);

        // 4. Apply smooth gain to all channels.
        for (int32_t ch = 0; ch < channels; ++ch) {
            frame[ch] *= _gain_smooth;
        }
    }  // end per-frame loop

    return NATIVE_RUNTIME_OK;
}

static void _ln_reset(void* self) {
    (void)self;
    // Transient bypass: ensures audio thread won't read stale filter state
    // while we clear it. The bypass lasts < 1 μs (just an atomic store).
    atomic_store(&_bypass, 1);
    _reset_internal();
    if (atomic_load(&_enabled)) atomic_store(&_bypass, 0);
}

static void _ln_dispose(void* self) { (void)self; /* no owned memory */ }

static int32_t _ln_latency_frames(void* self) {
    (void)self;
    return 0;  // Zero algorithmic latency — no look-ahead.
}

static const NarDspProcessorVTable kLnVTable = {
    .init           = _ln_init,
    .process        = _ln_process,
    .reset          = _ln_reset,
    .dispose        = _ln_dispose,
    .latency_frames = _ln_latency_frames,
};

// ── Registration ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_loudness_processor_register_internal(void) {
    const NarDspProcessorDescriptor desc = {
        .id     = "dsp.loudness",
        .self   = NULL,
        .vtable = &kLnVTable,
    };
    return nar_dsp_pipeline_register_internal(&desc);
}

// ── Public control-thread API ─────────────────────────────────────────────────

FFI_PLUGIN_EXPORT void nar_loudness_set_target_lufs(float target_lufs) {
    // Clamp to a safe range: [−36, −6] LUFS.
    if (target_lufs < -36.0f) target_lufs = -36.0f;
    if (target_lufs >  -6.0f) target_lufs =  -6.0f;
    atomic_store(&_target_lufs_bits, _float_to_bits(target_lufs));
}

FFI_PLUGIN_EXPORT void nar_loudness_set_bypass(int32_t bypass) {
    atomic_store(&_enabled, bypass ? 0 : 1);
    atomic_store(&_bypass,  bypass ? 1 : 0);
}

FFI_PLUGIN_EXPORT int32_t nar_loudness_get_bypass(void) {
    return atomic_load(&_bypass);
}

FFI_PLUGIN_EXPORT void nar_loudness_set_sample_rate(int32_t sample_rate) {
    if (sample_rate <= 0) return;
    // Transient bypass during coefficient update.
    atomic_store(&_bypass, 1);
    _compute_kw_coeffs((float)sample_rate);
    _reset_internal();
    if (atomic_load(&_enabled)) atomic_store(&_bypass, 0);
    LN_LOG("sample_rate=%d", sample_rate);
}

FFI_PLUGIN_EXPORT float nar_loudness_get_measured_lufs(void) {
    return _bits_to_float(atomic_load(&_measured_lufs_bits));
}

FFI_PLUGIN_EXPORT float nar_loudness_get_applied_gain_db(void) {
    return _bits_to_float(atomic_load(&_applied_gain_db_bits));
}

FFI_PLUGIN_EXPORT void nar_loudness_reset(void) {
    // Delegate to the vtable reset (which handles the transient bypass).
    _ln_reset(NULL);
}
