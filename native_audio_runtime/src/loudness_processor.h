// Loudness Normalization Processor — Phase 8.5.
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
// Design summary:
//   1. K-weighting (two biquad stages per channel) on every sample.
//   2. IIR mean-square power integration — zero heap allocation.
//   3. LUFS estimate refreshed every UPDATE_FRAMES (~85 ms at 48 kHz).
//   4. Gain target = 10^((target_lufs - measured_lufs) / 20), clamped ±12 dB.
//   5. Smooth gain via first-order IIR with a 3 s time constant (per frame).
//      Attack and release are intentionally slow — this is NOT a compressor.
//   6. Absolute gate: gain target not updated when signal is below −70 LUFS
//      (EBU R128 absolute gate) to prevent pumping on silence.
//
// Thread safety:
//   Audio thread — K-weighting, power integration, gain smoothing, sample
//                  multiply. No locks, no heap, deterministic per-frame cost.
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
/// Thread-safe atomic store — takes effect on the next UPDATE_FRAMES boundary.
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
/// the new rate, clears all filter state, then re-engages the processor.
/// The momentary bypass (~1 buffer) is completely inaudible.
///
/// Default: 48000 Hz (set during init — no call needed for standard streams).
FFI_PLUGIN_EXPORT void nar_loudness_set_sample_rate(int32_t sample_rate);

/// Current short-term measured loudness in LUFS.
///
/// Updated on the audio thread every ~85 ms (UPDATE_FRAMES at 48 kHz).
/// Returns −99.0 before the first measurement is complete or when bypassed.
/// Thread-safe atomic load — safe to call from any thread including the UI.
FFI_PLUGIN_EXPORT float nar_loudness_get_measured_lufs(void);

/// Current smooth gain applied to the audio stream, in dBFS.
///
/// Positive = boost, negative = attenuation. Updated at UPDATE_FRAMES intervals.
/// Returns 0.0 when bypassed.
FFI_PLUGIN_EXPORT float nar_loudness_get_applied_gain_db(void);

/// Reset the loudness analyzer: clear K-weighting state, power accumulator,
/// and smooth gain back to unity. Gain target is reset to unity.
///
/// Call on every track change so the new track is measured fresh.
/// Thread-safe: internally uses a transient bypass to prevent the audio
/// thread from reading stale state.
FFI_PLUGIN_EXPORT void nar_loudness_reset(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_LOUDNESS_PROCESSOR_H_
