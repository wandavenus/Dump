// Acoustic Engine — speaker-oriented perceptual enhancement processor.
#ifndef NATIVE_AUDIO_RUNTIME_ACOUSTIC_ENGINE_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_ACOUSTIC_ENGINE_PROCESSOR_H_

#include <stdint.h>
#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Registers "dsp.acoustic_engine" after loudness and before compressor.
FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_processor_register_internal(void);

// Intensity is a single user-facing control in [0, 100]. Updates are lock-free.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_intensity(float intensity);
FFI_PLUGIN_EXPORT float nar_acoustic_engine_get_intensity(void);

// A bypass is sample-transparent and resets all stream histories on transition.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_bypass(int32_t bypass);
FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_get_bypass(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_ACOUSTIC_ENGINE_PROCESSOR_H_
