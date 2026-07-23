// AAudio capability probe — implementation. See aaudio_probe.h for the
// rationale (runtime dlopen/dlsym against libaaudio.so, no build-time link).

#include "aaudio_probe.h"

#include <stdio.h>
#include <string.h>

#if defined(__ANDROID__)
#include <android/log.h>
#include <dlfcn.h>
#define AAP_LOG_TAG "AAudioProbe"
#define AAP_LOG(...) __android_log_print(ANDROID_LOG_DEBUG, AAP_LOG_TAG, __VA_ARGS__)
#else
#define AAP_LOG(...) ((void)0)
#endif

// ── Minimal AAudio ABI mirror (frozen public C ABI since API 26) ───────────

typedef struct AAudioStreamBuilderStruct AAudioStreamBuilder;
typedef struct AAudioStreamStruct AAudioStream;
typedef int32_t aaudio_result_t;

#define NAR_AAUDIO_SHARING_MODE_EXCLUSIVE 0
#define NAR_AAUDIO_PERFORMANCE_MODE_LOW_LATENCY 12
#define NAR_AAUDIO_DIRECTION_OUTPUT 0
#define NAR_AAUDIO_FORMAT_PCM_I16 1

typedef aaudio_result_t (*FnCreateBuilder)(AAudioStreamBuilder**);
typedef void (*FnBuilderSetPerformanceMode)(AAudioStreamBuilder*, int32_t);
typedef void (*FnBuilderSetSharingMode)(AAudioStreamBuilder*, int32_t);
typedef void (*FnBuilderSetDirection)(AAudioStreamBuilder*, int32_t);
typedef void (*FnBuilderSetFormat)(AAudioStreamBuilder*, int32_t);
typedef void (*FnBuilderSetChannelCount)(AAudioStreamBuilder*, int32_t);
typedef aaudio_result_t (*FnBuilderOpenStream)(AAudioStreamBuilder*, AAudioStream**);
typedef aaudio_result_t (*FnBuilderDelete)(AAudioStreamBuilder*);
typedef int32_t (*FnStreamGetSharingMode)(AAudioStream*);
typedef int32_t (*FnStreamGetPerformanceMode)(AAudioStream*);
typedef aaudio_result_t (*FnStreamClose)(AAudioStream*);
typedef const char* (*FnResultToText)(aaudio_result_t);

// ── Last-probe state (single global, matches this diagnostic's "one probe
// at a time from the debug page" usage — not part of the audio hot path). ──

static int32_t _last_sharing_mode = -1;
static int32_t _last_performance_mode = -1;
static char _last_error[160] = "";

static void nar_aaudio_set_error(const char* msg) {
  strncpy(_last_error, msg, sizeof(_last_error) - 1);
  _last_error[sizeof(_last_error) - 1] = '\0';
}

FFI_PLUGIN_EXPORT int32_t native_runtime_aaudio_probe(void) {
  _last_sharing_mode = -1;
  _last_performance_mode = -1;
  _last_error[0] = '\0';

#if !defined(__ANDROID__)
  nar_aaudio_set_error("AAudio hanya tersedia di Android");
  return NAR_AAUDIO_PROBE_UNSUPPORTED_PLATFORM;
#else
  void* handle = dlopen("libaaudio.so", RTLD_NOW);
  if (handle == NULL) {
    nar_aaudio_set_error("libaaudio.so tidak ditemukan (perlu Android 8.1+)");
    return NAR_AAUDIO_PROBE_LIBRARY_NOT_FOUND;
  }

  FnCreateBuilder create_builder =
      (FnCreateBuilder)dlsym(handle, "AAudio_createStreamBuilder");
  FnBuilderSetPerformanceMode set_perf =
      (FnBuilderSetPerformanceMode)dlsym(handle, "AAudioStreamBuilder_setPerformanceMode");
  FnBuilderSetSharingMode set_sharing =
      (FnBuilderSetSharingMode)dlsym(handle, "AAudioStreamBuilder_setSharingMode");
  FnBuilderSetDirection set_direction =
      (FnBuilderSetDirection)dlsym(handle, "AAudioStreamBuilder_setDirection");
  FnBuilderSetFormat set_format =
      (FnBuilderSetFormat)dlsym(handle, "AAudioStreamBuilder_setFormat");
  FnBuilderSetChannelCount set_channels =
      (FnBuilderSetChannelCount)dlsym(handle, "AAudioStreamBuilder_setChannelCount");
  FnBuilderOpenStream open_stream =
      (FnBuilderOpenStream)dlsym(handle, "AAudioStreamBuilder_openStream");
  FnBuilderDelete delete_builder =
      (FnBuilderDelete)dlsym(handle, "AAudioStreamBuilder_delete");
  FnStreamGetSharingMode get_sharing =
      (FnStreamGetSharingMode)dlsym(handle, "AAudioStream_getSharingMode");
  FnStreamGetPerformanceMode get_perf =
      (FnStreamGetPerformanceMode)dlsym(handle, "AAudioStream_getPerformanceMode");
  FnStreamClose stream_close =
      (FnStreamClose)dlsym(handle, "AAudioStream_close");
  FnResultToText result_to_text =
      (FnResultToText)dlsym(handle, "AAudio_convertResultToText");

  if (!create_builder || !set_perf || !set_sharing || !set_direction ||
      !set_format || !set_channels || !open_stream || !delete_builder ||
      !get_sharing || !get_perf || !stream_close) {
    nar_aaudio_set_error("Simbol AAudio tidak cocok di perangkat ini");
    dlclose(handle);
    return NAR_AAUDIO_PROBE_SYMBOL_MISSING;
  }

  AAudioStreamBuilder* builder = NULL;
  aaudio_result_t rc = create_builder(&builder);
  if (rc != 0 || builder == NULL) {
    nar_aaudio_set_error("Gagal membuat AAudioStreamBuilder");
    dlclose(handle);
    return NAR_AAUDIO_PROBE_BUILDER_FAILED;
  }

  set_direction(builder, NAR_AAUDIO_DIRECTION_OUTPUT);
  set_format(builder, NAR_AAUDIO_FORMAT_PCM_I16);
  set_channels(builder, 2);
  set_perf(builder, NAR_AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
  set_sharing(builder, NAR_AAUDIO_SHARING_MODE_EXCLUSIVE);

  AAudioStream* stream = NULL;
  rc = open_stream(builder, &stream);
  delete_builder(builder);

  if (rc != 0 || stream == NULL) {
    const char* text = result_to_text ? result_to_text(rc) : NULL;
    char buf[160];
    snprintf(buf, sizeof(buf), "openStream gagal: %s",
             text ? text : "unknown error");
    nar_aaudio_set_error(buf);
    dlclose(handle);
    return NAR_AAUDIO_PROBE_OPEN_FAILED;
  }

  _last_sharing_mode = get_sharing(stream);
  _last_performance_mode = get_perf(stream);

  stream_close(stream);
  dlclose(handle);

  AAP_LOG("probe ok: sharing=%d performance=%d", _last_sharing_mode,
          _last_performance_mode);
  return NAR_AAUDIO_PROBE_OK;
#endif
}

FFI_PLUGIN_EXPORT int32_t native_runtime_aaudio_last_sharing_mode(void) {
  return _last_sharing_mode;
}

FFI_PLUGIN_EXPORT int32_t native_runtime_aaudio_last_performance_mode(void) {
  return _last_performance_mode;
}

FFI_PLUGIN_EXPORT const char* native_runtime_aaudio_last_error(void) {
  return _last_error;
}
