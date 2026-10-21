// ─────────────────────────────────────────────────────────────────────────────
// JNI bridge for pcm_native.
//
// Java class: dev.wndavenz.music.audio.mixer.NativePcmBridge
//
// Every entry point validates handles, array lengths and direct-buffer
// capacity before touching native memory. Invalid state is reported with a
// negative value / false; no exception is thrown into the audio thread.
// ─────────────────────────────────────────────────────────────────────────────

#include <jni.h>

#include <cstdint>
#include <cstring>

#include "pcm_native.h"

namespace {

inline NarDeckConverter* as_converter(jlong handle) {
    return reinterpret_cast<NarDeckConverter*>(static_cast<intptr_t>(handle));
}

inline NarStereoMixer* as_mixer(jlong handle) {
    return reinterpret_cast<NarStereoMixer*>(static_cast<intptr_t>(handle));
}

inline int array_frames(JNIEnv* env, jfloatArray array) {
    if (array == nullptr) return 0;
    return static_cast<int>(env->GetArrayLength(array) / NAR_PCM_BUS_CHANNELS);
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_dev_wndavenz_music_audio_mixer_NativePcmBridge_nativeCreateDeckConverter(
    JNIEnv* env,
    jclass clazz,
    jint inputRate,
    jint outputRate) {
    (void) env;
    (void) clazz;
    return static_cast<jlong>(reinterpret_cast<intptr_t>(
        nar_deck_converter_create(inputRate, outputRate, 32, 256)));
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_audio_mixer_NativePcmBridge_nativeDestroyDeckConverter(
    JNIEnv* env,
    jclass clazz,
    jlong handle) {
    (void) env;
    (void) clazz;
    nar_deck_converter_destroy(as_converter(handle));
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_audio_mixer_NativePcmBridge_nativeResetDeckConverter(
    JNIEnv* env,
    jclass clazz,
    jlong handle) {
    (void) env;
    (void) clazz;
    nar_deck_converter_reset(as_converter(handle));
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_audio_mixer_NativePcmBridge_nativeDeckOutputFramesUpperBound(
    JNIEnv* env,
    jclass clazz,
    jlong handle,
    jint inputFrames) {
    (void) env;
    (void) clazz;
    return nar_deck_converter_max_output_frames(as_converter(handle), inputFrames);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_audio_mixer_NativePcmBridge_nativeProcessDeck(
    JNIEnv* env,
    jclass clazz,
    jlong handle,
    jobject inputBuffer,
    jint offsetBytes,
    jint inputFrames,
    jint channels,
    jint format,
    jboolean bigEndian,
    jfloatArray output) {
    (void) clazz;
    NarDeckConverter* converter = as_converter(handle);
    if (converter == nullptr || inputBuffer == nullptr || output == nullptr) {
        return NAR_PCM_ERROR_ARGUMENT;
    }
    if (offsetBytes < 0 || inputFrames <= 0 || channels <= 0 || channels > 8) {
        return NAR_PCM_ERROR_ARGUMENT;
    }

    const jlong capacity = env->GetDirectBufferCapacity(inputBuffer);
    if (capacity < 0) return NAR_PCM_ERROR_ARGUMENT;
    void* input = env->GetDirectBufferAddress(inputBuffer);
    if (input == nullptr) return NAR_PCM_ERROR_ARGUMENT;

    int bytesPerSample = 0;
    switch (format) {
        case NAR_PCM_U8: bytesPerSample = 1; break;
        case NAR_PCM_S16: bytesPerSample = 2; break;
        case NAR_PCM_S24: bytesPerSample = 3; break;
        case NAR_PCM_S32: bytesPerSample = 4; break;
        case NAR_PCM_F32: bytesPerSample = 4; break;
        case NAR_PCM_F64: bytesPerSample = 8; break;
        default: return NAR_PCM_ERROR_ARGUMENT;
    }
    const int64_t required = static_cast<int64_t>(offsetBytes) +
                             static_cast<int64_t>(inputFrames) * channels * bytesPerSample;
    if (required <= 0 || required > capacity) {
        return NAR_PCM_ERROR_ARGUMENT;
    }

    const int outputCapacityFrames = array_frames(env, output);
    if (outputCapacityFrames <= 0) return NAR_PCM_ERROR_ARGUMENT;
    // The converter treats each call as a complete block: a short output
    // buffer would silently drop the tail while history still advances.
    const int requiredOutputFrames =
        nar_deck_converter_max_output_frames(converter, inputFrames);
    if (requiredOutputFrames <= 0 ||
        outputCapacityFrames < requiredOutputFrames) {
        return NAR_PCM_ERROR_ARGUMENT;
    }

    float* outputAddress = env->GetFloatArrayElements(output, nullptr);
    if (outputAddress == nullptr) return NAR_PCM_ERROR_MEMORY;

    const int result = nar_deck_converter_process(
        converter,
        static_cast<const uint8_t*>(input) + offsetBytes,
        inputFrames,
        channels,
        format,
        bigEndian == JNI_TRUE ? 1 : 0,
        outputAddress,
        outputCapacityFrames);

    env->ReleaseFloatArrayElements(output, outputAddress, 0);
    return result;
}

JNIEXPORT jlong JNICALL
Java_dev_wndavenz_music_audio_mixer_NativePcmBridge_nativeCreateMixer(
    JNIEnv* env,
    jclass clazz,
    jint sampleRate,
    jint maxBlockFrames) {
    (void) env;
    (void) clazz;
    return static_cast<jlong>(reinterpret_cast<intptr_t>(
        nar_stereo_mixer_create(sampleRate, maxBlockFrames)));
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_audio_mixer_NativePcmBridge_nativeDestroyMixer(
    JNIEnv* env,
    jclass clazz,
    jlong handle) {
    (void) env;
    (void) clazz;
    nar_stereo_mixer_destroy(as_mixer(handle));
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_audio_mixer_NativePcmBridge_nativeResetMixer(
    JNIEnv* env,
    jclass clazz,
    jlong handle) {
    (void) env;
    (void) clazz;
    nar_stereo_mixer_reset(as_mixer(handle));
}

JNIEXPORT jboolean JNICALL
Java_dev_wndavenz_music_audio_mixer_NativePcmBridge_nativeMix(
    JNIEnv* env,
    jclass clazz,
    jlong handle,
    jint activeMask,
    jfloatArray deck0,
    jfloatArray deck1,
    jfloatArray gains,
    jfloatArray targets,
    jfloatArray output,
    jint frames) {
    (void) clazz;
    NarStereoMixer* mixer = as_mixer(handle);
    if (mixer == nullptr || gains == nullptr || targets == nullptr ||
        output == nullptr || frames <= 0) {
        return JNI_FALSE;
    }

    const int outputFrames = array_frames(env, output);
    if (outputFrames < frames) return JNI_FALSE;
    if (env->GetArrayLength(gains) < NAR_PCM_BUS_CHANNELS ||
        env->GetArrayLength(targets) < NAR_PCM_BUS_CHANNELS) {
        return JNI_FALSE;
    }

    const bool useDeck0 = (activeMask & 1) != 0;
    const bool useDeck1 = (activeMask & 2) != 0;
    if (useDeck0 && array_frames(env, deck0) < frames) return JNI_FALSE;
    if (useDeck1 && array_frames(env, deck1) < frames) return JNI_FALSE;

    float* deck0Address = useDeck0 ? env->GetFloatArrayElements(deck0, nullptr) : nullptr;
    if (useDeck0 && deck0Address == nullptr) return JNI_FALSE;
    float* deck1Address = useDeck1 ? env->GetFloatArrayElements(deck1, nullptr) : nullptr;
    if (useDeck1 && deck1Address == nullptr) {
        if (useDeck0) env->ReleaseFloatArrayElements(deck0, deck0Address, JNI_ABORT);
        return JNI_FALSE;
    }
    float* gainsAddress = env->GetFloatArrayElements(gains, nullptr);
    if (gainsAddress == nullptr) {
        if (useDeck0) env->ReleaseFloatArrayElements(deck0, deck0Address, JNI_ABORT);
        if (useDeck1) env->ReleaseFloatArrayElements(deck1, deck1Address, JNI_ABORT);
        return JNI_FALSE;
    }
    float* targetsAddress = env->GetFloatArrayElements(targets, nullptr);
    if (targetsAddress == nullptr) {
        env->ReleaseFloatArrayElements(gains, gainsAddress, JNI_ABORT);
        if (useDeck0) env->ReleaseFloatArrayElements(deck0, deck0Address, JNI_ABORT);
        if (useDeck1) env->ReleaseFloatArrayElements(deck1, deck1Address, JNI_ABORT);
        return JNI_FALSE;
    }
    float* outputAddress = env->GetFloatArrayElements(output, nullptr);
    if (outputAddress == nullptr) {
        env->ReleaseFloatArrayElements(targets, targetsAddress, JNI_ABORT);
        env->ReleaseFloatArrayElements(gains, gainsAddress, JNI_ABORT);
        if (useDeck0) env->ReleaseFloatArrayElements(deck0, deck0Address, JNI_ABORT);
        if (useDeck1) env->ReleaseFloatArrayElements(deck1, deck1Address, JNI_ABORT);
        return JNI_FALSE;
    }

    const int result = nar_stereo_mixer_process(
        mixer,
        deck0Address,
        deck1Address,
        static_cast<unsigned int>(activeMask),
        frames,
        gainsAddress,
        targetsAddress,
        outputAddress);

    env->ReleaseFloatArrayElements(output, outputAddress, 0);
    env->ReleaseFloatArrayElements(targets, targetsAddress, JNI_ABORT);
    env->ReleaseFloatArrayElements(gains, gainsAddress, 0);
    if (useDeck0) env->ReleaseFloatArrayElements(deck0, deck0Address, JNI_ABORT);
    if (useDeck1) env->ReleaseFloatArrayElements(deck1, deck1Address, JNI_ABORT);

    return result == 1 ? JNI_TRUE : JNI_FALSE;
}

}  // extern "C"
