#include <aaudio/AAudio.h>
#include <android/log.h>
#include <jni.h>
#include <atomic>
#include <condition_variable>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <vector>

#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "AAudioEngine", __VA_ARGS__)

namespace {
struct Engine {
    AAudioStream* stream = nullptr;
    std::mutex mutex;
    std::condition_variable cv;
    std::vector<int16_t> ring;
    size_t read = 0, write = 0, used = 0;
    int32_t sampleRate = 48000;
    int32_t channels = 2;
    float volume = 1.0f;
    bool configured = false;
} g;

aaudio_data_callback_result_t dataCallback(AAudioStream*, void*, void* audioData, int32_t numFrames) {
    auto* out = static_cast<int16_t*>(audioData);
    const size_t requested = static_cast<size_t>(numFrames) * static_cast<size_t>(g.channels);
    std::unique_lock<std::mutex> lock(g.mutex);
    size_t copied = 0;
    while (copied < requested && g.used > 0) {
        float scaled = static_cast<float>(g.ring[g.read]) * g.volume;
        if (scaled > 32767.0f) scaled = 32767.0f;
        if (scaled < -32768.0f) scaled = -32768.0f;
        out[copied++] = static_cast<int16_t>(scaled);
        g.read = (g.read + 1) % g.ring.size();
        --g.used;
    }
    lock.unlock();
    g.cv.notify_one();
    if (copied < requested) std::memset(out + copied, 0, (requested - copied) * sizeof(int16_t));
    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

void closeStream() {
    if (g.stream) {
        AAudioStream_requestStop(g.stream);
        AAudioStream_close(g.stream);
        g.stream = nullptr;
    }
}
}

extern "C" JNIEXPORT void JNICALL
Java_dev_wndavenz_music_aaudio_AAudioPlaybackBridge_nativeInit(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(g.mutex);
    if (g.ring.empty()) g.ring.resize(48000 * 2 * 4);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_wndavenz_music_aaudio_AAudioPlaybackBridge_nativeConfigure(JNIEnv* env, jobject, jint sampleRate, jint channels) {
    std::lock_guard<std::mutex> lock(g.mutex);
    closeStream();
    g.sampleRate = sampleRate > 0 ? sampleRate : 48000;
    g.channels = channels > 0 ? channels : 2;
    g.ring.assign(static_cast<size_t>(g.sampleRate) * static_cast<size_t>(g.channels) * 4, 0);
    g.read = g.write = g.used = 0;

    AAudioStreamBuilder* builder = nullptr;
    if (AAudio_createStreamBuilder(&builder) != AAUDIO_OK) {
        env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "AAudio builder failed"); return;
    }
    AAudioStreamBuilder_setDirection(builder, AAUDIO_DIRECTION_OUTPUT);
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_SHARED);
    AAudioStreamBuilder_setSampleRate(builder, g.sampleRate);
    AAudioStreamBuilder_setChannelCount(builder, g.channels);
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_I16);
    AAudioStreamBuilder_setDataCallback(builder, dataCallback, nullptr);
    aaudio_result_t res = AAudioStreamBuilder_openStream(builder, &g.stream);
    AAudioStreamBuilder_delete(builder);
    if (res != AAUDIO_OK) {
        LOGE("openStream failed: %s", AAudio_convertResultToText(res));
        env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), AAudio_convertResultToText(res));
    }
}

extern "C" JNIEXPORT void JNICALL Java_dev_wndavenz_music_aaudio_AAudioPlaybackBridge_nativeStart(JNIEnv*, jobject) { if (g.stream) AAudioStream_requestStart(g.stream); }
extern "C" JNIEXPORT void JNICALL Java_dev_wndavenz_music_aaudio_AAudioPlaybackBridge_nativePause(JNIEnv*, jobject) { if (g.stream) AAudioStream_requestPause(g.stream); }
extern "C" JNIEXPORT void JNICALL Java_dev_wndavenz_music_aaudio_AAudioPlaybackBridge_nativeStop(JNIEnv*, jobject) { if (g.stream) AAudioStream_requestStop(g.stream); }
extern "C" JNIEXPORT void JNICALL Java_dev_wndavenz_music_aaudio_AAudioPlaybackBridge_nativeSetVolume(JNIEnv*, jobject, jfloat volume) { g.volume = volume < 0.0f ? 0.0f : volume; }
extern "C" JNIEXPORT void JNICALL Java_dev_wndavenz_music_aaudio_AAudioPlaybackBridge_nativeFlush(JNIEnv*, jobject) { std::lock_guard<std::mutex> lock(g.mutex); g.read = g.write = g.used = 0; }
extern "C" JNIEXPORT void JNICALL Java_dev_wndavenz_music_aaudio_AAudioPlaybackBridge_nativeRelease(JNIEnv*, jobject) { std::lock_guard<std::mutex> lock(g.mutex); closeStream(); g.ring.clear(); }

extern "C" JNIEXPORT void JNICALL
Java_dev_wndavenz_music_aaudio_AAudioPlaybackBridge_nativeWrite(JNIEnv* env, jobject, jobject buffer, jint size) {
    auto* src = static_cast<int16_t*>(env->GetDirectBufferAddress(buffer));
    if (!src || size <= 0) return;
    size_t samples = static_cast<size_t>(size) / sizeof(int16_t);
    size_t copied = 0;
    while (copied < samples) {
        std::unique_lock<std::mutex> lock(g.mutex);
        g.cv.wait_for(lock, std::chrono::milliseconds(100), [] { return g.ring.empty() || g.used < g.ring.size(); });
        if (g.ring.empty()) return;
        while (copied < samples && g.used < g.ring.size()) {
            g.ring[g.write] = src[copied++];
            g.write = (g.write + 1) % g.ring.size();
            ++g.used;
        }
    }
}
