// Crossfeed Processor — Phase 7.
//
// Frequency-dependent headphone crossfeed processor.
// Registers as "dsp.crossfeed" at pipeline slot 3 (after dsp.compressor,
// before dsp.limiter).
//
// ── Purpose ───────────────────────────────────────────────────────────────────
//
// Headphones present each ear with a completely isolated channel. This unnatural
// "channel isolation" is fatiguing for long listening sessions and produces an
// exaggerated stereo image perceived entirely inside the listener's head.
//
// Crossfeed simulates the acoustic coupling between speakers and ears:
//   - Low frequencies radiate broadly and arrive at BOTH ears.
//   - High frequencies are more directional and arrive mostly at the near ear.
//
// By blending a lowpass-filtered version of each channel into the opposite
// channel, the processor collapses the extreme low-frequency stereo spread
// while preserving high-frequency imaging — matching the perceptual result of
// listening on speakers.
//
// ── Algorithm (per stereo frame) ─────────────────────────────────────────────
//
//   Step 1: Cross-path lowpass
//     xfeed_L = lowpass(R_in)   — filtered R for the L output
//     xfeed_R = lowpass(L_in)   — filtered L for the R output
//
//   Step 2: HF compensation shelf
//     direct_L = highshelf(L_in)  — restore HF energy on the direct path
//     direct_R = highshelf(R_in)
//
//   Step 3: Mix + normalize (maintains equal-loudness)
//     norm     = 1 / (1 + amount)  — pre-computed on the control thread
//     L_mixed  = (direct_L + amount * xfeed_L) * norm
//     R_mixed  = (direct_R + amount * xfeed_R) * norm
//
//   Step 4: Stereo width matrix (preserves image width)
//     [L_out, R_out] = nar_stereo_matrix_width(width) * [L_mixed, R_mixed]
//
// Mono channels (channels == 1) pass through unchanged.
// Channels beyond index 1 (e.g. surround) pass through unchanged.
//
// ── Filter details ────────────────────────────────────────────────────────────
//
// Cross-path:   2nd-order Butterworth lowpass (Q = 0.7071 = 1/√2).
//               cutoff_hz controls the crossfeed frequency threshold.
//               Typical values: 300–1500 Hz (default 700 Hz).
//
// HF compensation: 2nd-order high shelf (slope Q = 0.7071).
//               hf_comp_db controls the shelf gain (0 = transparent).
//               hf_comp_hz controls the shelf corner frequency.
//               Default: +3 dB shelf at 4000 Hz — compensates for the
//               slight HF loss caused by the crossfeed blending.
//
// ── Parameters ────────────────────────────────────────────────────────────────
//
//   amount      : Crossfeed strength [0.0, 1.0]. 0 = bypass-equivalent.
//                 Default: 0.3 (gentle, transparent crossfeed).
//   cutoff_hz   : LP filter cutoff [100, 2000] Hz. Default: 700 Hz.
//   hf_comp_db  : High-shelf gain [0, 12] dB. Default: 3.0 dB.
//   hf_comp_hz  : High-shelf corner [1000, 16000] Hz. Default: 4000 Hz.
//   width       : Stereo width multiplier [0.0, 2.0]. Default: 1.0 (unity).
//
// ── Thread safety ─────────────────────────────────────────────────────────────
//
// All parameter sets are pre-computed (biquad coefficients via nar_biquad_compute)
// on the control thread and committed via an acquire/release dirty-flag protocol
// identical to the compressor. The audio thread does a struct copy on dirty==1,
// then runs the pure TDF-II biquad recurrence — no transcendentals, no locks,
// no heap allocation.

#ifndef NATIVE_AUDIO_RUNTIME_CROSSFEED_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_CROSSFEED_PROCESSOR_H_

#include <stdint.h>
#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Register the crossfeed processor with the DSP pipeline.
// Must be called after nar_comp_processor_register_internal() and before
// nar_limiter_processor_register_internal().
// Idempotent: returns NATIVE_RUNTIME_ERROR_DUPLICATE_MODULE if already registered.
FFI_PLUGIN_EXPORT int32_t nar_crossfeed_processor_register_internal(void);

// Configure all crossfeed parameters in one atomic call.
//
// [amount]     : Crossfeed strength. Default: 0.3. Clamped to [0, 1].
//               0.0 = no crossfeed (pass-through equivalent).
//               1.0 = maximum crossfeed (full equal mix of filtered signals).
// [cutoff_hz]  : Lowpass cutoff for the cross-channel path. Default: 700.0 Hz.
//               Clamped to [100, 2000].
// [hf_comp_db] : High-shelf gain applied to the direct path for HF compensation.
//               Default: 3.0 dB. Clamped to [0, 12].
//               0.0 = no HF compensation (slightly darker sound).
// [hf_comp_hz] : High-shelf corner frequency. Default: 4000.0 Hz.
//               Clamped to [1000, 16000].
// [width]      : Stereo width multiplier applied after crossfeed mixing.
//               Default: 1.0 (unity). Clamped to [0, 2].
//               1.0 = natural post-crossfeed image.
//               < 1.0 = narrow; > 1.0 = wider than natural.
// [sample_rate]: Current playback sample rate. ≤ 0 → 48000 Hz fallback.
//
// Thread-safe: may be called from any thread while process() is running.
// Returns NATIVE_RUNTIME_OK on success.
FFI_PLUGIN_EXPORT int32_t nar_crossfeed_set_params(
    float amount,
    float cutoff_hz,
    float hf_comp_db,
    float hf_comp_hz,
    float width,
    float sample_rate);

// Enable (bypass=0) or bypass (bypass=1) the crossfeed processor.
// When bypassed, process() is a zero-copy early return. Thread-safe.
FFI_PLUGIN_EXPORT void    nar_crossfeed_set_bypass(int32_t bypass);
FFI_PLUGIN_EXPORT int32_t nar_crossfeed_get_bypass(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_CROSSFEED_PROCESSOR_H_
