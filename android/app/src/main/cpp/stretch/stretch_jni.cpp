// ─────────────────────────────────────────────────────────────────────────
// JNI bridge for Signalsmith Stretch (pitch-shift / time-stretch engine).
//
// Backs dev.wndavenz.music.effects.SignalsmithStretchAudioProcessor, which
// fully replaces ExoPlayer's built-in SonicAudioProcessor for both playback
// speed and pitch shifting (see Media3PlaybackService.kt chain wiring).
//
// ── Ownership / threading model ──────────────────────────────────────────
//
//  One StretchHandle per ExoPlayer instance (primary + secondary/crossfade),
//  created in nativeCreate() when the processor is configured and destroyed
//  in nativeDestroy() when the processor is torn down. All JNI entry points
//  below are only ever called from a single ExoPlayer instance's own audio
//  rendering thread — SignalsmithStretch itself is NOT thread-safe and must
//  never be shared or called concurrently from two threads. Because each
//  ExoPlayer gets its own handle, this is naturally satisfied; do not turn
//  this into a shared/global handle the way the DSP pipeline's gain/bypass
//  state is shared, or two players processing during a crossfade would
//  race on the same StretchHandle.
//
// ── Deinterleaving ────────────────────────────────────────────────────────
//
//  ExoPlayer hands us interleaved float32 PCM ([L R L R ...]). Signalsmith
//  Stretch's process()/flush() expect planar per-channel buffers accessed as
//  buffer[channel][index]. We deinterleave into scratch buffers before the
//  call and re-interleave the result after. Scratch buffers are reused
//  across calls (grow-only) to avoid per-buffer heap churn on the audio
//  thread once warmed up.
//
// ── Failure handling ──────────────────────────────────────────────────────
//
//  Every entry point fails closed but never crashes: a null/invalid handle,
//  a null direct-buffer address, or an exception from the library returns
//  a negative status (or a safe default for accessors) and the Kotlin side
//  is responsible for treating that as "leave the output buffer empty /
//  unmodified" — see SignalsmithStretchAudioProcessor.kt. Non-finite output
//  samples are sanitized to 0 before being written back, matching the same
//  fail-open convention used by native_audio_runtime's DSP processors.
// ─────────────────────────────────────────────────────────────────────────

#include <jni.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include <android/log.h>

#include "signalsmith-stretch.h"

#define LOG_TAG "StretchNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ─────────────────────────────────────────────────────────────────────────
// System Log bridge (diagnostics feature — added per runtime-diagnostics
// request; does NOT alter any DSP behaviour below).
//
// Native code cannot reach the Dart-facing NativeLogger EventChannel
// directly, so every log point below also calls back into Kotlin via
// SignalsmithStretchAudioProcessor.nativeLog(level, message) (a plain
// @JvmStatic method), which forwards to NativeLogger.emit(...) — the same
// mechanism already used for every other native→System Log message in this
// app (see events/EventEmitter.kt + lib/services/log_service/native_log_bridge.dart).
// This keeps Logcat (__android_log_print) AND the in-app System Log in sync.
// ─────────────────────────────────────────────────────────────────────────

namespace {

std::mutex gLogMutex;
jclass gProcClass = nullptr;
jmethodID gLogMethodId = nullptr;

std::string ptrToHex(jlong p) {
    char buf[24];
    snprintf(buf, sizeof(buf), "0x%llx", static_cast<unsigned long long>(p));
    return std::string(buf);
}

// Calls SignalsmithStretchAudioProcessor.nativeLog(level, message) so the
// message also lands in the app's System Log screen, not just Logcat.
// Resolved and cached once (global ref); safe to call from any JNI entry
// point since each already carries a valid JNIEnv*.
void bridgeToSystemLog(JNIEnv *env, const char *level, const std::string &message) {
    std::lock_guard<std::mutex> lock(gLogMutex);
    if (gProcClass == nullptr) {
        jclass local = env->FindClass("dev/wndavenz/music/effects/SignalsmithStretchAudioProcessor");
        if (local == nullptr) {
            env->ExceptionClear();
            return;
        }
        gProcClass = static_cast<jclass>(env->NewGlobalRef(local));
        env->DeleteLocalRef(local);
        if (gProcClass != nullptr) {
            gLogMethodId = env->GetStaticMethodID(gProcClass, "nativeLog", "(Ljava/lang/String;Ljava/lang/String;)V");
            if (gLogMethodId == nullptr) env->ExceptionClear();
        }
    }
    if (gProcClass == nullptr || gLogMethodId == nullptr) return;

    jstring jLevel = env->NewStringUTF(level);
    jstring jMessage = env->NewStringUTF(message.c_str());
    env->CallStaticVoidMethod(gProcClass, gLogMethodId, jLevel, jMessage);
    if (env->ExceptionCheck()) env->ExceptionClear();
    env->DeleteLocalRef(jLevel);
    env->DeleteLocalRef(jMessage);
}

// Single entry point used by every log call below: writes to Logcat (for
// `adb logcat` users) AND bridges to the in-app System Log (rule 4).
// `msg` should NOT include the "[Stretch] " prefix — added once here (rule 7).
void slog(JNIEnv *env, const char *level, const std::string &msg) {
    const std::string full = std::string("[Stretch] ") + msg;
    if (std::strcmp(level, "error") == 0) {
        LOGE("%s", full.c_str());
    } else if (std::strcmp(level, "warn") == 0) {
        LOGW("%s", full.c_str());
    } else {
        LOGI("%s", full.c_str());
    }
    bridgeToSystemLog(env, level, full);
}

// Defensive upper bound — real content is mono/stereo/5.1/7.1 at most.
// Rejecting anything above this in nativeCreate() avoids unbounded
// allocation from a malformed AudioFormat.
constexpr int kMaxChannels = 8;

// nativeProcess() logging (RMS + call summary) is throttled to at most once
// every 2 seconds per handle (rule 6) — see StretchHandle::lastProcessLogTime.
constexpr auto kProcessLogInterval = std::chrono::milliseconds(2000);

struct StretchHandle {
    signalsmith::stretch::SignalsmithStretch<float> stretch;
    int channels = 0;

    // Diagnostics only — last time nativeProcess() emitted its throttled
    // RMS/summary log. Default-constructed to the clock epoch so the very
    // first call always logs. Never read/written outside the single audio
    // thread that owns this handle (see class doc in the .kt file).
    std::chrono::steady_clock::time_point lastProcessLogTime{};

    // Flat planar scratch storage, reused (grow-only) across calls.
    // inPtrs[c]/outPtrs[c] are recomputed on every call from the CURRENT
    // call's frame counts, so stale pointers from a previous (possibly
    // larger) call never alias between channels — see ensureCapacity().
    std::vector<float> inFlat;
    std::vector<float> outFlat;
    std::vector<float *> inPtrs;
    std::vector<float *> outPtrs;

    void ensureCapacity(int inFrames, int outFrames) {
        if (static_cast<int>(inPtrs.size()) != channels) inPtrs.resize(channels);
        if (static_cast<int>(outPtrs.size()) != channels) outPtrs.resize(channels);

        const size_t inNeeded = static_cast<size_t>(channels) * static_cast<size_t>(std::max(inFrames, 0));
        const size_t outNeeded = static_cast<size_t>(channels) * static_cast<size_t>(std::max(outFrames, 0));
        if (inFlat.size() < inNeeded) inFlat.resize(inNeeded);
        if (outFlat.size() < outNeeded) outFlat.resize(outNeeded);

        for (int c = 0; c < channels; ++c) {
            inPtrs[c] = inFlat.data() + static_cast<size_t>(c) * static_cast<size_t>(std::max(inFrames, 0));
            outPtrs[c] = outFlat.data() + static_cast<size_t>(c) * static_cast<size_t>(std::max(outFrames, 0));
        }
    }
};

inline StretchHandle *fromPtr(jlong handlePtr) {
    return reinterpret_cast<StretchHandle *>(static_cast<intptr_t>(handlePtr));
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeCreate(
        JNIEnv *env, jclass, jint sampleRate, jint channels) {
    slog(env, "info", "nativeCreate sampleRate=" + std::to_string(sampleRate) + " channels=" + std::to_string(channels));
    if (sampleRate <= 0 || channels <= 0 || channels > kMaxChannels) {
        slog(env, "warn", "nativeCreate rejecting invalid params sampleRate=" + std::to_string(sampleRate) +
                               " channels=" + std::to_string(channels));
        return 0;
    }
    auto *handle = new (std::nothrow) StretchHandle();
    if (handle == nullptr) {
        slog(env, "error", "nativeCreate allocation failed");
        return 0;
    }
    handle->channels = channels;
    try {
        // presetDefault(): ~120ms block / ~30ms interval — the library's
        // general-purpose preset, a good default for full-range music.
        slog(env, "info", "presetDefault() channels=" + std::to_string(channels) + " sampleRate=" + std::to_string(sampleRate));
        handle->stretch.presetDefault(channels, static_cast<float>(sampleRate));
    } catch (...) {
        slog(env, "error", "nativeCreate presetDefault() threw");
        delete handle;
        return 0;
    }
    const jlong ptr = static_cast<jlong>(reinterpret_cast<intptr_t>(handle));
    slog(env, "info", "nativeCreate succeeded pointer=" + ptrToHex(ptr));
    return ptr;
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeDestroy(
        JNIEnv *env, jclass, jlong handlePtr) {
    slog(env, "info", "nativeDestroy pointer=" + ptrToHex(handlePtr));
    delete fromPtr(handlePtr);
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeReset(
        JNIEnv *env, jclass, jlong handlePtr) {
    slog(env, "info", "nativeReset pointer=" + ptrToHex(handlePtr));
    auto *h = fromPtr(handlePtr);
    if (h == nullptr) return;
    try {
        h->stretch.reset();
    } catch (...) {
        slog(env, "error", "nativeReset reset() threw pointer=" + ptrToHex(handlePtr));
    }
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeSetPitchSemitones(
        JNIEnv *env, jclass, jlong handlePtr, jfloat semitones) {
    auto *h = fromPtr(handlePtr);
    if (h == nullptr) {
        slog(env, "warn", "nativeSetPitchSemitones null handle pointer=" + ptrToHex(handlePtr));
        return;
    }
    if (!std::isfinite(semitones)) semitones = 0.0f;
    {
        char buf[96];
        snprintf(buf, sizeof(buf), "setTransposeSemitones() pointer=%s semitones=%.3f", ptrToHex(handlePtr).c_str(), semitones);
        slog(env, "info", buf);
    }
    try {
        h->stretch.setTransposeSemitones(semitones);
    } catch (...) {
        slog(env, "error", "nativeSetPitchSemitones threw pointer=" + ptrToHex(handlePtr));
    }
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeOutputLatencyFrames(
        JNIEnv *env, jclass, jlong handlePtr) {
    auto *h = fromPtr(handlePtr);
    if (h == nullptr) return 0;
    try {
        const int latency = h->stretch.outputLatency();
        slog(env, "info", "nativeOutputLatencyFrames pointer=" + ptrToHex(handlePtr) + " latency=" + std::to_string(latency));
        return latency;
    } catch (...) {
        slog(env, "error", "nativeOutputLatencyFrames threw pointer=" + ptrToHex(handlePtr));
        return 0;
    }
}

// Processes exactly `inputFrames` interleaved input frames into exactly
// `outputFrames` interleaved output frames (the input/output ratio is how
// Signalsmith Stretch realises time-stretching — see README "Time-stretching").
// Returns 0 on success, negative on failure (Kotlin side treats this as
// "emit nothing for this call" — fail-open, never garbage audio).
//
// Diagnostics (RMS + call summary) are throttled to at most once every 2s
// per handle (rule 6) via StretchHandle::lastProcessLogTime — this adds no
// extra per-sample work on the throttled-out calls beyond one clock read.
JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeProcess(
        JNIEnv *env, jclass, jlong handlePtr,
        jobject inputBuffer, jint inputFrames,
        jobject outputBuffer, jint outputFrames) {
    auto *h = fromPtr(handlePtr);
    if (h == nullptr || inputFrames < 0 || outputFrames < 0) {
        slog(env, "warn", "nativeProcess invalid args pointer=" + ptrToHex(handlePtr) +
                               " inputFrames=" + std::to_string(inputFrames) + " outputFrames=" + std::to_string(outputFrames));
        return -1;
    }

    auto *inSamples = static_cast<float *>(env->GetDirectBufferAddress(inputBuffer));
    auto *outSamples = static_cast<float *>(env->GetDirectBufferAddress(outputBuffer));
    if (inSamples == nullptr || outSamples == nullptr) {
        slog(env, "error", "nativeProcess GetDirectBufferAddress returned null pointer=" + ptrToHex(handlePtr));
        return -1;
    }

    const auto now = std::chrono::steady_clock::now();
    const bool shouldLog = (now - h->lastProcessLogTime) >= kProcessLogInterval;

    try {
        h->ensureCapacity(inputFrames, outputFrames);

        double inSumSq = 0.0;
        for (int i = 0; i < inputFrames; ++i) {
            for (int c = 0; c < h->channels; ++c) {
                const float s = inSamples[i * h->channels + c];
                h->inPtrs[c][i] = s;
                if (shouldLog) inSumSq += static_cast<double>(s) * s;
            }
        }

        if (shouldLog) {
            slog(env, "info",
                 "process() pointer=" + ptrToHex(handlePtr) + " inputFrames=" + std::to_string(inputFrames) +
                     " outputFrames=" + std::to_string(outputFrames) + " channels=" + std::to_string(h->channels));
        }

        h->stretch.process(h->inPtrs.data(), inputFrames, h->outPtrs.data(), outputFrames);

        bool hasNonFinite = false;
        double outSumSq = 0.0;
        for (int i = 0; i < outputFrames; ++i) {
            for (int c = 0; c < h->channels; ++c) {
                const float s = h->outPtrs[c][i];
                const bool finite = std::isfinite(s);
                if (!finite) hasNonFinite = true;
                const float safe = finite ? s : 0.0f;
                outSamples[i * h->channels + c] = safe;
                if (shouldLog) outSumSq += static_cast<double>(safe) * safe;
            }
        }

        if (shouldLog) {
            const long inCount = static_cast<long>(inputFrames) * h->channels;
            const long outCount = static_cast<long>(outputFrames) * h->channels;
            const double inRms = inCount > 0 ? std::sqrt(inSumSq / inCount) : 0.0;
            const double outRms = outCount > 0 ? std::sqrt(outSumSq / outCount) : 0.0;

            char buf[64];
            snprintf(buf, sizeof(buf), "RMS in=%.4f", inRms);
            slog(env, "info", buf);
            snprintf(buf, sizeof(buf), "RMS out=%.4f", outRms);
            slog(env, "info", buf);

            if (outCount > 0 && outRms == 0.0) {
                slog(env, "warn", "nativeProcess output RMS is zero pointer=" + ptrToHex(handlePtr));
            }
            if (hasNonFinite) {
                slog(env, "warn", "nativeProcess NaN/Inf detected in output pointer=" + ptrToHex(handlePtr));
            }
            // Logging-only (no behaviour change): Signalsmith Stretch's process()
            // contract always fills exactly `outputFrames` (see signalsmith-stretch.h
            // process(): the outputIndex loop runs unconditionally for the full
            // requested outputSamples, with no early-exit that writes fewer), so
            // "actual frames written" is always equal to the requested outputFrames
            // on this success path — logged explicitly per the runtime-audit request
            // rather than left implicit.
            slog(env, "info",
                 "nativeProcess actualFramesWritten=" + std::to_string(outputFrames) +
                     " returnValue=0 pointer=" + ptrToHex(handlePtr));
            h->lastProcessLogTime = now;
        }
    } catch (...) {
        slog(env, "error", "nativeProcess exception during process() pointer=" + ptrToHex(handlePtr) +
                                " actualFramesWritten=0 returnValue=-1");
        return -1;
    }
    return 0;
}

// Feeds `inputFrames` interleaved input frames into the STFT engine with
// ZERO output requested — "priming" the engine's spectral-analysis history
// without producing any audible output.
//
// Called once, immediately before the first real nativeProcess() call after
// a bypass→STFT transition (speed/pitch leaving their unity values).  By
// feeding the engine the last outputLatency() frames of bypass audio (plain
// 1:1 copy that was already sent to the AudioTrack), the STFT's spectral
// history is populated with real signal rather than zero-padded silence.
// This makes the first stretched output frame indistinguishable from a
// seamless continuation — zero-flicker bypass→STFT transitions.
//
// Signalsmith Stretch's process() contract: when outputSamples == 0 the
// output loop body executes zero times and no output pointer is ever
// dereferenced, so passing a stub output array is safe.
JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativePrime(
        JNIEnv *env, jclass, jlong handlePtr,
        jobject inputBuffer, jint inputFrames) {
    auto *h = fromPtr(handlePtr);
    if (h == nullptr || inputFrames <= 0) {
        slog(env, "warn", "nativePrime invalid args pointer=" + ptrToHex(handlePtr) +
             " inputFrames=" + std::to_string(inputFrames));
        return -1;
    }

    auto *inSamples = static_cast<float *>(env->GetDirectBufferAddress(inputBuffer));
    if (inSamples == nullptr) {
        slog(env, "error", "nativePrime GetDirectBufferAddress null pointer=" + ptrToHex(handlePtr));
        return -1;
    }

    slog(env, "info", "nativePrime pointer=" + ptrToHex(handlePtr) +
         " primeFrames=" + std::to_string(inputFrames));

    try {
        // ensureCapacity(in, 1): guarantees outFlat is non-empty so outPtrs[c]
        // is a valid non-null pointer even though process() writes 0 output frames.
        h->ensureCapacity(inputFrames, 1);

        // Deinterleave into planar scratch (same layout as nativeProcess).
        for (int i = 0; i < inputFrames; ++i)
            for (int c = 0; c < h->channels; ++c)
                h->inPtrs[c][i] = inSamples[i * h->channels + c];

        // Feed into STFT analysis with outputSamples=0 — populates spectral
        // history without writing any output.  outPtrs are valid but never
        // written (process() loop body runs 0 times when outputSamples==0).
        h->stretch.process(h->inPtrs.data(), inputFrames, h->outPtrs.data(), 0);
    } catch (...) {
        slog(env, "error", "nativePrime exception pointer=" + ptrToHex(handlePtr));
        return -1;
    }

    slog(env, "info", "nativePrime completed pointer=" + ptrToHex(handlePtr) +
         " primeFrames=" + std::to_string(inputFrames) + " result=0");
    return 0;
}

// End-of-stream drain: produces the final `outputFrames` of output still
// buffered inside the STFT pipeline (Signalsmith Stretch's flush() already
// internally zero-pads as needed — see README "Ending").
JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeFlush(
        JNIEnv *env, jclass, jlong handlePtr,
        jobject outputBuffer, jint outputFrames) {
    auto *h = fromPtr(handlePtr);
    if (h == nullptr || outputFrames < 0) {
        slog(env, "warn", "nativeFlush invalid args pointer=" + ptrToHex(handlePtr) + " frames=" + std::to_string(outputFrames));
        return -1;
    }

    auto *outSamples = static_cast<float *>(env->GetDirectBufferAddress(outputBuffer));
    if (outSamples == nullptr) {
        slog(env, "error", "nativeFlush GetDirectBufferAddress returned null pointer=" + ptrToHex(handlePtr));
        return -1;
    }

    slog(env, "info", "flush() pointer=" + ptrToHex(handlePtr) + " frames=" + std::to_string(outputFrames));

    try {
        h->ensureCapacity(0, outputFrames);
        h->stretch.flush(h->outPtrs.data(), outputFrames);
        for (int i = 0; i < outputFrames; ++i) {
            for (int c = 0; c < h->channels; ++c) {
                const float s = h->outPtrs[c][i];
                outSamples[i * h->channels + c] = std::isfinite(s) ? s : 0.0f;
            }
        }
    } catch (...) {
        slog(env, "error", "nativeFlush exception during flush() pointer=" + ptrToHex(handlePtr) + " result=-1");
        return -1;
    }
    slog(env, "info", "nativeFlush completed pointer=" + ptrToHex(handlePtr) + " frames=" + std::to_string(outputFrames) + " result=0");
    return 0;
}

}  // extern "C"
