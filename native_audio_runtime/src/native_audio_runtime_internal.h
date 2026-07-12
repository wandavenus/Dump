// Internal-only shared declarations used ACROSS the native runtime's own
// source files (native_audio_runtime.c, audio_buffer.c, dsp_pipeline.c,
// gain_processor.c). Never exported via FFI_PLUGIN_EXPORT, never part of
// the public header (native_audio_runtime.h) — Dart never sees this file.

#ifndef NATIVE_AUDIO_RUNTIME_INTERNAL_H_
#define NATIVE_AUDIO_RUNTIME_INTERNAL_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Record the status code of the most recent call, readable from Dart via
// native_runtime_last_status(). Defined once in native_audio_runtime.c;
// every other translation unit in this library calls this instead of
// keeping its own copy of "last status" so there is a single source of
// truth process-wide, matching the header's documented contract.
void nar_runtime_set_last_status(int32_t status);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_INTERNAL_H_
