#ifndef REPLAYGAIN_JNI_COMMON_H
#define REPLAYGAIN_JNI_COMMON_H

#include <jni.h>
#include <string>

// ─────────────────────────────────────────────────────────────────────────────
// Shared JNI helpers + error taxonomy for the native ReplayGain module.
//
// Every JNI entry point in replaygain_jni.cpp funnels failures through
// ReplayGainError so the Kotlin layer (ReplayGainNative.kt) gets a stable,
// documented error code instead of parsing exception messages.
// ─────────────────────────────────────────────────────────────────────────────

namespace replaygain {

// Mirrors dev.wndavenz.music.replaygain.ReplayGainError (Kotlin sealed class).
// Keep the integer values in sync — Kotlin maps them positionally.
enum class ErrorCode : int32_t {
    kOk                 = 0,
    kUnsupportedFormat  = 1,
    kCorruptedFile      = 2,
    kWriteFailure       = 3,
    kPermissionFailure  = 4,
    kFileNotFound       = 5,
    kInvalidArgument    = 6,
    kUnknown            = 7,
    // Appended — never renumber the values above. Returned by the fd-based
    // post-write verification step (see tag_writer.h) when a just-written
    // value doesn't read back as expected, or other metadata changed.
    kVerificationFailed = 8,
};

// Converts a jstring to a std::string. Returns empty string on null/OOM.
inline std::string JStringToStd(JNIEnv* env, jstring jstr) {
    if (jstr == nullptr) return {};
    const char* chars = env->GetStringUTFChars(jstr, nullptr);
    if (chars == nullptr) return {};
    std::string result(chars);
    env->ReleaseStringUTFChars(jstr, chars);
    return result;
}

inline jstring StdToJString(JNIEnv* env, const std::string& s) {
    return env->NewStringUTF(s.c_str());
}

}  // namespace replaygain

#endif  // REPLAYGAIN_JNI_COMMON_H
