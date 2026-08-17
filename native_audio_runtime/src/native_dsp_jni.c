// JNI bridge — NativeDspAudioProcessor.kt → native DSP pipeline.
//
// This translation unit is compiled into libnative_audio_runtime.so alongside
// the rest of the native runtime. The same .so is used by both Dart FFI and
// Kotlin JNI in the same process:
//
//   Dart:   DynamicLibrary.open("libnative_audio_runtime.so")
//   Kotlin: System.loadLibrary("native_audio_runtime")
//
// Both calls resolve to the same dlopen() handle (Android's linker deduplicates
// by name), so all C global/static state — including _initialized, _pipeline
// slots, and gain atomic knobs — is SHARED between the two callers.
//
// Ownership model:
//   Dart  — owns lifecycle: nar_dsp_pipeline_init(), nar_gain_processor_register_internal(),
//            all parameter control (set_gain_db, set_bypass, set_enabled), and dispose()
//            (pipeline teardown via NativeDspPipeline.dispose(); the runtime-level
//            native_runtime_dispose() is owned by NativeAudioRuntime.dispose() and is
//            never called concurrently with pipeline processing).
//   Kotlin — calls nar_dsp_pipeline_process_raw() on ExoPlayer's audio thread ONLY.
//
// Thread safety:
//   nativeProcessFloat() is called on ExoPlayer's audio rendering thread.
//   nar_dsp_pipeline_process_raw() acquires no locks and makes no heap allocations
//   — safe to call concurrently with Dart's atomic-based parameter writes.

#include <jni.h>
#include <stdint.h>
#include <stddef.h>

#include "dsp_pipeline.h"
#include "native_audio_runtime.h"
#include "gain_processor.h"
#include "replaygain_processor.h"
#include "crossfeed_processor.h"
#include "comp_processor.h"
#include "loudness_processor.h"
#include "soft_clipper_processor.h"
#include "limiter_processor.h"

// Java class: dev.wndavenz.music.effects.NativeDspAudioProcessor
JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_NativeDspAudioProcessor_nativeInitializeRuntime(
    JNIEnv* env, jclass clazz) {
  (void)env;
  (void)clazz;
  int32_t status = native_runtime_init();
  if (status != NATIVE_RUNTIME_OK && status != NATIVE_RUNTIME_ERROR_ALREADY_INITIALIZED) {
    return (jint)status;
  }
  status = nar_dsp_pipeline_init();
  if (status != NATIVE_RUNTIME_OK) {
    return (jint)status;
  }
  nar_gain_processor_register_internal();
  nar_replaygain_processor_register_internal();
  nar_crossfeed_processor_register_internal();
  nar_comp_processor_register_internal();
  nar_loudness_processor_register_internal();
  nar_soft_clipper_processor_register_internal();
  nar_limiter_processor_register_internal();
  return (jint)NATIVE_RUNTIME_OK;
}

// JNI name mangling: '.' → '_', no underscores in any component.

// Process frame_count * channel_count float32 samples in `buffer` in-place,
// for the given `stream_slot` (production-hardening pass — see
// dsp_stream.h). Each NativeDspAudioProcessor instance is constructed with
// its own fixed streamSlot (0 = primary ExoPlayer, 1 = secondary/
// crossfade-standby ExoPlayer) and passes it on every call, so the two
// concurrently-playing streams' envelope followers / delay lines / filter
// histories never collide inside the native pipeline.
//
// `buffer` must be a direct java.nio.ByteBuffer positioned at offset 0 of the
// PCM data. Returns NATIVE_RUNTIME_OK (0) on success. Returns
// NATIVE_RUNTIME_ERROR_NOT_INITIALIZED (2) if the pipeline is not ready yet —
// callers must treat non-OK as pass-through (buffer unchanged).
JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_NativeDspAudioProcessor_nativeProcessFloat(
    JNIEnv* env, jclass clazz,
    jobject buffer,
    jint    frame_count,
    jint    channel_count,
    jint    sample_rate,
    jint    stream_slot) {
  (void)clazz;
  if (buffer == NULL) {
    return (jint)NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  if (frame_count <= 0 || channel_count <= 0 || sample_rate <= 0) {
    return (jint)NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  const int64_t required_bytes =
      (int64_t)frame_count * (int64_t)channel_count * (int64_t)sizeof(float);
  if (required_bytes <= 0) {
    return (jint)NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  const jlong capacity_bytes = (*env)->GetDirectBufferCapacity(env, buffer);
  if (capacity_bytes < required_bytes) {
    return (jint)NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  float* data = (float*)(*env)->GetDirectBufferAddress(env, buffer);
  if (data == NULL) {
    return (jint)NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  return (jint)nar_dsp_pipeline_process_raw_stream(
      data, (int32_t)frame_count, (int32_t)channel_count, (int32_t)sample_rate,
      (int32_t)stream_slot);
}

// Returns JNI_TRUE (1) if the DSP pipeline has been initialised by Dart,
// JNI_FALSE (0) otherwise. Backed by an atomic load — safe from any thread.
JNIEXPORT jboolean JNICALL
Java_dev_wndavenz_music_effects_NativeDspAudioProcessor_nativeIsInitialized(
    JNIEnv* env, jclass clazz) {
  (void)env;
  (void)clazz;
  return (jboolean)(nar_dsp_pipeline_is_initialized() != 0);
}
