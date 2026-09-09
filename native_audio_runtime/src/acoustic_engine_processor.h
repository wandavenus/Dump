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

// Intensity is a single user-facing control in [0, 1], published as ONE
// atomic scalar (float bits). The audio thread detects the change itself and
// rebuilds its per-stream coefficients there — the control thread never
// writes DSP structs, so rapid slider updates cannot tear any read.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_intensity(float intensity);
FFI_PLUGIN_EXPORT float nar_acoustic_engine_get_intensity(void);

// A true zero-copy bypass: stores one atomic. Each audio thread observes the
// transition and clears its OWN filter/envelope history, so a toggle can
// never race with an in-flight render and stale state cannot colour audio
// after a later enable.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_bypass(int32_t bypass);
FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_get_bypass(void);

// Stores only the fallback rate used when a buffer carries none — the actual
// buffer's sample rate is authoritative and coefficients are rebuilt on the
// audio thread when it changes. Never builds coefficients here.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_sample_rate(int32_t sample_rate);

// Bumps a reset generation: every audio thread clears its own history on its
// next process() call. Safe to call concurrently with rendering.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_reset(void);

#ifdef __cplusplus
}
#endif
#endif  // NATIVE_AUDIO_RUNTIME_ACOUSTIC_ENGINE_PROCESSOR_H_
