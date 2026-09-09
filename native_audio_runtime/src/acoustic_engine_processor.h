// Acoustic Engine — speaker-oriented, zero-latency perceptual enhancement.
#ifndef NATIVE_AUDIO_RUNTIME_ACOUSTIC_ENGINE_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_ACOUSTIC_ENGINE_PROCESSOR_H_

#include <stdint.h>
#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Registers as dsp.acoustic_engine. Registration order places it after
// loudness/replay-gain and before the compressor/limiter safety stages.
FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_processor_register_internal(void);

// Intensity is a single user-facing control in [0, 1]. The control thread
// derives and publishes all internal strengths atomically; the audio thread
// only consumes precomputed values.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_intensity(float intensity);
FFI_PLUGIN_EXPORT float nar_acoustic_engine_get_intensity(void);

// A true zero-copy bypass. Disabling clears histories so stale IIR/envelope
// state can never colour audio after a later enable.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_bypass(int32_t bypass);
FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_get_bypass(void);

// Called on a format transition by the control plane. Coefficients are built
// here, never in the audio callback. Invalid rates use the 48 kHz fallback.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_sample_rate(int32_t sample_rate);
FFI_PLUGIN_EXPORT void nar_acoustic_engine_reset(void);

#ifdef __cplusplus
}
#endif
#endif  // NATIVE_AUDIO_RUNTIME_ACOUSTIC_ENGINE_PROCESSOR_H_
