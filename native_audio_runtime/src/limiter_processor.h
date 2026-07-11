// Limiter Processor — Phase 6.
//
// Brickwall look-ahead limiter with per-sample linear-domain processing.
// Registers as "dsp.limiter" at pipeline slot 3 (after dsp.compressor).
//
// Algorithm:
//   - For each frame, the current input samples are pushed into a
//     per-channel circular delay buffer (NAR_LIMITER_LOOKAHEAD_FRAMES deep).
//   - The CURRENT (not delayed) peak level is used to compute the desired
//     gain: desired_gain = threshold_linear / peak  (when peak > threshold).
//   - Attack is INSTANT (1 sample): if desired_gain < current_gain, snap.
//   - Release is smooth: one-pole IIR recovering toward 1.0 (unity gain).
//   - The OUTPUT reads the delayed sample and multiplies by the smoothed gain.
//
// This architecture provides:
//   - True brickwall ceiling: output never exceeds threshold_linear.
//   - Look-ahead: gain begins dropping (NAR_LIMITER_LOOKAHEAD_FRAMES − 1)
//     samples before the loud peak reaches the output.
//   - No log/exp in the per-sample hot loop (linear domain only).
//
// Latency:
//   The limiter introduces NAR_LIMITER_LOOKAHEAD_FRAMES − 1 frames of
//   algorithmic latency. This is reported via the vtable's latency_frames()
//   callback. For a music-only player with no A/V sync requirement, the
//   ~1.3 ms at 48 kHz is imperceptible.

#ifndef NATIVE_AUDIO_RUNTIME_LIMITER_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_LIMITER_PROCESSOR_H_

#include <stdint.h>
#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Maximum channels processed per band (extra channels pass through unchanged).
#define NAR_LIMITER_MAX_CHANNELS    8

// Look-ahead delay depth in frames. Must be a power of 2 for the bitwise
// AND modulo trick (& (LOOKAHEAD_FRAMES − 1)) in the inner loop.
// 64 frames ≈ 1.3 ms at 48 kHz.
#define NAR_LIMITER_LOOKAHEAD_FRAMES 64

// Register the limiter processor with the DSP pipeline.
// Must be called after nar_comp_processor_register_internal().
FFI_PLUGIN_EXPORT int32_t nar_limiter_processor_register_internal(void);

// Configure limiter parameters.
//
// [threshold_db] : Ceiling above which limiting begins. Default: −1.0 dBFS.
//                  Clamped to (−30, −0.001). Values ≥ 0 are clamped to −0.001.
// [release_ms]   : Gain recovery time (1/e). Default: 50.0 ms. [1, 1000].
// [sample_rate]  : Current playback sample rate. ≤ 0 → 48000 Hz fallback.
FFI_PLUGIN_EXPORT int32_t nar_limiter_set_params(
    float threshold_db,
    float release_ms,
    float sample_rate);

// Enable (bypass=0) or bypass (bypass=1). Thread-safe.
FFI_PLUGIN_EXPORT void    nar_limiter_set_bypass(int32_t bypass);
FFI_PLUGIN_EXPORT int32_t nar_limiter_get_bypass(void);

// Compile-time constant: NAR_LIMITER_LOOKAHEAD_FRAMES − 1. Reported as
// algorithmic latency via the vtable and queryable from Dart.
FFI_PLUGIN_EXPORT int32_t nar_limiter_lookahead_frames(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_LIMITER_PROCESSOR_H_
