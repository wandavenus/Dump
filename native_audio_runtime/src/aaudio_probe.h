// AAudio capability probe — diagnostic only, not part of the DSP pipeline.
//
// Answers a single question that cannot be answered from static device
// info: when this app actually asks for an AAudio stream in
// SHARING_MODE_EXCLUSIVE + PERFORMANCE_MODE_LOW_LATENCY, what sharing mode
// does the OS/HAL actually grant? AAudio silently downgrades to SHARED (or a
// different performance mode) when the vendor HAL/OEM policy doesn't honor
// the request — there is no public "is exclusive mode supported" query,
// only "open a stream and see what you got".
//
// Implementation note: this probe does NOT link against libaaudio.so at
// build time (no `#include <aaudio/AAudio.h>`, no `-laaudio`). It dlopen()s
// libaaudio.so and dlsym()s each entry point at runtime instead, because
// this project's build environment cannot verify NDK header availability
// (see NATIVE_RUNTIME.md). The numeric enum values and function signatures
// below mirror AAudio's frozen public C ABI (stable since API 26); a
// mismatch fails the probe closed (reports unavailable) rather than
// crashing.

#ifndef NATIVE_AUDIO_RUNTIME_AAUDIO_PROBE_H_
#define NATIVE_AUDIO_RUNTIME_AAUDIO_PROBE_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Result codes for native_runtime_aaudio_probe(), distinct from
// NativeRuntimeStatus since this is a standalone diagnostic, not a pipeline
// module.
typedef enum {
  NAR_AAUDIO_PROBE_OK = 0,
  NAR_AAUDIO_PROBE_UNSUPPORTED_PLATFORM = -100,  // not Android
  NAR_AAUDIO_PROBE_LIBRARY_NOT_FOUND = -101,     // libaaudio.so missing (< API 26)
  NAR_AAUDIO_PROBE_SYMBOL_MISSING = -102,        // ABI mismatch
  NAR_AAUDIO_PROBE_BUILDER_FAILED = -103,        // AAudio_createStreamBuilder failed
  NAR_AAUDIO_PROBE_OPEN_FAILED = -104,           // openStream failed/denied
} NarAAudioProbeResult;

// Opens a real AAudio output stream requesting SHARING_MODE_EXCLUSIVE +
// PERFORMANCE_MODE_LOW_LATENCY, reads back what was actually granted, then
// closes it immediately. Safe to call repeatedly; each call is a fresh probe.
// Returns a NarAAudioProbeResult. On NAR_AAUDIO_PROBE_OK, query the actual
// granted modes via native_runtime_aaudio_last_sharing_mode() /
// native_runtime_aaudio_last_performance_mode().
FFI_PLUGIN_EXPORT int32_t native_runtime_aaudio_probe(void);

// Sharing mode actually granted by the last probe (0 = EXCLUSIVE,
// 1 = SHARED), or -1 if the last probe did not reach a successful open.
FFI_PLUGIN_EXPORT int32_t native_runtime_aaudio_last_sharing_mode(void);

// Performance mode actually granted by the last probe (10 = NONE,
// 11 = POWER_SAVING, 12 = LOW_LATENCY), or -1 if unavailable.
FFI_PLUGIN_EXPORT int32_t native_runtime_aaudio_last_performance_mode(void);

// Human-readable detail for the last probe (error detail, or empty string
// on success). Owned by the native layer — do not free.
FFI_PLUGIN_EXPORT const char* native_runtime_aaudio_last_error(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_AAUDIO_PROBE_H_
