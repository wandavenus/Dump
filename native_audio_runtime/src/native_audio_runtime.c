// native_audio_runtime — Phase 3 native runtime foundation (implementation).
//
// Pure lifecycle/version/capability/registry bookkeeping. No DSP, no
// FFmpeg, no audio processing — see native_audio_runtime.h for the contract.

#include "native_audio_runtime.h"
#include "native_audio_runtime_internal.h"

#include <stdatomic.h>
#include <string.h>

#if defined(__ANDROID__)
#include <android/log.h>
#define NAR_LOG_TAG "NativeAudioRuntime"
#define NAR_LOG(...) __android_log_print(ANDROID_LOG_DEBUG, NAR_LOG_TAG, __VA_ARGS__)
#else
#include <stdio.h>
#define NAR_LOG(...) ((void)0)  // No noisy stdout/stderr logging off-device.
#endif

// ── Runtime state ────────────────────────────────────────────────────────────
//
// `_state` is the single source of truth for whether the runtime is usable.
// It is an atomic so init/dispose/is_initialized never race regardless of
// which thread calls them — required by the Phase 3 thread-safety mandate.
typedef enum {
  NAR_STATE_UNINITIALIZED = 0,
  NAR_STATE_INITIALIZING = 1,
  NAR_STATE_INITIALIZED = 2,
  NAR_STATE_DISPOSED = 3,
} NarState;

static _Atomic NarState _state = NAR_STATE_UNINITIALIZED;
static _Atomic int32_t _last_status = NATIVE_RUNTIME_OK;

static const char* const kVersion = "0.1.0-phase8";

// ── Capability table ─────────────────────────────────────────────────────────
//
// Phase 4: dsp.pipeline and dsp.gain are now supported (the DSP processing
// architecture is implemented and the gain processor validates the chain).
// All other entries remain placeholders (supported = 0) until those modules
// are implemented.
typedef struct {
  const char* key;
  int32_t     supported;  // 1 = available, 0 = placeholder
} NarCapabilityEntry;

static const NarCapabilityEntry kCapabilities[] = {
    {"dsp.pipeline",          1},  // Phase 4:   DSP pipeline architecture
    {"dsp.gain",              1},  // Phase 4:   gain processor
    {"dsp.media3_integration",1},  // Phase 4.5: NativeDspAudioProcessor in ExoPlayer chain
    {"dsp.equalizer",         1},  // Phase 5:   parametric EQ (biquad, 32-band)
    {"dsp.compressor",        1},  // Phase 6:   feed-forward soft-knee compressor
    {"dsp.crossfeed",         1},  // Phase 7:   frequency-dependent headphone crossfeed
    {"dsp.limiter",           1},  // Phase 6:   look-ahead brickwall limiter
    {"dsp.soft_clipper",      1},  // Phase 6:   tanh soft clipper
    {"dsp.replaygain",        1},  // Phase 8:   metadata-driven ReplayGain gain stage
    {"dsp.bass_boost",        0},
    {"dsp.virtualizer",       0},
    {"dsp.resampler",         0},
    {"decoder.flac_hires",    0},
    {"decoder.dsd",           0},
    {"scan.loudness_ebur128",  0},
};
static const int32_t kCapabilityCount =
    (int32_t)(sizeof(kCapabilities) / sizeof(kCapabilities[0]));

// ── Module registry (fixed-size, native-side ledger) ────────────────────────

#define NAR_MAX_MODULES 16
#define NAR_MODULE_ID_MAX_LEN 63

static char _module_ids[NAR_MAX_MODULES][NAR_MODULE_ID_MAX_LEN + 1];
static _Atomic int32_t _module_count = 0;

// Guards the module table only. The hot lifecycle path (init/dispose) uses
// the lock-free `_state` atomic above; this mutex protects the small,
// infrequently-touched registration list from concurrent registrations.
#if defined(_WIN32)
#include <windows.h>
static CRITICAL_SECTION _module_lock;
static _Atomic int _module_lock_ready = 0;
static void nar_ensure_lock(void) {
  int expected = 0;
  if (atomic_compare_exchange_strong(&_module_lock_ready, &expected, 1)) {
    InitializeCriticalSection(&_module_lock);
  }
}
static void nar_lock(void) { nar_ensure_lock(); EnterCriticalSection(&_module_lock); }
static void nar_unlock(void) { LeaveCriticalSection(&_module_lock); }
#else
#include <pthread.h>
static pthread_mutex_t _module_lock = PTHREAD_MUTEX_INITIALIZER;
static void nar_lock(void) { pthread_mutex_lock(&_module_lock); }
static void nar_unlock(void) { pthread_mutex_unlock(&_module_lock); }
#endif

// Defined here to match the extern declaration in
// native_audio_runtime_internal.h — every other translation unit in this
// library links against this exact symbol name. It must NOT be `static`;
// doing so silently drops it from the shared library's dynamic symbol
// table, leaving every other .c file's call to `nar_runtime_set_last_status`
// unresolved at dlopen() time (matches the header's "defined once" contract).
void nar_runtime_set_last_status(int32_t status) {
  atomic_store(&_last_status, status);
}

// ── Lifecycle ────────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t native_runtime_init(void) {
  // Re-initialization after a prior dispose() must succeed (DISPOSED ->
  // INITIALIZING is a valid transition), not just the first-ever
  // UNINITIALIZED -> INITIALIZING path. Loop the CAS so concurrent callers
  // racing from either starting state still get exactly one winner.
  for (;;) {
    NarState current = atomic_load(&_state);
    if (current == NAR_STATE_INITIALIZED || current == NAR_STATE_INITIALIZING) {
      nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_ALREADY_INITIALIZED);
      return NATIVE_RUNTIME_ERROR_ALREADY_INITIALIZED;
    }
    // current is UNINITIALIZED or DISPOSED — try to claim it.
    if (atomic_compare_exchange_weak(&_state, &current, NAR_STATE_INITIALIZING)) {
      break;
    }
    // Lost the race to another thread; re-read state and retry.
  }

  // Real setup goes here in future phases (e.g. opening a shared audio
  // graph context). Phase 3 has nothing to allocate.
  atomic_store(&_module_count, 0);

  atomic_store(&_state, NAR_STATE_INITIALIZED);
  NAR_LOG("native_runtime_init: ok (version=%s)", kVersion);
  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT int32_t native_runtime_dispose(void) {
  NarState prev = atomic_exchange(&_state, NAR_STATE_DISPOSED);
  if (prev != NAR_STATE_INITIALIZED) {
    // Disposing when never initialized (or already disposed) is a safe
    // no-op per the header contract, but still report what happened.
    nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
    return NATIVE_RUNTIME_OK;
  }

  nar_lock();
  atomic_store(&_module_count, 0);
  memset(_module_ids, 0, sizeof(_module_ids));
  nar_unlock();

  NAR_LOG("native_runtime_dispose: ok");
  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT int32_t native_runtime_is_initialized(void) {
  return atomic_load(&_state) == NAR_STATE_INITIALIZED ? 1 : 0;
}

// ── Version / capability reporting ──────────────────────────────────────────

FFI_PLUGIN_EXPORT const char* native_runtime_get_version(void) {
  return kVersion;
}

FFI_PLUGIN_EXPORT int32_t native_runtime_capability_count(void) {
  return kCapabilityCount;
}

FFI_PLUGIN_EXPORT const char* native_runtime_capability_key(int32_t index) {
  if (index < 0 || index >= kCapabilityCount) return NULL;
  return kCapabilities[index].key;
}

FFI_PLUGIN_EXPORT int32_t native_runtime_capability_supported(int32_t index) {
  if (index < 0 || index >= kCapabilityCount) return 0;
  return kCapabilities[index].supported;
}

// ── Module registry ──────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t native_runtime_register_module(const char* module_id) {
  if (atomic_load(&_state) != NAR_STATE_INITIALIZED) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_NOT_INITIALIZED);
    return NATIVE_RUNTIME_ERROR_NOT_INITIALIZED;
  }
  if (module_id == NULL || module_id[0] == '\0') {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT);
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  /* Reject IDs longer than the storage limit to prevent silent truncation
   * and prefix collisions (e.g. "abc...63" vs "abc...63_extra" would match
   * with strncmp if we silently stored only the first 63 chars). */
  if (strlen(module_id) > NAR_MODULE_ID_MAX_LEN) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT);
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }

  int32_t result = NATIVE_RUNTIME_OK;
  nar_lock();
  {
    int32_t count = atomic_load(&_module_count);
    for (int32_t i = 0; i < count; i++) {
      if (strcmp(_module_ids[i], module_id) == 0) {
        result = NATIVE_RUNTIME_ERROR_DUPLICATE_MODULE;
        break;
      }
    }
    if (result == NATIVE_RUNTIME_OK) {
      if (count >= NAR_MAX_MODULES) {
        result = NATIVE_RUNTIME_ERROR_MODULE_LIMIT_REACHED;
      } else {
        strncpy(_module_ids[count], module_id, NAR_MODULE_ID_MAX_LEN);
        _module_ids[count][NAR_MODULE_ID_MAX_LEN] = '\0';
        atomic_store(&_module_count, count + 1);
        NAR_LOG("native_runtime_register_module: %s", module_id);
      }
    }
  }
  nar_unlock();

  nar_runtime_set_last_status(result);
  return result;
}

FFI_PLUGIN_EXPORT int32_t native_runtime_module_count(void) {
  return atomic_load(&_module_count);
}

FFI_PLUGIN_EXPORT const char* native_runtime_module_id_at(int32_t index) {
  if (index < 0 || index >= atomic_load(&_module_count)) return NULL;
  return _module_ids[index];
}

// ── Error reporting ──────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t native_runtime_last_status(void) {
  return atomic_load(&_last_status);
}
