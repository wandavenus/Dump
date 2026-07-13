// JNI bridge for dev.wndavenz.music.replaygain.ReplayGainNative (Kotlin).
//
// Design: the JNI layer is deliberately thin. It never touches file I/O or
// MediaCodec — Kotlin still owns decoding (MediaExtractor + MediaCodec, same
// as before) and streams raw PCM shorts across the JNI boundary into an
// EburAnalyzer. This keeps native code portable/testable (it only knows
// about PCM buffers and file paths for tag writing) and keeps all Android
// framework interaction on the Kotlin side where it already works.
//
// Handle lifecycle: nativeCreateAnalyzer() returns an opaque jlong that is
// really a `reinterpret_cast<jlong>(EburAnalyzer*)`. Kotlin must call
// nativeDestroyAnalyzer() exactly once per handle (a try/finally in
// EburTrackSession.kt enforces this). For album scans, Kotlin keeps every
// track's handle alive until nativeComputeAlbumLoudness() has been called,
// then destroys them all.

#include <jni.h>

#include <cmath>
#include <unordered_map>
#include <mutex>
#include <vector>

#include "ebur128_analyzer.h"
#include "jni_common.h"
#include "tag_writer.h"

using replaygain::EburAnalyzer;
using replaygain::LoudnessResult;
using replaygain::TagFormat;
using replaygain::WriteRequest;
using replaygain::WriteResult;

namespace {

// Registry mapping opaque handles back to EburAnalyzer* so we can validate
// handles from Kotlin instead of trusting an arbitrary jlong cast blindly.
// Also lets nativeComputeAlbumLoudness() look up multiple handles safely.
std::mutex g_registry_mutex;
std::unordered_map<jlong, std::unique_ptr<EburAnalyzer>> g_registry;
jlong g_next_handle = 1;

jlong RegisterAnalyzer(std::unique_ptr<EburAnalyzer> analyzer) {
    std::lock_guard<std::mutex> lock(g_registry_mutex);
    const jlong handle = g_next_handle++;
    g_registry[handle] = std::move(analyzer);
    return handle;
}

EburAnalyzer* LookupAnalyzer(jlong handle) {
    std::lock_guard<std::mutex> lock(g_registry_mutex);
    auto it = g_registry.find(handle);
    return (it == g_registry.end()) ? nullptr : it->second.get();
}

void DestroyAnalyzer(jlong handle) {
    std::lock_guard<std::mutex> lock(g_registry_mutex);
    g_registry.erase(handle);
}

}  // namespace

extern "C" {

// ── Analyzer lifecycle ────────────────────────────────────────────────────────

JNIEXPORT jlong JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeCreateAnalyzer(
    JNIEnv* /*env*/, jobject /*thiz*/, jint sample_rate, jint channels) {
    if (sample_rate <= 0 || channels <= 0) return 0;
    auto analyzer = EburAnalyzer::Create(static_cast<uint32_t>(sample_rate),
                                          static_cast<uint32_t>(channels));
    if (analyzer == nullptr) return 0;
    return RegisterAnalyzer(std::move(analyzer));
}

JNIEXPORT jboolean JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeAddFramesShort(
    JNIEnv* env, jobject /*thiz*/, jlong handle, jshortArray buf, jint frame_count) {
    EburAnalyzer* analyzer = LookupAnalyzer(handle);
    if (analyzer == nullptr || frame_count <= 0) return JNI_FALSE;

    jshort* elems = env->GetShortArrayElements(buf, nullptr);
    if (elems == nullptr) return JNI_FALSE;
    const bool ok = analyzer->AddFramesShort(reinterpret_cast<const int16_t*>(elems),
                                              static_cast<size_t>(frame_count));
    env->ReleaseShortArrayElements(buf, elems, JNI_ABORT);  // read-only, no copy-back needed
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jobject JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeFinishAnalyzer(
    JNIEnv* env, jobject /*thiz*/, jlong handle) {
    EburAnalyzer* analyzer = LookupAnalyzer(handle);
    if (analyzer == nullptr) return nullptr;

    const LoudnessResult r = analyzer->Finish();

    // Returns a double[5]: [integratedLufs, lra, truePeakDbtp, samplePeakDbfs,
    // recommendedGainDb, validFlag(0/1)] — kept as a primitive array (not a
    // custom Kotlin data class constructed via JNI) to avoid brittle
    // FindClass/GetMethodID boilerplate; ReplayGainNative.kt unpacks it.
    jdoubleArray out = env->NewDoubleArray(6);
    if (out == nullptr) return nullptr;
    jdouble vals[6] = {
        r.integrated_lufs, r.loudness_range_lu, r.true_peak_dbtp,
        r.sample_peak_dbfs, r.recommended_gain_db, r.valid ? 1.0 : 0.0,
    };
    env->SetDoubleArrayRegion(out, 0, 6, vals);
    return out;
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeDestroyAnalyzer(
    JNIEnv* /*env*/, jobject /*thiz*/, jlong handle) {
    DestroyAnalyzer(handle);
}

// ── Album aggregation ─────────────────────────────────────────────────────────

JNIEXPORT jdouble JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeComputeAlbumLoudness(
    JNIEnv* env, jobject /*thiz*/, jlongArray handles) {
    const jsize count = env->GetArrayLength(handles);
    if (count <= 0) return -HUGE_VAL;

    jlong* elems = env->GetLongArrayElements(handles, nullptr);
    if (elems == nullptr) return -HUGE_VAL;

    std::vector<ebur128_state*> states;
    states.reserve(count);
    {
        std::lock_guard<std::mutex> lock(g_registry_mutex);
        for (jsize i = 0; i < count; i++) {
            auto it = g_registry.find(elems[i]);
            if (it != g_registry.end()) {
                states.push_back(it->second->raw_state());
            }
        }
    }
    env->ReleaseLongArrayElements(handles, elems, JNI_ABORT);

    return replaygain::ComputeAlbumLoudness(states);
}

// ── Tag writing ───────────────────────────────────────────────────────────────

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeWriteReplayGainTags(
    JNIEnv* env, jobject /*thiz*/, jstring path, jint format, jdouble track_gain_db,
    jdouble track_peak_linear, jboolean has_album, jdouble album_gain_db,
    jdouble album_peak_linear, jint r128_track_q7_8, jboolean has_r128_album,
    jint r128_album_q7_8) {
    WriteRequest req;
    req.path              = replaygain::JStringToStd(env, path);
    req.format             = static_cast<TagFormat>(format);
    req.track_gain_db       = track_gain_db;
    req.track_peak_linear   = track_peak_linear;
    req.has_album           = (has_album == JNI_TRUE);
    req.album_gain_db       = album_gain_db;
    req.album_peak_linear   = album_peak_linear;
    req.r128_track_q7_8     = r128_track_q7_8;
    req.has_r128_album      = (has_r128_album == JNI_TRUE);
    req.r128_album_q7_8     = r128_album_q7_8;

    const WriteResult result = replaygain::WriteReplayGainTags(req);
    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeRemoveReplayGainTags(
    JNIEnv* env, jobject /*thiz*/, jstring path) {
    const std::string p = replaygain::JStringToStd(env, path);
    const WriteResult result = replaygain::RemoveReplayGainTags(p);
    return static_cast<jint>(result);
}

// ── Fixed-point helper exposed for Kotlin's own display/formatting needs ────

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeLufsToR128Q7x8(
    JNIEnv* /*env*/, jobject /*thiz*/, jdouble integrated_lufs) {
    return replaygain::LufsToR128Q7_8(integrated_lufs);
}

}  // extern "C"
