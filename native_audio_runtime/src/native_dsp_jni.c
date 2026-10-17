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
#include "automix_tone_processor.h"
#include "automix_live_tracker.h"

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
  // Observe decoded PCM before DSP. Processing is per-slot, bounded and lock-free.
  (void)nar_automix_live_tracker_process(data, (int32_t)frame_count,
      (int32_t)channel_count, (int32_t)sample_rate, (int32_t)stream_slot);
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

// Kotlin's AutoMix AudioProcessor stays in the Media3 chain at its original
// position, but all per-sample filtering now runs in C/ARM64 NEON.
JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_AutomixToneAudioProcessor_nativeConfigureTone(
    JNIEnv* env, jclass clazz, jint stream_slot, jint sample_rate,
    jint channel_count) {
  (void)env;
  (void)clazz;
  return (jint)nar_automix_tone_configure(
      (int32_t)stream_slot, (int32_t)sample_rate, (int32_t)channel_count);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_AutomixToneAudioProcessor_nativeSetBassGain(
    JNIEnv* env, jclass clazz, jint stream_slot, jfloat gain) {
  (void)env;
  (void)clazz;
  return (jint)nar_automix_tone_set_bass_gain((int32_t)stream_slot, gain);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_AutomixToneAudioProcessor_nativeSetMidGain(
    JNIEnv* env, jclass clazz, jint stream_slot, jfloat gain) {
  (void)env;
  (void)clazz;
  return (jint)nar_automix_tone_set_mid_gain((int32_t)stream_slot, gain);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_AutomixToneAudioProcessor_nativeSetHighGain(
    JNIEnv* env, jclass clazz, jint stream_slot, jfloat gain) {
  (void)env;
  (void)clazz;
  return (jint)nar_automix_tone_set_high_gain((int32_t)stream_slot, gain);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_AutomixToneAudioProcessor_nativeSetFadeGain(
    JNIEnv* env, jclass clazz, jint stream_slot, jfloat gain) {
  (void)env;
  (void)clazz;
  return (jint)nar_automix_tone_set_fade_gain((int32_t)stream_slot, gain);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_AutomixToneAudioProcessor_nativeSetCrossfadeGains(
    JNIEnv* env, jclass clazz, jint outgoing_slot, jint incoming_slot,
    jfloat progress, jfloat gamma, jfloat outgoing_trim, jfloat incoming_trim) {
  (void)env;
  (void)clazz;
  return (jint)nar_automix_tone_set_crossfade_gains(
      (int32_t)outgoing_slot, (int32_t)incoming_slot, progress, gamma,
      outgoing_trim, incoming_trim);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_AutomixToneAudioProcessor_nativeProcessTone(
    JNIEnv* env, jclass clazz, jobject buffer, jint frame_count,
    jint channel_count, jint stream_slot) {
  (void)clazz;
  if (buffer == NULL || frame_count <= 0 || channel_count <= 0) return 0;
  const int64_t required_bytes =
      (int64_t)frame_count * (int64_t)channel_count * (int64_t)sizeof(float);
  if (required_bytes <= 0 ||
      (*env)->GetDirectBufferCapacity(env, buffer) < required_bytes) {
    return 0;
  }
  float* data = (float*)(*env)->GetDirectBufferAddress(env, buffer);
  if (data == NULL) return 0;
  return (jint)nar_automix_tone_process(
      data, (int32_t)frame_count, (int32_t)channel_count,
      (int32_t)stream_slot);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_AutomixToneAudioProcessor_nativeResetTone(
    JNIEnv* env, jclass clazz, jint stream_slot) {
  (void)env;
  (void)clazz;
  return (jint)nar_automix_tone_reset((int32_t)stream_slot);
}


JNIEXPORT jdoubleArray JNICALL
Java_dev_wndavenz_music_effects_NativeDspAudioProcessor_nativeGetLiveBeatState(
    JNIEnv* env, jclass clazz, jint stream_slot) {
  (void)clazz;
  double values[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0.0, 0.0, 0.0};
  if (nar_automix_live_tracker_get((int32_t)stream_slot, values,
                                    NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) != 1) {
    return NULL;
  }
  jdoubleArray result = (*env)->NewDoubleArray(env, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT);
  if (result != NULL) {
    (*env)->SetDoubleArrayRegion(env, result, 0,
        NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT, values);
  }
  return result;
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_effects_NativeDspAudioProcessor_nativeResetLiveBeatTracker(
    JNIEnv* env, jclass clazz, jint stream_slot) {
  (void)env;
  (void)clazz;
  (void)nar_automix_live_tracker_reset((int32_t)stream_slot);
}
