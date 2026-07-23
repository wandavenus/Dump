// DSP Pipeline implementation — Phase 4 / Phase 4.5.
// See dsp_pipeline.h for the full contract.
//
// Phase 4.5 additions:
//   nar_dsp_pipeline_is_initialized() — atomic read of _initialized.
//   nar_dsp_pipeline_process_raw()    — stack-allocated NarAudioBuffer view so
//                                       JNI can call the pipeline without heap
//                                       allocation. Requires audio_buffer_internal.h
//                                       for the full struct layout.

#include "dsp_pipeline.h"

#include <stdatomic.h>
#include <string.h>

#include "audio_buffer_internal.h"      // full NarAudioBuffer layout for process_raw()
#include "dsp_stream.h"
#include "native_audio_runtime_internal.h"

#if defined(__ANDROID__)
#include <android/log.h>
#define NAR_DSP_TAG "NarDspPipeline"
#define NAR_DSP_LOG(...) \
  __android_log_print(ANDROID_LOG_DEBUG, NAR_DSP_TAG, __VA_ARGS__)
#else
#define NAR_DSP_LOG(...) ((void)0)
#endif

// ── Pipeline state ────────────────────────────────────────────────────────────

#define NAR_MAX_PIPELINE_PROCESSORS 16
#define NAR_PROCESSOR_ID_MAX_LEN    63

// One registered slot. The `enabled` flag is an atomic so set_enabled() can be
// called from a UI thread while process() is running on the audio thread.
typedef struct {
  char  id[NAR_PROCESSOR_ID_MAX_LEN + 1];
  void* self;
  const NarDspProcessorVTable* vtable;
  _Atomic int32_t enabled;  // 1 = enabled, 0 = disabled
} NarPipelineSlot;

static NarPipelineSlot  _slots[NAR_MAX_PIPELINE_PROCESSORS];
static _Atomic int32_t  _count       = 0;  // registered processor count
static _Atomic int32_t  _initialized = 0;  // 1 after init, 0 after dispose

// Guards _slots mutation (registration/disposal). The hot process/reset path
// only reads _count and per-slot atomics — it is lock-free by design.
#if defined(_WIN32)
#include <windows.h>
static CRITICAL_SECTION _lock;
static _Atomic int _lock_ready = 0;
static void _ensure_lock(void) {
  int expected = 0;
  if (atomic_compare_exchange_strong(&_lock_ready, &expected, 1))
    InitializeCriticalSection(&_lock);
}
static void _lock_acquire(void) { _ensure_lock(); EnterCriticalSection(&_lock); }
static void _lock_release(void) { LeaveCriticalSection(&_lock); }
#else
#include <pthread.h>
static pthread_mutex_t _lock = PTHREAD_MUTEX_INITIALIZER;
static void _lock_acquire(void) { pthread_mutex_lock(&_lock); }
static void _lock_release(void) { pthread_mutex_unlock(&_lock); }
#endif

// ── Lifecycle ────────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_init(void) {
  int32_t expected = 0;
  if (!atomic_compare_exchange_strong(&_initialized, &expected, 1)) {
    // Idempotent — already initialised.
    nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
    return NATIVE_RUNTIME_OK;
  }
  _lock_acquire();
  atomic_store(&_count, 0);
  memset(_slots, 0, sizeof(_slots));
  _lock_release();
  NAR_DSP_LOG("nar_dsp_pipeline_init: ok");
  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT void nar_dsp_pipeline_reset(void) {
  // NEW-02: Defensive guard — nar_dsp_pipeline_dispose() nulls all vtable
  // pointers before zeroing _count. If reset() were called between those two
  // atomic stores (structurally impossible in practice because ExoPlayer's
  // audio thread is stopped before onDestroy() calls dispose()), dereferencing
  // a null vtable would crash. The guard is purely defensive and cannot change
  // runtime behaviour when the pipeline is live (_initialized == 1).
  if (!atomic_load(&_initialized)) return;
  int32_t count = atomic_load(&_count);
  for (int32_t i = 0; i < count; i++) {
    _slots[i].vtable->reset(_slots[i].self);
  }
}

FFI_PLUGIN_EXPORT void nar_dsp_pipeline_dispose(void) {
  int32_t was_initialized = 1;
  if (!atomic_compare_exchange_strong(&_initialized, &was_initialized, 0)) {
    return;  // Already disposed — no-op.
  }
  _lock_acquire();
  {
    int32_t count = atomic_load(&_count);
    for (int32_t i = 0; i < count; i++) {
      _slots[i].vtable->dispose(_slots[i].self);
    }
    atomic_store(&_count, 0);
    memset(_slots, 0, sizeof(_slots));
  }
  _lock_release();
  NAR_DSP_LOG("nar_dsp_pipeline_dispose: ok");
}

// ── Registration ──────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_register_internal(
    const NarDspProcessorDescriptor* desc) {
  if (!atomic_load(&_initialized) || desc == NULL || desc->id == NULL ||
      desc->vtable == NULL) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT);
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }

  int32_t result = NATIVE_RUNTIME_OK;
  _lock_acquire();
  {
    int32_t count = atomic_load(&_count);

    // Reject duplicate ids.
    for (int32_t i = 0; i < count; i++) {
      if (strncmp(_slots[i].id, desc->id, NAR_PROCESSOR_ID_MAX_LEN) == 0) {
        result = NATIVE_RUNTIME_ERROR_DUPLICATE_MODULE;
        goto done;
      }
    }

    if (count >= NAR_MAX_PIPELINE_PROCESSORS) {
      result = NATIVE_RUNTIME_ERROR_MODULE_LIMIT_REACHED;
      goto done;
    }

    // Call the processor's own init. A non-OK result aborts registration.
    result = desc->vtable->init(desc->self);
    if (result != NATIVE_RUNTIME_OK) goto done;

    // Commit to the slot.
    strncpy(_slots[count].id, desc->id, NAR_PROCESSOR_ID_MAX_LEN);
    _slots[count].id[NAR_PROCESSOR_ID_MAX_LEN] = '\0';
    _slots[count].self   = desc->self;
    _slots[count].vtable = desc->vtable;
    atomic_store(&_slots[count].enabled, 1);  // processors start enabled
    atomic_store(&_count, count + 1);

    NAR_DSP_LOG("nar_dsp_pipeline_register_internal: %s", desc->id);
  }
done:
  _lock_release();
  nar_runtime_set_last_status(result);
  return result;
}

// ── Processing ───────────────────────────────────────────────────────────────

// Production-hardening pass: the chain no longer aborts on a processor's
// non-OK return. Every processor still runs its process() call even if an
// earlier one failed — this is what guarantees the limiter/soft-clipper
// (registered last) always execute as the final safety net. Only the FIRST
// non-OK code is remembered/returned, for diagnostics.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_process_stream(
    NarAudioBuffer* buffer, int32_t stream_slot) {
  if (buffer == NULL) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT);
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  // FIX NAR-2: defensive _initialized guard. nar_dsp_pipeline_dispose()
  // sets _initialized=0 BEFORE zeroing vtable pointers. Checking here
  // (in addition to the existing check in process_raw_stream()) ensures
  // that if the audio thread slips past the outer guard and enters this
  // function after dispose() has started, it fails-open instead of
  // dereferencing a zeroed vtable pointer. In practice the architectural
  // invariant (ExoPlayer audio thread stopped before dispose is called)
  // prevents this scenario, but the explicit check makes it crash-safe
  // even if that invariant is ever violated by a future refactor.
  if (!atomic_load(&_initialized)) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_NOT_INITIALIZED);
    return NATIVE_RUNTIME_ERROR_NOT_INITIALIZED;
  }
  const int32_t slot = nar_dsp_clamp_stream(stream_slot);
  int32_t count = atomic_load(&_count);
  int32_t first_error = NATIVE_RUNTIME_OK;
  for (int32_t i = 0; i < count; i++) {
    if (!atomic_load(&_slots[i].enabled)) continue;  // skip disabled
    int32_t r = _slots[i].vtable->process(_slots[i].self, buffer, slot);
    if (r != NATIVE_RUNTIME_OK && first_error == NATIVE_RUNTIME_OK) {
      first_error = r;  // remember the first failure but keep going —
                         // a single failing effect must never skip the
                         // limiter/soft-clipper safety net further down
                         // the chain.
    }
  }
  nar_runtime_set_last_status(first_error);
  return first_error;
}

FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_process(NarAudioBuffer* buffer) {
  return nar_dsp_pipeline_process_stream(buffer, 0);
}

// ── Enable / disable ─────────────────────────────────────────────────────────

// Returns slot index, or -1 if not found. Lock-free (reads atomic count).
static int32_t _find_slot(const char* id) {
  int32_t count = atomic_load(&_count);
  for (int32_t i = 0; i < count; i++) {
    if (strncmp(_slots[i].id, id, NAR_PROCESSOR_ID_MAX_LEN) == 0) return i;
  }
  return -1;
}

FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_set_enabled(
    const char* id, int32_t enabled) {
  if (id == NULL) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT);
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  int32_t idx = _find_slot(id);
  if (idx < 0) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT);
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  atomic_store(&_slots[idx].enabled, enabled ? 1 : 0);
  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_is_enabled(const char* id) {
  if (id == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  int32_t idx = _find_slot(id);
  if (idx < 0) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  return atomic_load(&_slots[idx].enabled);
}

// ── Metadata ─────────────────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_total_latency_frames(void) {
  int32_t total = 0;
  int32_t count = atomic_load(&_count);
  for (int32_t i = 0; i < count; i++) {
    total += _slots[i].vtable->latency_frames(_slots[i].self);
  }
  return total;
}

FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_processor_count(void) {
  return atomic_load(&_count);
}

FFI_PLUGIN_EXPORT const char* nar_dsp_pipeline_processor_id_at(int32_t index) {
  if (index < 0 || index >= atomic_load(&_count)) return NULL;
  return _slots[index].id;
}

// ── Phase 4.5 additions ───────────────────────────────────────────────────────

FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_is_initialized(void) {
  return atomic_load(&_initialized);
}

// Process a raw interleaved float32 buffer in-place without any heap allocation.
// Constructs a stack-local NarAudioBuffer VIEW (no owned data) and routes it
// through the existing process() call. The view is zero-copy: `data` is the
// same pointer ExoPlayer passes us via JNI GetDirectBufferAddress().
//
// Called from NativeDspAudioProcessor.kt on EACH ExoPlayer instance's own
// audio rendering thread — one call site per stream (primary vs
// secondary/crossfade-standby), each passing its own stream_slot. Thread
// safety is identical to nar_dsp_pipeline_process_stream(): no locks, no
// alloc; two different stream_slots may call in concurrently from two
// different OS threads with zero shared mutable per-stream state.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_process_raw_stream(
    float* data, int32_t frame_count, int32_t channel_count,
    int32_t sample_rate, int32_t stream_slot) {
  if (!atomic_load(&_initialized)) {
    // Pipeline not yet initialised by Dart — fail-open (audio passes unchanged).
    return NATIVE_RUNTIME_ERROR_NOT_INITIALIZED;
  }
  if (data == NULL || frame_count <= 0 || channel_count <= 0) {
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }

  // Stack-allocate a view NarAudioBuffer. audio_buffer_internal.h gives us the
  // full struct layout; we do NOT call nar_audio_buffer_create() (heap) here.
  // IMPORTANT: nar_audio_buffer_destroy() must NEVER be called on this struct.
  struct NarAudioBuffer view;
  view.data             = data;
  view.capacity_frames  = frame_count;
  view.frame_count      = frame_count;
  view.channel_count    = channel_count;
  view.sample_rate      = sample_rate;
  view.format           = NAR_SAMPLE_FORMAT_FLOAT32;
  view.timestamp_us     = 0;

  return nar_dsp_pipeline_process_stream(&view, stream_slot);
}

// Legacy single-stream entry point — always targets stream slot 0.
FFI_PLUGIN_EXPORT int32_t nar_dsp_pipeline_process_raw(
    float* data, int32_t frame_count, int32_t channel_count, int32_t sample_rate) {
  return nar_dsp_pipeline_process_raw_stream(
      data, frame_count, channel_count, sample_rate, 0);
}
