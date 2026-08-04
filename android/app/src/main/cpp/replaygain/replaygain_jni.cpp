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
using replaygain::RegionBackup;
using replaygain::TagFormat;
using replaygain::TagSnapshot;
using replaygain::WriteRequest;
using replaygain::WriteResult;

namespace {

// TagSnapshot <-> jobjectArray of 9 nullable jstrings, in this fixed order:
// [track_gain, track_peak, album_gain, album_peak, r128_track, r128_album,
//  title, artist, album]. Keep in sync with ReplayGainNative.kt's unpacking.
constexpr int kSnapshotFieldCount = 9;

jobjectArray PackSnapshot(JNIEnv* env, const TagSnapshot& snap) {
    jclass string_class = env->FindClass("java/lang/String");
    if (string_class == nullptr) return nullptr;
    jobjectArray arr = env->NewObjectArray(kSnapshotFieldCount, string_class, nullptr);
    // FIX Temuan #3 (LOW): delete string_class local ref immediately after use —
    // NewObjectArray holds its own internal reference to the class; the caller's
    // local ref is no longer needed and must be released.
    env->DeleteLocalRef(string_class);
    if (arr == nullptr) return nullptr;
    const std::optional<std::string>* fields[kSnapshotFieldCount] = {
        &snap.track_gain, &snap.track_peak, &snap.album_gain, &snap.album_peak,
        &snap.r128_track, &snap.r128_album, &snap.title,      &snap.artist,
        &snap.album,
    };
    for (int i = 0; i < kSnapshotFieldCount; i++) {
        if (fields[i]->has_value()) {
            // FIX Temuan #3 (LOW): capture the jstring local ref so it can be
            // deleted after SetObjectArrayElement — the array holds its own ref,
            // so the caller's local ref is redundant and must be released here.
            jstring jstr = replaygain::StdToJString(env, **fields[i]);
            env->SetObjectArrayElement(arr, i, jstr);
            if (jstr != nullptr) env->DeleteLocalRef(jstr);
        }
    }
    return arr;
}

TagSnapshot UnpackSnapshot(JNIEnv* env, jobjectArray arr) {
    TagSnapshot snap;
    if (arr == nullptr || env->GetArrayLength(arr) < kSnapshotFieldCount) return snap;
    std::optional<std::string>* fields[kSnapshotFieldCount] = {
        &snap.track_gain, &snap.track_peak, &snap.album_gain, &snap.album_peak,
        &snap.r128_track, &snap.r128_album, &snap.title,      &snap.artist,
        &snap.album,
    };
    for (int i = 0; i < kSnapshotFieldCount; i++) {
        auto* jstr = static_cast<jstring>(env->GetObjectArrayElement(arr, i));
        if (jstr != nullptr) {
            *fields[i] = replaygain::JStringToStd(env, jstr);
            env->DeleteLocalRef(jstr);
        }
    }
    return snap;
}

WriteRequest BuildWriteRequest(TagFormat format, jdouble track_gain_db,
                                jdouble track_peak_linear, jboolean has_album,
                                jdouble album_gain_db, jdouble album_peak_linear,
                                jint r128_track_q7_8, jboolean has_r128_album,
                                jint r128_album_q7_8) {
    WriteRequest req;
    req.format             = format;
    req.track_gain_db       = track_gain_db;
    req.track_peak_linear   = track_peak_linear;
    req.has_album           = (has_album == JNI_TRUE);
    req.album_gain_db       = album_gain_db;
    req.album_peak_linear   = album_peak_linear;
    req.r128_track_q7_8     = r128_track_q7_8;
    req.has_r128_album      = (has_r128_album == JNI_TRUE);
    req.r128_album_q7_8     = r128_album_q7_8;
    return req;
}

// Result envelope for the fd-based write/remove calls: Object[3] =
// [0] Integer resultCode, [1] String[9]? priorSnapshot, [2] byte[]? region.
// FIX Temuan #3 (LOW): all local refs created inside this function and
// PackSnapshot() are now explicitly deleted after they are no longer needed.
// Rule: every jobject/jclass/jstring/jarray returned by a New*/Find* call is a
// local ref that must be released by the caller before control leaves the
// JNI frame — or it leaks from the local ref table for the lifetime of the
// call stack frame, potentially exhausting the 512-slot JNI local ref table
// for callers that invoke this function in a tight loop (e.g. batch tag scans).
jobjectArray PackWriteEnvelope(JNIEnv* env, WriteResult result, const TagSnapshot& snap,
                                const RegionBackup& region, bool include_payload) {
    jclass object_class = env->FindClass("java/lang/Object");
    if (object_class == nullptr) return nullptr;
    jobjectArray envelope = env->NewObjectArray(3, object_class, nullptr);
    env->DeleteLocalRef(object_class);  // no longer needed
    if (envelope == nullptr) return nullptr;

    jclass integer_class = env->FindClass("java/lang/Integer");
    if (integer_class == nullptr) return nullptr;
    jmethodID ctor = env->GetMethodID(integer_class, "<init>", "(I)V");
    jobject code_obj = env->NewObject(integer_class, ctor, static_cast<jint>(result));
    env->DeleteLocalRef(integer_class);  // no longer needed
    env->SetObjectArrayElement(envelope, 0, code_obj);
    if (code_obj != nullptr) env->DeleteLocalRef(code_obj);  // no longer needed

    if (include_payload) {
        // Capture the inner array ref so it can be deleted after storing.
        jobjectArray snap_arr = PackSnapshot(env, snap);
        env->SetObjectArrayElement(envelope, 1, snap_arr);
        if (snap_arr != nullptr) env->DeleteLocalRef(snap_arr);  // no longer needed

        jbyteArray region_bytes = nullptr;
        if (region.captured) {
            region_bytes = env->NewByteArray(static_cast<jsize>(region.bytes.size()));
        }
        if (region_bytes != nullptr && !region.bytes.empty()) {
            env->SetByteArrayRegion(region_bytes, 0, static_cast<jsize>(region.bytes.size()),
                                     reinterpret_cast<const jbyte*>(region.bytes.data()));
        }
        env->SetObjectArrayElement(envelope, 2, region_bytes);
        if (region_bytes != nullptr) env->DeleteLocalRef(region_bytes);  // no longer needed
    }
    return envelope;
}

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
    if (analyzer == nullptr || frame_count <= 0 || buf == nullptr) return JNI_FALSE;

    // FIX Temuan #5 (LOW): validate that frame_count × channel_count samples
    // actually fit within the array Kotlin passed. Without this check, a stale
    // or corrupt frame_count could cause AddFramesShort() to read past the end
    // of the JNI array — undefined behaviour in C++ and a potential SIGSEGV
    // (even though GetShortArrayElements returns a copy, AddFramesShort indexes
    // into it with frame_count × channels as the total element count).
    const jsize array_len = env->GetArrayLength(buf);
    const jsize channel_count = static_cast<jsize>(analyzer->ChannelCount());
    if (channel_count <= 0 ||
        frame_count > array_len / channel_count) {  // integer division; safe
        return JNI_FALSE;
    }

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

    // Hold g_registry_mutex for the entire pointer-collection + loudness computation
    // block. Without this, DestroyAnalyzer() on a concurrent thread could free an
    // ebur128_state* between the lock release and the ebur128_loudness_global_multiple
    // call, causing a use-after-free crash. The computation is sub-millisecond even
    // for large albums, so holding the lock here is safe.
    std::vector<ebur128_state*> states;
    double result;
    {
        std::lock_guard<std::mutex> lock(g_registry_mutex);
        states.reserve(count);
        for (jsize i = 0; i < count; i++) {
            auto it = g_registry.find(elems[i]);
            if (it != g_registry.end()) {
                states.push_back(it->second->raw_state());
            }
        }
        env->ReleaseLongArrayElements(handles, elems, JNI_ABORT);
        result = replaygain::ComputeAlbumLoudness(states);
    }
    return result;
}

// ── Scoped-storage-safe fd-based tag writing ─────────────────────────────────
// See tag_writer.h for the full write→close→reopen→verify→(restore) protocol
// these entry points implement pieces of. `fd` is a raw file descriptor
// Kotlin obtained via ParcelFileDescriptor.detachFd() — ownership passes to
// native for this call; TagLib's FileStream closes it internally on
// destruction (it wraps the fd with fdopen()/fclose()), so Kotlin must NOT
// call ParcelFileDescriptor.close() on an fd it already detached and passed
// here.

JNIEXPORT jobjectArray JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeWriteReplayGainTagsFd(
    JNIEnv* env, jobject /*thiz*/, jint fd, jint format, jdouble track_gain_db,
    jdouble track_peak_linear, jboolean has_album, jdouble album_gain_db,
    jdouble album_peak_linear, jint r128_track_q7_8, jboolean has_r128_album,
    jint r128_album_q7_8) {
    const WriteRequest req = BuildWriteRequest(
        static_cast<TagFormat>(format), track_gain_db, track_peak_linear, has_album,
        album_gain_db, album_peak_linear, r128_track_q7_8, has_r128_album, r128_album_q7_8);
    TagSnapshot prior;
    RegionBackup region;
    const WriteResult result =
        replaygain::WriteReplayGainTagsFd(fd, req, &prior, &region);
    return PackWriteEnvelope(env, result, prior, region, /*include_payload=*/true);
}

JNIEXPORT jobjectArray JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeRemoveReplayGainTagsFd(
    JNIEnv* env, jobject /*thiz*/, jint fd, jint format) {
    TagSnapshot prior;
    RegionBackup region;
    const WriteResult result = replaygain::RemoveReplayGainTagsFd(
        fd, static_cast<TagFormat>(format), &prior, &region);
    return PackWriteEnvelope(env, result, prior, region, /*include_payload=*/true);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeVerifyReplayGainTagsFd(
    JNIEnv* env, jobject /*thiz*/, jint fd, jint format, jdouble track_gain_db,
    jdouble track_peak_linear, jboolean has_album, jdouble album_gain_db,
    jdouble album_peak_linear, jint r128_track_q7_8, jboolean has_r128_album,
    jint r128_album_q7_8, jobjectArray prior_snapshot) {
    const WriteRequest req = BuildWriteRequest(
        static_cast<TagFormat>(format), track_gain_db, track_peak_linear, has_album,
        album_gain_db, album_peak_linear, r128_track_q7_8, has_r128_album, r128_album_q7_8);
    const TagSnapshot prior = UnpackSnapshot(env, prior_snapshot);
    const WriteResult result = replaygain::VerifyReplayGainTagsFd(fd, req, prior);
    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeVerifyReplayGainRemovedFd(
    JNIEnv* env, jobject /*thiz*/, jint fd, jint format, jobjectArray prior_snapshot) {
    const TagSnapshot prior = UnpackSnapshot(env, prior_snapshot);
    const WriteResult result = replaygain::VerifyReplayGainRemovedFd(
        fd, static_cast<TagFormat>(format), prior);
    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeVerifyReplayGainRestoredFd(
    JNIEnv* env, jobject /*thiz*/, jint fd, jint format, jobjectArray prior_snapshot) {
    const TagSnapshot prior = UnpackSnapshot(env, prior_snapshot);
    const WriteResult result = replaygain::VerifyReplayGainRestoredFd(
        fd, static_cast<TagFormat>(format), prior);
    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeRestoreMetadataRegionFd(
    JNIEnv* env, jobject /*thiz*/, jint fd, jint format, jbyteArray region_bytes) {
    RegionBackup backup;
    if (region_bytes != nullptr) {
        const jsize len = env->GetArrayLength(region_bytes);
        backup.bytes.resize(static_cast<size_t>(len));
        if (len > 0) {
            env->GetByteArrayRegion(region_bytes, 0, len,
                                     reinterpret_cast<jbyte*>(backup.bytes.data()));
        }
    }
    const WriteResult result =
        replaygain::RestoreMetadataRegionFd(fd, static_cast<TagFormat>(format), backup);
    return static_cast<jint>(result);
}

// ── Fixed-point helper exposed for Kotlin's own display/formatting needs ────

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeLufsToR128Q7x8(
    JNIEnv* /*env*/, jobject /*thiz*/, jdouble integrated_lufs) {
    return replaygain::LufsToR128Q7_8(integrated_lufs);
}

}  // extern "C"
