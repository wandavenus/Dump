#include <jni.h>

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
