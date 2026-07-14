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
//            all parameter control (set_gain_db, set_bypass, set_enabled), and dispose().
//   Kotlin — calls nar_dsp_pipeline_process_raw() on ExoPlayer's audio thread ONLY.
//
// Thread safety:
//   nativeProcessFloat() is called on ExoPlayer's audio rendering thread.
//   nar_dsp_pipeline_process_raw() acquires no locks and makes no heap allocations
//   — safe to call concurrently with Dart's atomic-based parameter writes.

#include <jni.h>
#include <stdint.h>

#include "dsp_pipeline.h"
#include "native_audio_runtime.h"

// Java class: dev.wndavenz.music.effects.NativeDspAudioProcessor
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
