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

// FIX Temuan #8 (LOW): ErrorCode was a dead duplicate of WriteResult (both
// defined the same integer constants with the same semantics). Every JNI
// entry point was already using WriteResult directly; ErrorCode was never
// referenced anywhere in the codebase. Removed to eliminate maintenance
// debt — if the Kotlin sealed class ever evolves, only WriteResult needs
// to stay in sync.

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
