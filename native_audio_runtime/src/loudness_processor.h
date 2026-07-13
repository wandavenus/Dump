// Loudness Normalization Processor — Phase 8.5 (hardened, ITU-R BS.1770-4).
//
// Pipeline slot 2 (between dsp.replaygain at slot 1 and dsp.peq at slot 3).
//
// Implements a real-time EBU R128 / ITU-R BS.1770-4 perceptual loudness
// measurement + smooth gain controller. This processor is SEPARATE from and
// COMPLEMENTARY TO the ReplayGain processor:
//
//   ReplayGain (slot 1) — metadata-based, song-level gain offset.
//   Loudness Norm (slot 2) — real-time measurement, gentle playback adjustment.
//
// Design summary (production-hardening pass):
//   1. K-weighting: two biquad stages per channel, using the literal
//      ITU-R BS.1770-4 Annex 1 coefficient formulas (tan/pow-based, derived
//      directly at the live sample rate) rather than an RBJ-cookbook
//      approximation — see _compute_kw_coeffs() for the closed-form math.
//   2. Per-channel BS.1770-4 channel weighting (front L/R/C = 1.0 power
//      weight, surround/back = +1.5 dB ≈ 1.41254 power weight, LFE = 0.0)
//      applied to squared K-weighted samples and SUMMED (not averaged)
//      across channels, matching the spec's power-domain loudness formula.
//   3. Two-stage gated cumulative block integration matching BS.1770-4 §5:
//      100 ms sub-blocks combined into 400 ms / 75%-overlap gating blocks;
//      an absolute-gated running mean (> −70 LUFS) establishes the relative
//      gate threshold (running mean − 10 LU); blocks passing both gates
//      accumulate into the final integrated-loudness estimate. This is a
//      causal, O(1)-memory approximation of the spec's offline two-pass
//      algorithm — the accepted approach for real-time/continuous meters.
//   4. Gain target = 10^((target_lufs - integrated_lufs) / 20), clamped to
//      [MIN_GAIN_DB, MAX_GAIN_DB].
//   5. Smooth gain via first-order IIR with asymmetric time constants: fast
//      attack (~0.3 s) for gain reduction, slow release (~3 s) for gain
//      increase — intentionally slow, this is NOT a compressor.
//   6. Defensive NaN/Inf guard after every biquad stage: a single non-finite
//      input sample cannot permanently poison the K-weighting IIR state
//      (fail-open, consistent with the rest of this DSP runtime).
//
// Known limitation (documented, not fixed): for channel counts other than
// 1 or 2, this module assumes a canonical channel order (front L/R/C, then
// surround/back, with LFE at index 3 for 6/7/8-channel layouts) because
// NarAudioBuffer carries only a channel COUNT, not a channel mask. This
// matches Android's standard AudioFormat.CHANNEL_OUT_5POINT1 / 7POINT1
// layouts for 6/8 channels; 3/5/7-channel layouts are a best-effort
// assumption since Android has no single canonical mask for them.
//
// Thread safety:
//   Audio thread — K-weighting, power integration, gating, gain smoothing,
//                  sample multiply. No locks, no heap, deterministic cost.
//   Control thread — writes target_lufs, bypass, sample_rate (via transient
//                    bypass on SR change). Reads measured_lufs / applied_gain_db.
//
// All cross-thread state uses the IEEE 754 bit-pattern atomic trick
// (same as gain_processor.c, replaygain_processor.c).

#ifndef NATIVE_AUDIO_RUNTIME_LOUDNESS_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_LOUDNESS_PROCESSOR_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Register the Loudness Normalization processor with the DSP pipeline.
/// Must be called after nar_replaygain_processor_register_internal() so that
/// the correct slot order is preserved. Returns NATIVE_RUNTIME_OK (0) on
/// success, or NATIVE_RUNTIME_ERROR_DUPLICATE_MODULE if already registered.
FFI_PLUGIN_EXPORT int32_t nar_loudness_processor_register_internal(void);

/// Set the target output loudness in LUFS.
/// Typical values: −23.0 (EBU R128 broadcast), −16.0 (podcast), −14.0 (streaming).
/// Clamped to [−36.0, −6.0] LUFS. Default: −23.0.
/// Thread-safe atomic store — takes effect on the next gating-block boundary.
FFI_PLUGIN_EXPORT void nar_loudness_set_target_lufs(float target_lufs);

/// Enable (bypass=0) or bypass (bypass=1) the Loudness Normalization processor.
/// Thread-safe atomic store. When bypassed, audio passes through unmodified.
FFI_PLUGIN_EXPORT void nar_loudness_set_bypass(int32_t bypass);

/// Returns 1 if the processor is currently bypassed, 0 if active.
FFI_PLUGIN_EXPORT int32_t nar_loudness_get_bypass(void);

/// Update the playback sample rate and recompute K-weighting coefficients.
///
/// Must be called whenever ExoPlayer reports a sample rate change.
/// Internally engages a transient bypass, recomputes biquad coefficients for
/// the new rate using the literal BS.1770-4 closed-form formulas, clears all
/// filter and gating state, then re-engages the processor.
/// The momentary bypass (~1 buffer) is completely inaudible.
///
/// Default: 48000 Hz (set during init — no call needed for standard streams).
FFI_PLUGIN_EXPORT void nar_loudness_set_sample_rate(int32_t sample_rate);

/// Current gated-integrated measured loudness in LUFS.
///
/// Updated on the audio thread every 100 ms (BS.1770-4 gating hop) once the
/// first 400 ms gating block has both filled and passed the absolute +
/// relative loudness gates.
/// Returns −99.0 before the first gated measurement is available (e.g.
/// during the initial 400 ms, or for content that never exceeds the
/// absolute gate) or when bypassed.
/// Thread-safe atomic load — safe to call from any thread including the UI.
FFI_PLUGIN_EXPORT float nar_loudness_get_measured_lufs(void);

/// Current smooth gain applied to the audio stream, in dBFS.
///
/// Positive = boost, negative = attenuation. Refreshed every 100 ms hop.
/// Returns 0.0 when bypassed.
FFI_PLUGIN_EXPORT float nar_loudness_get_applied_gain_db(void);

/// Reset the loudness analyzer: clear K-weighting filter state, the sub-block
/// gating ring buffer, the gated cumulative accumulators, and smooth gain
/// back to unity. Gain target is reset to unity.
///
/// Call on every track change so the new track is measured fresh.
/// Thread-safe: internally uses a transient bypass to prevent the audio
/// thread from reading stale state.
FFI_PLUGIN_EXPORT void nar_loudness_reset(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_LOUDNESS_PROCESSOR_H_
