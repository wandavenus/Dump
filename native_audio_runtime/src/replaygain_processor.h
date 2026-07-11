// ReplayGain Processor — Phase 8.
//
// A transparent metadata-driven gain stage at DSP pipeline slot 1 (between
// dsp.gain and dsp.peq). Applies REPLAYGAIN_TRACK_GAIN / REPLAYGAIN_ALBUM_GAIN
// (or R128 / iTunNORM equivalents) as a scalar multiply.
//
// Key properties:
//   - Zero algorithmic latency (pure scalar multiply; no IIR state).
//   - Thread-safe parameter updates (lock-free atomics; no blocking on audio thread).
//   - Optional clipping protection: caps the effective gain so that
//     gain_linear × peak_linear ≤ 1.0.
//   - Starts bypassed — call nar_replaygain_set_gain() to engage.
//   - Stateless — reset() is a no-op; no filter history to clear.
//
// Do NOT call these from ExoPlayer's audio thread (Kotlin side) — use the
// Dart PlaybackManager API which routes through here after computing the
// effective gain on the Dart/control thread.

#ifndef NATIVE_AUDIO_RUNTIME_REPLAYGAIN_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_REPLAYGAIN_PROCESSOR_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Register the ReplayGain processor with the DSP pipeline.
/// Must be called after nar_dsp_pipeline_init() and before any playback.
/// Returns NATIVE_RUNTIME_OK (0) on success, or
/// NATIVE_RUNTIME_ERROR_DUPLICATE_MODULE if already registered.
FFI_PLUGIN_EXPORT int32_t nar_replaygain_processor_register_internal(void);

/// Set the ReplayGain gain.
///
/// [gain_db]              : Gain in dBFS from metadata (e.g. −6.0 attenuates
///                          by 6 dB, +1.5 boosts by 1.5 dB).
///                          Clamped to [−24, +24] dB.
/// [peak_linear]          : Track/album peak in linear scale (e.g. 1.05 = 105%).
///                          Pass 0.0 if no peak data is available.
/// [use_clipping_protection]: When 1 and peak > 0, caps effective gain so
///                          gain_linear × peak_linear ≤ 1.0 (prevents clipping).
///
/// Effective gain is computed and stored atomically — audio thread picks up
/// the new value on its next render cycle without blocking.
/// Returns NATIVE_RUNTIME_OK (0).
FFI_PLUGIN_EXPORT int32_t nar_replaygain_set_gain(float gain_db,
                                                    float peak_linear,
                                                    int32_t use_clipping_protection);

/// Enable (bypass=0) or bypass (bypass=1) the ReplayGain processor.
/// Thread-safe atomic store.
FFI_PLUGIN_EXPORT void nar_replaygain_set_bypass(int32_t bypass);

/// Returns 1 if the processor is currently bypassed, 0 if active.
/// Thread-safe atomic load.
FFI_PLUGIN_EXPORT int32_t nar_replaygain_get_bypass(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_REPLAYGAIN_PROCESSOR_H_
