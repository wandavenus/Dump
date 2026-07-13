// Loudness Normalization Processor — Phase 8.5 (hardened, ITU-R BS.1770-4).
// See loudness_processor.h for the full contract and design rationale.
//
// ── K-weighting coefficient derivation ──────────────────────────────────────
//
// Stage 1 (pre-filter, high-shelf-like) and Stage 2 (RLB weighting,
// high-pass) coefficients are computed directly from the closed-form
// formulas in ITU-R BS.1770-4 Annex 1 ("Description of algorithms"), which
// generalize the standard's reference 48 kHz coefficient table to any
// sample rate via a tan()-based bilinear pre-warp. This is the same
// derivation used by libebur128 and ffmpeg's `ebur128` filter, and is exact
// (not an approximation) — unlike a generic RBJ-cookbook shelf filter, whose
// slope parameterization does not reproduce the BS.1770 curve exactly.
//
// Stage 1:  f0 = 1681.9744509555319 Hz, G = 3.99984385397 dB,
//           Q = 0.7071752369554193
// Stage 2:  f0 = 38.13547087602444 Hz,  Q = 0.5003270373238773
//
// All coefficient math runs in double precision on the control thread only
// (sample-rate change / init), then rounds to the float32 NarBiquadCoeffs
// storage used by the per-sample hot loop.
//
// ── Channel weighting ────────────────────────────────────────────────────────
//
// BS.1770-4 defines a per-channel POWER-domain weight G_i applied to each
// channel's mean-square value before summing across channels:
//   front L/R/C        → G = 1.0       (0 dB)
//   surround/back L/R  → G = 1.41253754 (+1.5 dB in the power domain, i.e.
//                         10*log10(G) = 1.5 — not 20*log10(G), because G
//                         multiplies power, not amplitude)
//   LFE                → G = 0.0       (excluded from loudness entirely)
// See _channel_weights() for the assumed canonical channel order per count.
//
// ── Gating / block integration ────────────────────────────────────────────
//
// BS.1770-4 §5 defines loudness measurement over 400 ms blocks with 75%
// overlap (100 ms hop), gated in two stages: an absolute gate (−70 LUFS)
// and a relative gate (running absolute-gated mean − 10 LU). The spec's
// reference algorithm is OFFLINE (two full passes over the whole
// programme). This processor implements the standard CAUSAL approximation
// used by real-time loudness meters: a 4-slot 100 ms ring buffer forms each
// 400 ms gating block, and both gate thresholds are computed against
// cumulative running sums since the last reset (track change) rather than
// a full offline pass. This is O(1) memory/CPU and updates every 100 ms.
//
// ── Numerical stability ─────────────────────────────────────────────────────
//
// All power accumulators are double precision. A cheap isfinite() guard
// runs on the raw INPUT sample before it reaches the K-weighting filters or
// the output gain multiply, and again after each biquad stage — if a
// sample is NaN/Inf (e.g. from a corrupt decode), it is zeroed in place
// before either the measurement path or the output path sees it. This
// prevents a single bad sample from (a) permanently poisoning the
// K-weighting IIR state for the rest of the track, or (b) multiplying
// straight through to the output and poisoning every downstream processor
// (peq/compressor/limiter/etc.) — fail-open, consistent with the rest of
// this DSP runtime.

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

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ── Constants ─────────────────────────────────────────────────────────────────

// EBU R128 / BS.1770-4 LUFS offset term:  LUFS = -0.691 + 10*log10(power_sum)
#define LUFS_OFFSET          (-0.691)
// Gating hop / sub-block length (BS.1770-4: 100 ms, 75% overlap → 400 ms block).
#define SUB_BLOCK_SEC        0.1
// Number of 100 ms sub-blocks per 400 ms gating block (75% overlap).
#define SUB_BLOCKS_PER_BLOCK 4
// Tiny power floor to prevent log10(0).
#define POWER_FLOOR          1e-10
// Default target loudness (EBU R128 broadcast reference).
#define DEFAULT_TARGET_LUFS  (-23.0f)
// Absolute gate (EBU R128 / BS.1770-4 §5): blocks quieter than this are
// never counted toward the loudness estimate (silence / near-silence).
#define GATE_ABS_LUFS        (-70.0)
// Relative gate (EBU R128 / BS.1770-4 §5): blocks more than this many LU
// below the absolute-gated running mean are excluded from the final
// integrated estimate.
#define GATE_REL_LU          10.0
// Maximum boost (dB, linear ≈ +2×).
#define MAX_GAIN_DB          6.0f
// Maximum cut (dB, linear ≈ 0.25×).
#define MIN_GAIN_DB          (-12.0f)
// Release time constant (seconds) — gain INCREASE (quiet→loud transition).
// Intentionally slow to prevent audible pumping on fades and dynamic music.
#define RELEASE_TAU_SEC      3.0f
// Attack time constant (seconds) — gain REDUCTION (loud→quiet transition).
// Fast attack prevents momentary overloads before the smoother reacts.
// Standard practice: fast attack (~200-500 ms), slow release (2-5 s).
#define ATTACK_TAU_SEC       0.3f
// Maximum supported channels (matches BS.1770-4's largest defined layout, 7.1).
#define MAX_CHANNELS         8
// Power-domain surround/back-channel weight: 10*log10(G) = +1.5 dB → G = 10^0.15.
#define SURROUND_WEIGHT      1.4125375446227544f

// ── Float ↔ int32 bit-pattern trick (same as gain_processor.c) ───────────────

static inline float  _bits_to_float(int32_t b) { float  f; memcpy(&f, &b, 4); return f; }
static inline int32_t _float_to_bits(float f)   { int32_t b; memcpy(&b, &f, 4); return b; }

// ── Module-private state ──────────────────────────────────────────────────────

// K-weighting biquad coefficients (written by control thread via set_sample_rate,
// read by audio thread). Protected by a transient bypass during updates.
static NarBiquadCoeffs _kw1;   // Stage 1: pre-filter
static NarBiquadCoeffs _kw2;   // Stage 2: RLB high-pass

// Per-channel biquad state (audio thread only — never read by control thread).
static NarBiquadState _st1;    // Stage 1 delay state
static NarBiquadState _st2;    // Stage 2 delay state

// Cached per-channel BS.1770-4 power weights (audio thread only; recomputed
// only when the buffer's channel count changes — see _channel_weights()).
static float   _weights[MAX_CHANNELS];
static int32_t _weights_channels;  // 0 = not yet computed

// Sample-rate-derived sub-block length in frames (audio thread only).
static int32_t _sub_block_frames;

// 100 ms sub-block gating ring buffer (audio thread only).
static double  _sub_block_ring[SUB_BLOCKS_PER_BLOCK];  // mean-square per 100ms
static int32_t _ring_index;
static int32_t _ring_filled;      // number of valid ring slots, capped at 4

// Current in-progress 100 ms sub-block accumulator (audio thread only).
static double  _sub_acc;
static int32_t _sub_count;

// Cumulative gating accumulators since last reset (audio thread only).
// Stage A: absolute-gated running mean — establishes the relative threshold.
static double  _abs_sum_z;
static int64_t _abs_count;
// Stage B: absolute+relative-gated running mean — the final integrated LUFS.
static double  _rel_sum_z;
static int64_t _rel_count;

// Smooth gain (linear). Audio thread only — no atomic needed.
static float _gain_smooth;

// Per-frame smoothing coefficients (precomputed from sample rate).
// Asymmetric attack/release: fast for gain reduction, slow for gain increase.
static float _alpha_attack;   // fast — gain reduction  (~0.3 s)
static float _alpha_release;  // slow — gain increase   (~3.0 s)

// ── Atomics for cross-thread communication ────────────────────────────────────

static _Atomic int32_t _target_lufs_bits;      // control → audio
static _Atomic int32_t _measured_lufs_bits;    // audio → control (UI display)
static _Atomic int32_t _applied_gain_db_bits;  // audio → control (UI display)
static _Atomic int32_t _gain_target_bits;      // audio thread: last computed target
static _Atomic int32_t _bypass;                // control → audio (1=bypass)
static _Atomic int32_t _enabled;               // control: is user-enabled?

// ── K-weighting coefficient computation (literal BS.1770-4 Annex 1) ──────────

// Converts a double-precision biquad (a0-normalized) into the float32
// NarBiquadCoeffs storage used by the per-sample hot loop. `a1`/`a2` here
// follow the SAME positive-and-subtracted convention as biquad_filter.h's
// TDF-II recurrence: y = b0 x + b1 x1 + b2 x2 - a1 y1 - a2 y2.
static void _store_coeffs(double b0, double b1, double b2,
                           double a1, double a2, NarBiquadCoeffs* out) {
    out->b0 = (float)b0;
    out->b1 = (float)b1;
    out->b2 = (float)b2;
    out->a1 = (float)a1;
    out->a2 = (float)a2;
}

static void _compute_kw_coeffs(double sr) {
    if (sr <= 0.0) sr = 48000.0;

    // ── Stage 1: pre-filter ────────────────────────────────────────────────
    // Literal ITU-R BS.1770-4 Annex 1 formula (generalizes the standard's
    // 48 kHz reference table to any sample rate via a tan() bilinear prewarp).
    {
        const double f0 = 1681.9744509555319;
        const double G  = 3.99984385397;
        const double Q  = 0.7071752369554193;

        const double K  = tan(M_PI * f0 / sr);
        const double Vh = pow(10.0, G / 20.0);
        const double Vb = pow(Vh, 0.4996667741545416);

        const double a0 = 1.0 + K / Q + K * K;
        const double b0 = (Vh + Vb * K / Q + K * K) / a0;
        const double b1 =        2.0 * (K * K - Vh) / a0;
        const double b2 = (Vh - Vb * K / Q + K * K) / a0;
        const double a1 =        2.0 * (K * K - 1.0) / a0;
        const double a2 = (1.0 - K / Q + K * K) / a0;

        _store_coeffs(b0, b1, b2, a1, a2, &_kw1);
    }

    // ── Stage 2: RLB weighting (high-pass) ────────────────────────────────
    {
        const double f0 = 38.13547087602444;
        const double Q  = 0.5003270373238773;
        const double K  = tan(M_PI * f0 / sr);

        const double a0 = 1.0 + K / Q + K * K;
        const double b0 =  1.0 / a0;
        const double b1 = -2.0 / a0;
        const double b2 =  1.0 / a0;
        const double a1 =  2.0 * (K * K - 1.0) / a0;
        const double a2 = (1.0 - K / Q + K * K) / a0;

        _store_coeffs(b0, b1, b2, a1, a2, &_kw2);
    }

    // Smoothing coefficients: 1 frame step along the attack/release RC tau.
    _alpha_attack  = 1.0f - expf(-1.0f / ((float)sr * ATTACK_TAU_SEC));
    _alpha_release = 1.0f - expf(-1.0f / ((float)sr * RELEASE_TAU_SEC));

    // Sub-block length in frames (100 ms). Minimum 1 to avoid a div/mod by 0
    // on pathological sample rates.
    _sub_block_frames = (int32_t)(sr * SUB_BLOCK_SEC + 0.5);
    if (_sub_block_frames < 1) _sub_block_frames = 1;

    LN_LOG("coeffs updated: sr=%.0f sub_block_frames=%d alpha_att=%.2e alpha_rel=%.2e",
           sr, _sub_block_frames, (double)_alpha_attack, (double)_alpha_release);
}

// ── Channel weighting (BS.1770-4 power-domain weights) ───────────────────────
//
// Best-effort canonical channel order — see loudness_processor.h for the
// documented limitation (NarAudioBuffer carries a channel COUNT, not a mask).
static void _channel_weights(int32_t channels, float* w) {
    switch (channels) {
        case 1:  // Mono
            w[0] = 1.0f;
            break;
        case 2:  // Stereo: FL, FR
            w[0] = w[1] = 1.0f;
            break;
        case 3:  // Assumed FL, FR, FC
            w[0] = w[1] = w[2] = 1.0f;
            break;
        case 4:  // Android QUAD: FL, FR, BL, BR
            w[0] = w[1] = 1.0f;
            w[2] = w[3] = SURROUND_WEIGHT;
            break;
        case 5:  // Assumed FL, FR, FC, BL, BR
            w[0] = w[1] = w[2] = 1.0f;
            w[3] = w[4] = SURROUND_WEIGHT;
            break;
        case 6:  // Android 5POINT1: FL, FR, FC, LFE, BL, BR
            w[0] = w[1] = w[2] = 1.0f;
            w[3] = 0.0f;
            w[4] = w[5] = SURROUND_WEIGHT;
            break;
        case 7:  // Assumed FL, FR, FC, LFE, BC, SL, SR
            w[0] = w[1] = w[2] = 1.0f;
            w[3] = 0.0f;
            w[4] = w[5] = w[6] = SURROUND_WEIGHT;
            break;
        case 8:  // Android 7POINT1_SURROUND: FL, FR, FC, LFE, BL, BR, SL, SR
            w[0] = w[1] = w[2] = 1.0f;
            w[3] = 0.0f;
            w[4] = w[5] = w[6] = w[7] = SURROUND_WEIGHT;
            break;
        default:
            // Should be unreachable (channels is validated to [1, MAX_CHANNELS]
            // before this is called) — fail open with unity weighting.
            for (int32_t c = 0; c < channels && c < MAX_CHANNELS; ++c) w[c] = 1.0f;
            break;
    }
}

// ── Internal reset (no atomic changes — caller owns bypass state) ─────────────

static void _reset_internal(void) {
    memset(&_st1, 0, sizeof _st1);
    memset(&_st2, 0, sizeof _st2);

    _weights_channels = 0;
    memset(_weights, 0, sizeof _weights);

    memset(_sub_block_ring, 0, sizeof _sub_block_ring);
    _ring_index = 0;
    _ring_filled = 0;
    _sub_acc   = 0.0;
    _sub_count = 0;

    _abs_sum_z = 0.0;
    _abs_count = 0;
    _rel_sum_z = 0.0;
    _rel_count = 0;

    _gain_smooth = 1.0f;
    atomic_store(&_gain_target_bits,      _float_to_bits(1.0f));
    atomic_store(&_measured_lufs_bits,    _float_to_bits(-99.0f));
    atomic_store(&_applied_gain_db_bits,  _float_to_bits(0.0f));
}

// ── VTable callbacks ──────────────────────────────────────────────────────────

static int32_t _ln_init(void* self) {
    (void)self;
    _compute_kw_coeffs(48000.0);
    _reset_internal();
    atomic_store(&_bypass,           1);  // start bypassed
    atomic_store(&_enabled,          0);
    atomic_store(&_target_lufs_bits, _float_to_bits(DEFAULT_TARGET_LUFS));
    LN_LOG("init ok");
    return NATIVE_RUNTIME_OK;
}

// Process one channel's K-weighting cascade for sample x. Defensive: if the
// result of either stage is non-finite, that channel's filter state is
// zeroed and the sample is treated as silence (fail-open — see file header).
static inline float _kweight_sample(int32_t ch, float x) {
    float y1 = nar_biquad_process_sample(&_kw1, &_st1.s1[ch], &_st1.s2[ch], x);
    if (!isfinite(y1)) {
        _st1.s1[ch] = 0.0f;
        _st1.s2[ch] = 0.0f;
        y1 = 0.0f;
    }
    float y2 = nar_biquad_process_sample(&_kw2, &_st2.s1[ch], &_st2.s2[ch], y1);
    if (!isfinite(y2)) {
        _st2.s1[ch] = 0.0f;
        _st2.s2[ch] = 0.0f;
        y2 = 0.0f;
    }
    return y2;
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

    if (channels != _weights_channels) {
        _channel_weights(channels, _weights);
        _weights_channels = channels;
    }

    // Load current gain target (written by audio thread; atomic for consistency).
    float gain_target = _bits_to_float(atomic_load(&_gain_target_bits));

    // ── Per-frame loop ────────────────────────────────────────────────────────
    for (int32_t f = 0; f < frames; ++f) {
        float* frame = data + (size_t)f * (size_t)channels;

        // 1. K-weighting + BS.1770-4 power-domain channel weighting.
        //    frame_power = Σ_c G_c * y_c^2 — this is already the per-frame
        //    contribution to the block's channel-weighted mean-square z,
        //    since averaging is linear and distributes over the weighted sum.
        double frame_power = 0.0;
        for (int32_t ch = 0; ch < channels; ++ch) {
            // Sanitize a non-finite INPUT sample in place before it reaches
            // either the K-weighting measurement path or the gain multiply
            // below — otherwise a single corrupt decoded sample (NaN/Inf)
            // would multiply straight through to the output and poison
            // every downstream processor (peq/compressor/limiter/etc.).
            float x = frame[ch];
            if (!isfinite(x)) {
                x = 0.0f;
                frame[ch] = 0.0f;
            }
            const float y = _kweight_sample(ch, x);
            frame_power += (double)_weights[ch] * (double)y * (double)y;
        }
        _sub_acc += frame_power;
        _sub_count += 1;

        // 2. 100 ms sub-block boundary → push into the 400 ms gating ring.
        if (_sub_count >= _sub_block_frames) {
            const double sub_mean = _sub_acc / (double)_sub_count;
            _sub_block_ring[_ring_index] = sub_mean;
            _ring_index = (_ring_index + 1) % SUB_BLOCKS_PER_BLOCK;
            if (_ring_filled < SUB_BLOCKS_PER_BLOCK) _ring_filled += 1;
            _sub_acc   = 0.0;
            _sub_count = 0;

            // 3. Once the 400 ms window is full, run the BS.1770-4 two-stage
            //    gating update (causal approximation — see file header).
            if (_ring_filled == SUB_BLOCKS_PER_BLOCK) {
                double block_z = 0.0;
                for (int32_t i = 0; i < SUB_BLOCKS_PER_BLOCK; ++i) block_z += _sub_block_ring[i];
                block_z /= (double)SUB_BLOCKS_PER_BLOCK;

                const double block_lufs = LUFS_OFFSET + 10.0 * log10(block_z + POWER_FLOOR);

                // Stage A: absolute-gated running mean → relative threshold.
                if (block_lufs > GATE_ABS_LUFS) {
                    _abs_sum_z += block_z;
                    _abs_count += 1;
                }

                if (_abs_count > 0) {
                    const double abs_mean_z   = _abs_sum_z / (double)_abs_count;
                    const double abs_gated_db = LUFS_OFFSET + 10.0 * log10(abs_mean_z + POWER_FLOOR);
                    const double rel_threshold = abs_gated_db - GATE_REL_LU;

                    // Stage B: absolute + relative gated running mean → the
                    // final integrated-so-far loudness estimate.
                    if (block_lufs > GATE_ABS_LUFS && block_lufs >= rel_threshold) {
                        _rel_sum_z += block_z;
                        _rel_count += 1;
                    }
                }

                if (_rel_count > 0) {
                    const double rel_mean_z     = _rel_sum_z / (double)_rel_count;
                    const double integrated_lufs = LUFS_OFFSET + 10.0 * log10(rel_mean_z + POWER_FLOOR);
                    atomic_store(&_measured_lufs_bits, _float_to_bits((float)integrated_lufs));

                    const float target_lufs = _bits_to_float(atomic_load(&_target_lufs_bits));
                    float gain_db = target_lufs - (float)integrated_lufs;
                    if (gain_db > MAX_GAIN_DB) gain_db = MAX_GAIN_DB;
                    if (gain_db < MIN_GAIN_DB) gain_db = MIN_GAIN_DB;
                    gain_target = powf(10.0f, gain_db / 20.0f);
                    atomic_store(&_gain_target_bits, _float_to_bits(gain_target));
                }
                // else: not enough gated content yet (e.g. near-silent
                // intro/track) — leave measured_lufs at its last value
                // (sentinel −99.0 if this is the first block) and leave
                // gain_target unchanged, per the absolute-gate contract.
            }

            // Refresh the UI-facing applied-gain display every 100 ms hop.
            const float applied_db = 20.0f * log10f(_gain_smooth + 1e-10f);
            atomic_store(&_applied_gain_db_bits, _float_to_bits(applied_db));
        }

        // 4. Smooth gain interpolation — asymmetric attack/release.
        //    Attack  (gain_target < _gain_smooth): fast alpha ≈ 0.3 s tau.
        //    Release (gain_target > _gain_smooth): slow alpha ≈ 3.0 s tau.
        const float _alpha = (gain_target < _gain_smooth) ? _alpha_attack : _alpha_release;
        _gain_smooth += _alpha * (gain_target - _gain_smooth);
        if (!isfinite(_gain_smooth)) _gain_smooth = 1.0f;  // defensive fail-open

        // 5. Apply smooth gain to all channels.
        for (int32_t ch = 0; ch < channels; ++ch) {
            frame[ch] *= _gain_smooth;
        }
    }  // end per-frame loop

    return NATIVE_RUNTIME_OK;
}

static void _ln_reset(void* self) {
    (void)self;
    // Transient bypass: ensures audio thread won't read stale filter/gating
    // state while we clear it. The bypass lasts < 1 μs (just an atomic store).
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
    _compute_kw_coeffs((double)sample_rate);
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
