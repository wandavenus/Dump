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
// All coefficient math runs in double precision on the AUDIO thread, but
// only on the rare frame where a stream's sample rate actually changes (see
// "Per-stream sample-rate auto-detect" below) — never per-sample.
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
//
// ── Per-stream isolation (production-hardening pass) ────────────────────────
//
// Every field that is derived from or mutated by the actual audio flowing
// through a specific stream — K-weighting filter state, gating ring
// buffer/accumulators, the smoothed gain, and even the K-weighting
// COEFFICIENTS themselves (since two concurrently-playing streams can
// legitimately be decoding at different sample rates) — is now an array of
// NAR_DSP_MAX_STREAMS slots, indexed by `stream_slot`. See dsp_stream.h for
// the general rationale.
//
// `target_lufs`/`enabled`/`bypass` remain SHARED: there is only one
// loudness-target knob and one on/off switch in the whole app, applied
// uniformly to both streams.
//
// `measured_lufs`/`applied_gain_db`/`gain_target` are audio-thread OUTPUTS
// that are inherently stream-specific (two different tracks can measure
// different loudness) — these become per-stream arrays too. The public
// getters (`nar_loudness_get_measured_lufs()` etc.), which predate the
// concept of multiple streams, keep defaulting to stream 0 for full
// backward compatibility — see the "Known limitation" note below.
//
// ── Per-stream sample-rate auto-detect ──────────────────────────────────────
//
// Rather than requiring Dart/Kotlin to call `nar_loudness_set_sample_rate()`
// once per stream (a public API change), each stream instead caches the
// sample rate of the last buffer it processed. On the rare frame where a
// stream's incoming buffer reports a different `sample_rate` than that
// cache, this processor recomputes ONLY that stream's K-weighting
// coefficients/timing constants from the buffer's own `sample_rate` field
// (already passed into every process() call) — lazily, and only for the
// stream that actually changed rate. `nar_loudness_set_sample_rate()` is
// kept as a public back-compat wrapper that pre-seeds stream 0's cached
// rate (a no-op fast path once auto-detection has already converged).
//
// ── Known limitation ─────────────────────────────────────────────────────────
//
// `nar_loudness_reset()` (called by Dart on every track change) is scoped
// to stream 0 ONLY — it must not clobber a concurrently-preloading standby
// stream's gating history. Dart's crossfade code has no concept of "which
// logical stream this track-changed event belongs to" today, so a
// standby stream's own gating state is only reset lazily, the first time
// ITS sample rate actually changes (a reasonable proxy for "new track
// beginning to decode", though not a perfect signal). The vtable-level
// `reset()` (rare, called by `nar_dsp_pipeline_reset()` on seek/flush) DOES
// clear every stream, since that call has no single-stream semantics to
// begin with.

#include "loudness_processor.h"

#include <math.h>
#include <stdatomic.h>
#include <string.h>

#include "audio_buffer.h"
#include "biquad_filter.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "dsp_stream.h"
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

// ── Per-stream runtime state ──────────────────────────────────────────────────

typedef struct {
    // K-weighting biquad coefficients — per stream because two concurrently
    // playing streams can be decoding at different sample rates.
    NarBiquadCoeffs kw1;   // Stage 1: pre-filter
    NarBiquadCoeffs kw2;   // Stage 2: RLB high-pass
    int32_t         last_sample_rate;  // cached SR this stream's coeffs were derived from (0 = uninitialized)

    // Per-channel biquad state (audio thread only).
    NarBiquadState st1;    // Stage 1 delay state
    NarBiquadState st2;    // Stage 2 delay state

    // Cached per-channel BS.1770-4 power weights (recomputed only when this
    // stream's channel count changes).
    float   weights[MAX_CHANNELS];
    int32_t weights_channels;  // 0 = not yet computed

    // Sample-rate-derived sub-block length in frames.
    int32_t sub_block_frames;

    // 100 ms sub-block gating ring buffer.
    double  sub_block_ring[SUB_BLOCKS_PER_BLOCK];  // mean-square per 100ms
    int32_t ring_index;
    int32_t ring_filled;      // number of valid ring slots, capped at 4

    // Current in-progress 100 ms sub-block accumulator.
    double  sub_acc;
    int32_t sub_count;

    // Cumulative gating accumulators since last reset (audio thread only).
    // Stage A: absolute-gated running mean — establishes the relative threshold.
    double  abs_sum_z;
    int64_t abs_count;
    // Stage B: absolute+relative-gated running mean — the final integrated LUFS.
    double  rel_sum_z;
    int64_t rel_count;

    // Smooth gain (linear). Audio thread only — no atomic needed.
    float gain_smooth;

    // Per-frame smoothing coefficients (precomputed alongside the coeffs
    // above, from this stream's own sample rate).
    float alpha_attack;   // fast — gain reduction  (~0.3 s)
    float alpha_release;  // slow — gain increase   (~3.0 s)

    // Audio-thread outputs, exposed cross-thread via atomics so the legacy
    // stream-0-only getters remain lock-free and consistent.
    _Atomic int32_t measured_lufs_bits;    // audio → control (UI display)
    _Atomic int32_t applied_gain_db_bits;  // audio → control (UI display)
    _Atomic int32_t gain_target_bits;      // audio thread: last computed target
} NarLoudnessStream;

static NarLoudnessStream _streams[NAR_DSP_MAX_STREAMS];

// ── Shared control-plane (one set of user-facing knobs for the whole app) ───

static _Atomic int32_t _target_lufs_bits;      // control → audio (shared)
static _Atomic int32_t _bypass;                // control → audio (1=bypass) (shared)
static _Atomic int32_t _enabled;               // control: is user-enabled? (shared)

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

// Recomputes stream `s`'s K-weighting coefficients and smoothing timing
// constants from `sr`. Runs on the audio thread, but only on the rare frame
// where that stream's sample rate has actually changed (see
// `_ensure_sample_rate()`), never per-sample. Uses double precision, same
// as the original control-thread implementation — the cost (a handful of
// tan/pow/log calls) is negligible when amortized over an entire stream's
// lifetime at a fixed sample rate.
static void _compute_kw_coeffs(NarLoudnessStream* st, double sr) {
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

        _store_coeffs(b0, b1, b2, a1, a2, &st->kw1);
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

        _store_coeffs(b0, b1, b2, a1, a2, &st->kw2);
    }

    // Smoothing coefficients: 1 frame step along the attack/release RC tau.
    st->alpha_attack  = 1.0f - expf(-1.0f / ((float)sr * ATTACK_TAU_SEC));
    st->alpha_release = 1.0f - expf(-1.0f / ((float)sr * RELEASE_TAU_SEC));

    // Sub-block length in frames (100 ms). Minimum 1 to avoid a div/mod by 0
    // on pathological sample rates.
    st->sub_block_frames = (int32_t)(sr * SUB_BLOCK_SEC + 0.5);
    if (st->sub_block_frames < 1) st->sub_block_frames = 1;

    st->last_sample_rate = (int32_t)sr;

    LN_LOG("coeffs updated: sr=%.0f sub_block_frames=%d alpha_att=%.2e alpha_rel=%.2e",
           sr, st->sub_block_frames, (double)st->alpha_attack, (double)st->alpha_release);
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

// ── Internal per-stream reset (no atomic changes to shared state) ────────────

static void _reset_stream(NarLoudnessStream* st) {
    memset(&st->st1, 0, sizeof st->st1);
    memset(&st->st2, 0, sizeof st->st2);

    st->weights_channels = 0;
    memset(st->weights, 0, sizeof st->weights);

    memset(st->sub_block_ring, 0, sizeof st->sub_block_ring);
    st->ring_index = 0;
    st->ring_filled = 0;
    st->sub_acc   = 0.0;
    st->sub_count = 0;

    st->abs_sum_z = 0.0;
    st->abs_count = 0;
    st->rel_sum_z = 0.0;
    st->rel_count = 0;

    st->gain_smooth = 1.0f;
    atomic_store(&st->gain_target_bits,     _float_to_bits(1.0f));
    atomic_store(&st->measured_lufs_bits,   _float_to_bits(-99.0f));
    atomic_store(&st->applied_gain_db_bits, _float_to_bits(0.0f));
}

// Ensures stream `s`'s K-weighting coefficients match the sample rate
// actually present on the current buffer, lazily regenerating them (and
// resetting the stream's gating history — a sample-rate change only occurs
// at a track/stream boundary) on the rare frame where it differs from the
// cached value. Zero cost on every other frame (a single int comparison).
static void _ensure_sample_rate(NarLoudnessStream* st, int32_t sample_rate) {
    if (sample_rate <= 0) sample_rate = 48000;
    if (st->last_sample_rate == sample_rate) return;  // fast path — unchanged
    _compute_kw_coeffs(st, (double)sample_rate);
    _reset_stream(st);
    st->last_sample_rate = sample_rate;  // _compute_kw_coeffs also sets this, kept for clarity
}

// ── VTable callbacks ──────────────────────────────────────────────────────────

static int32_t _ln_init(void* self) {
    (void)self;
    for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
        NarLoudnessStream* st = &_streams[s];
        st->last_sample_rate = 0;  // force coeff computation on first buffer
        _compute_kw_coeffs(st, 48000.0);
        _reset_stream(st);
    }
    atomic_store(&_bypass,           1);  // start bypassed
    atomic_store(&_enabled,          0);
    atomic_store(&_target_lufs_bits, _float_to_bits(DEFAULT_TARGET_LUFS));
    LN_LOG("init ok");
    return NATIVE_RUNTIME_OK;
}

// Process one channel's K-weighting cascade for sample x, using stream
// `st`'s own coefficients/state. Defensive: if the result of either stage
// is non-finite, that channel's filter state is zeroed and the sample is
// treated as silence (fail-open — see file header).
static inline float _kweight_sample(NarLoudnessStream* st, int32_t ch, float x) {
    float y1 = nar_biquad_process_sample(&st->kw1, &st->st1.s1[ch], &st->st1.s2[ch], x);
    if (!isfinite(y1)) {
        st->st1.s1[ch] = 0.0f;
        st->st1.s2[ch] = 0.0f;
        y1 = 0.0f;
    }
    float y2 = nar_biquad_process_sample(&st->kw2, &st->st2.s1[ch], &st->st2.s2[ch], y1);
    if (!isfinite(y2)) {
        st->st2.s1[ch] = 0.0f;
        st->st2.s2[ch] = 0.0f;
        y2 = 0.0f;
    }
    return y2;
}

static int32_t _ln_process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
    (void)self;
    const int32_t s = nar_dsp_clamp_stream(stream_slot);
    NarLoudnessStream* st = &_streams[s];

    // Zero-copy bypass: return immediately, audio unchanged.
    if (atomic_load(&_bypass)) return NATIVE_RUNTIME_OK;

    float*        data     = nar_audio_buffer_data(buffer);
    if (!data) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

    const int32_t frames   = nar_audio_buffer_frame_count(buffer);
    const int32_t channels = nar_audio_buffer_channel_count(buffer);
    if (channels < 1 || channels > MAX_CHANNELS)
        return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;

    // Buffer-driven sample-rate auto-detect — see file header. Lazily
    // regenerates this STREAM's coefficients only, so two concurrently
    // playing streams at different sample rates never interfere.
    _ensure_sample_rate(st, nar_audio_buffer_sample_rate(buffer));

    if (channels != st->weights_channels) {
        _channel_weights(channels, st->weights);
        st->weights_channels = channels;
    }

    // Load current gain target (written by audio thread; atomic for consistency).
    float gain_target = _bits_to_float(atomic_load(&st->gain_target_bits));
    float gain_smooth  = st->gain_smooth;

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
            const float y = _kweight_sample(st, ch, x);
            frame_power += (double)st->weights[ch] * (double)y * (double)y;
        }
        st->sub_acc += frame_power;
        st->sub_count += 1;

        // 2. 100 ms sub-block boundary → push into the 400 ms gating ring.
        if (st->sub_count >= st->sub_block_frames) {
            const double sub_mean = st->sub_acc / (double)st->sub_count;
            st->sub_block_ring[st->ring_index] = sub_mean;
            st->ring_index = (st->ring_index + 1) % SUB_BLOCKS_PER_BLOCK;
            if (st->ring_filled < SUB_BLOCKS_PER_BLOCK) st->ring_filled += 1;
            st->sub_acc   = 0.0;
            st->sub_count = 0;

            // 3. Once the 400 ms window is full, run the BS.1770-4 two-stage
            //    gating update (causal approximation — see file header).
            if (st->ring_filled == SUB_BLOCKS_PER_BLOCK) {
                double block_z = 0.0;
                for (int32_t i = 0; i < SUB_BLOCKS_PER_BLOCK; ++i) block_z += st->sub_block_ring[i];
                block_z /= (double)SUB_BLOCKS_PER_BLOCK;

                const double block_lufs = LUFS_OFFSET + 10.0 * log10(block_z + POWER_FLOOR);

                // Stage A: absolute-gated running mean → relative threshold.
                if (block_lufs > GATE_ABS_LUFS) {
                    st->abs_sum_z += block_z;
                    st->abs_count += 1;
                }

                if (st->abs_count > 0) {
                    const double abs_mean_z   = st->abs_sum_z / (double)st->abs_count;
                    const double abs_gated_db = LUFS_OFFSET + 10.0 * log10(abs_mean_z + POWER_FLOOR);
                    const double rel_threshold = abs_gated_db - GATE_REL_LU;

                    // Stage B: absolute + relative gated running mean → the
                    // final integrated-so-far loudness estimate.
                    if (block_lufs > GATE_ABS_LUFS && block_lufs >= rel_threshold) {
                        st->rel_sum_z += block_z;
                        st->rel_count += 1;
                    }
                }

                if (st->rel_count > 0) {
                    const double rel_mean_z     = st->rel_sum_z / (double)st->rel_count;
                    const double integrated_lufs = LUFS_OFFSET + 10.0 * log10(rel_mean_z + POWER_FLOOR);
                    atomic_store(&st->measured_lufs_bits, _float_to_bits((float)integrated_lufs));

                    const float target_lufs = _bits_to_float(atomic_load(&_target_lufs_bits));
                    float gain_db = target_lufs - (float)integrated_lufs;
                    if (gain_db > MAX_GAIN_DB) gain_db = MAX_GAIN_DB;
                    if (gain_db < MIN_GAIN_DB) gain_db = MIN_GAIN_DB;
                    gain_target = powf(10.0f, gain_db / 20.0f);
                    atomic_store(&st->gain_target_bits, _float_to_bits(gain_target));
                }
                // else: not enough gated content yet (e.g. near-silent
                // intro/track) — leave measured_lufs at its last value
                // (sentinel −99.0 if this is the first block) and leave
                // gain_target unchanged, per the absolute-gate contract.
            }

            // Refresh the UI-facing applied-gain display every 100 ms hop.
            const float applied_db = 20.0f * log10f(gain_smooth + 1e-10f);
            atomic_store(&st->applied_gain_db_bits, _float_to_bits(applied_db));
        }

        // 4. Smooth gain interpolation — asymmetric attack/release.
        //    Attack  (gain_target < gain_smooth): fast alpha ≈ 0.3 s tau.
        //    Release (gain_target > gain_smooth): slow alpha ≈ 3.0 s tau.
        const float alpha = (gain_target < gain_smooth) ? st->alpha_attack : st->alpha_release;
        gain_smooth += alpha * (gain_target - gain_smooth);
        if (!isfinite(gain_smooth)) gain_smooth = 1.0f;  // defensive fail-open

        // 5. Apply smooth gain to all channels.
        for (int32_t ch = 0; ch < channels; ++ch) {
            frame[ch] *= gain_smooth;
        }
    }  // end per-frame loop

    st->gain_smooth = gain_smooth;

    return NATIVE_RUNTIME_OK;
}

static void _ln_reset(void* self) {
    (void)self;
    // Transient bypass: ensures audio threads won't read stale filter/gating
    // state while we clear it. The bypass lasts < 1 μs (just an atomic store).
    // Clears EVERY stream — this is the rare, global vtable-level reset (see
    // nar_dsp_pipeline_reset()), which has no single-stream semantics.
    atomic_store(&_bypass, 1);
    for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; s++) {
        _reset_stream(&_streams[s]);
    }
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
//
// All of these remain SINGLE, SHARED knobs (target/bypass/enabled) or
// STREAM-0-SCOPED back-compat accessors (sample rate seed, measured/applied
// getters, reset) — see the file header's "Known limitation" note for why
// per-stream plumbing was not extended to this public surface.

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
    // Back-compat: seeds stream 0's cached sample rate directly (the buffer-
    // driven auto-detect in _ensure_sample_rate() makes this call optional
    // going forward, but existing callers keep working unchanged).
    atomic_store(&_bypass, 1);
    _compute_kw_coeffs(&_streams[0], (double)sample_rate);
    _reset_stream(&_streams[0]);
    if (atomic_load(&_enabled)) atomic_store(&_bypass, 0);
    LN_LOG("sample_rate=%d", sample_rate);
}

FFI_PLUGIN_EXPORT float nar_loudness_get_measured_lufs(void) {
    return _bits_to_float(atomic_load(&_streams[0].measured_lufs_bits));
}

FFI_PLUGIN_EXPORT float nar_loudness_get_applied_gain_db(void) {
    return _bits_to_float(atomic_load(&_streams[0].applied_gain_db_bits));
}

FFI_PLUGIN_EXPORT void nar_loudness_reset(void) {
    // Scoped to stream 0 ONLY (Dart calls this on every track change) — must
    // not clobber a concurrently-preloading standby stream's gating history.
    // See the file header's "Known limitation" note.
    atomic_store(&_bypass, 1);
    _reset_stream(&_streams[0]);
    if (atomic_load(&_enabled)) atomic_store(&_bypass, 0);
}
