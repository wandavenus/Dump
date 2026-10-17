#include <jni.h>
#include <stdlib.h>

#include "automix_native.h"
#include "automix_phase_lock.h"

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_dev_wndavenz_music_automix_AutomixNative_nativeAnalyze(
    JNIEnv* env, jobject /* thiz */, jfloatArray pcm, jint sample_rate) {
  if (pcm == nullptr) return nullptr;
  const jsize count = env->GetArrayLength(pcm);
  if (count <= 0) return nullptr;

  jboolean is_copy = JNI_FALSE;
  jfloat* samples = env->GetFloatArrayElements(pcm, &is_copy);
  if (samples == nullptr) return nullptr;

  double values[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  const int32_t status = nar_automix_analyze(
      reinterpret_cast<const float*>(samples), count, sample_rate, values,
      NAR_AUTOMIX_ANALYSIS_VALUE_COUNT);
  env->ReleaseFloatArrayElements(pcm, samples, JNI_ABORT);
  if (status != 1) return nullptr;

  jdoubleArray result =
      env->NewDoubleArray(NAR_AUTOMIX_ANALYSIS_VALUE_COUNT);
  if (result == nullptr) return nullptr;
  env->SetDoubleArrayRegion(result, 0, NAR_AUTOMIX_ANALYSIS_VALUE_COUNT,
                            values);
  return result;
}

extern "C" JNIEXPORT jfloat JNICALL
Java_dev_wndavenz_music_automix_AutomixPhaseLock_nativePhaseLockFactor(
    JNIEnv* /* env */, jobject /* thiz */, jdouble outgoing_position_ms,
    jdouble outgoing_phase_offset_ms, jdouble outgoing_bpm,
    jdouble incoming_position_ms, jdouble incoming_phase_offset_ms,
    jdouble incoming_bpm, jdouble remaining_ms, jdouble max_nudge) {
  return static_cast<jfloat>(nar_automix_phase_lock_factor(
      outgoing_position_ms, outgoing_phase_offset_ms, outgoing_bpm,
      incoming_position_ms, incoming_phase_offset_ms, incoming_bpm,
      remaining_ms, max_nudge));
}

extern "C" JNIEXPORT jfloat JNICALL
Java_dev_wndavenz_music_automix_AutomixPhaseLock_nativePhrasePhaseLockFactor(
    JNIEnv* /* env */, jobject /* thiz */, jdouble outgoing_position_ms,
    jdouble outgoing_downbeat_offset_ms, jdouble outgoing_bpm,
    jdouble incoming_position_ms, jdouble incoming_downbeat_offset_ms,
    jdouble incoming_bpm, jdouble remaining_ms, jdouble max_nudge,
    jint beats_per_phrase) {
  return static_cast<jfloat>(nar_automix_phrase_lock_factor(
      outgoing_position_ms, outgoing_downbeat_offset_ms, outgoing_bpm,
      incoming_position_ms, incoming_downbeat_offset_ms, incoming_bpm,
      remaining_ms, max_nudge, beats_per_phrase));
}


extern "C" JNIEXPORT jdoubleArray JNICALL
Java_dev_wndavenz_music_automix_AutomixNative_nativeAnalyzeChords(
    JNIEnv* env, jobject /* thiz */, jfloatArray pcm, jint sample_rate) {
  if (pcm == nullptr || sample_rate < 4000 || sample_rate > 192000) return nullptr;
  const jsize count = env->GetArrayLength(pcm);
  const int64_t window_samples = (int64_t)sample_rate * 2;
  if (count < window_samples) return env->NewDoubleArray(0);
  const int64_t max_segments64 = 1 + (count - window_samples) / sample_rate;
  if (max_segments64 <= 0 || max_segments64 > 4096) return nullptr;
  const jsize max_segments = static_cast<jsize>(max_segments64);
  const jsize output_capacity = max_segments * 4;
  double* output = static_cast<double*>(
      calloc(static_cast<size_t>(output_capacity), sizeof(double)));
  if (output == nullptr) return nullptr;

  jfloat* samples = env->GetFloatArrayElements(pcm, nullptr);
  if (samples == nullptr) {
    free(output);
    return nullptr;
  }
  const int32_t count_written = nar_automix_analyze_chords(
      reinterpret_cast<const float*>(samples), count, sample_rate,
      output, output_capacity);
  env->ReleaseFloatArrayElements(pcm, samples, JNI_ABORT);
  if (count_written < 0 || count_written > max_segments) {
    free(output);
    return nullptr;
  }

  const jsize result_count = static_cast<jsize>(count_written * 4);
  jdoubleArray result = env->NewDoubleArray(result_count);
  if (result != nullptr && result_count > 0) {
    env->SetDoubleArrayRegion(result, 0, result_count, output);
  }
  free(output);
  return result;
}
