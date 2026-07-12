// native_audio_runtime — Phase 3 native runtime foundation.
//
// This header defines the ONLY public C surface of the native runtime.
// It intentionally contains no DSP, no FFmpeg, and no audio processing code.
// It exists to give future native modules (DSP, FFmpeg, FFT, ReplayGain,
// Visualizer, Resampler, ...) a single, thread-safe place to initialize,
// report capabilities, and register themselves — without requiring any
// changes to the Dart-side PlaybackManager.
//
// Threading contract:
//   - native_runtime_init() may be called from any thread. Concurrent calls
//     are safe: exactly one caller performs the real initialization, all
//     others observe NATIVE_RUNTIME_ERROR_ALREADY_INITIALIZED.
//   - native_runtime_dispose() is safe to call even if init was never called,
//     or after a previous dispose (idempotent no-op).
//   - native_runtime_register_module() is safe to call concurrently from
//     multiple threads; duplicate module ids are rejected.
//
// Extension point for future modules:
//   Real modules (DSP, FFmpeg, ...) will add their OWN header/source files
//   and their OWN native_<module>_init()/dispose() functions. They will call
//   native_runtime_register_module("<module_id>") during their own init to
//   announce themselves, but this file itself never grows module-specific
//   APIs — see NATIVE_RUNTIME.md for the extension mechanism.

#ifndef NATIVE_AUDIO_RUNTIME_H_
#define NATIVE_AUDIO_RUNTIME_H_

#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ── Error / status codes ────────────────────────────────────────────────────
//
// Every function that can fail returns one of these as an int32_t so Dart can
// surface a meaningful, typed exception instead of guessing from a bool.
typedef enum {
  NATIVE_RUNTIME_OK = 0,
  NATIVE_RUNTIME_ERROR_ALREADY_INITIALIZED = 1,
  NATIVE_RUNTIME_ERROR_NOT_INITIALIZED = 2,
  NATIVE_RUNTIME_ERROR_UNSUPPORTED_PLATFORM = 3,
  NATIVE_RUNTIME_ERROR_DUPLICATE_MODULE = 4,
  NATIVE_RUNTIME_ERROR_MODULE_LIMIT_REACHED = 5,
  NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT = 6,
  NATIVE_RUNTIME_ERROR_ALLOCATION_FAILED = 7,
} NativeRuntimeStatus;

// ── Lifecycle ────────────────────────────────────────────────────────────────

// Initialize the native runtime. Idempotent and thread-safe: the first
// caller wins and performs real setup; subsequent callers get
// NATIVE_RUNTIME_ERROR_ALREADY_INITIALIZED without side effects.
FFI_PLUGIN_EXPORT int32_t native_runtime_init(void);

// Tear down the native runtime and clear the module registry. Safe to call
// multiple times or without a prior init (no-op in that case).
FFI_PLUGIN_EXPORT int32_t native_runtime_dispose(void);

// Returns 1 if native_runtime_init() has completed successfully and
// native_runtime_dispose() has not since been called, 0 otherwise.
FFI_PLUGIN_EXPORT int32_t native_runtime_is_initialized(void);

// ── Version / capability reporting ──────────────────────────────────────────

// Static, human-readable runtime version string. Owned by the runtime —
// callers must NOT free it.
FFI_PLUGIN_EXPORT const char* native_runtime_get_version(void);

// Number of capability entries currently known to the runtime. Phase 3 ships
// zero real capabilities (no DSP / FFmpeg exist yet) — this reports the
// placeholder set only, all unsupported, so future modules have a stable
// query surface to extend.
FFI_PLUGIN_EXPORT int32_t native_runtime_capability_count(void);

// Dot-separated capability key at `index` (e.g. "dsp.equalizer"). Returns
// NULL if index is out of range. Owned by the runtime — do not free.
FFI_PLUGIN_EXPORT const char* native_runtime_capability_key(int32_t index);

// Whether the capability at `index` is currently supported (1) or not (0).
// Returns 0 for an out-of-range index.
FFI_PLUGIN_EXPORT int32_t native_runtime_capability_supported(int32_t index);

// ── Module registry ──────────────────────────────────────────────────────────
//
// A lightweight, native-side ledger of which logical modules (by string id)
// have announced themselves to the runtime. Real per-module behavior lives
// in each module's own bridge/source files, never here.

// Register a module id with the runtime. Returns NATIVE_RUNTIME_OK on
// success, NATIVE_RUNTIME_ERROR_NOT_INITIALIZED if called before init,
// NATIVE_RUNTIME_ERROR_DUPLICATE_MODULE if already registered, or
// NATIVE_RUNTIME_ERROR_MODULE_LIMIT_REACHED if the fixed-size table is full.
FFI_PLUGIN_EXPORT int32_t native_runtime_register_module(const char* module_id);

// Number of modules currently registered.
FFI_PLUGIN_EXPORT int32_t native_runtime_module_count(void);

// Module id at `index` in registration order. Returns NULL if out of range.
// Owned by the runtime — do not free.
FFI_PLUGIN_EXPORT const char* native_runtime_module_id_at(int32_t index);

// ── Error reporting ──────────────────────────────────────────────────────────

// Status code of the most recent call made from the current process
// (not per-thread — the runtime is a single global singleton by design).
FFI_PLUGIN_EXPORT int32_t native_runtime_last_status(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_H_
