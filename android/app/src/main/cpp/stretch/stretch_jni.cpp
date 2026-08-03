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
#include <cfloat>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include <android/log.h>

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

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

#if defined(__aarch64__)
// Stereo-only NEON shuffles for the interleaved Media3 format
// [L0, R0, L1, R1, ...] and Signalsmith's planar format. These helpers are
// deliberately copy-only: they do not change floating-point values or the
// frame ratio, so the STFT algorithm and timeline remain untouched.
inline int deinterleaveStereoNeon(
        const float* interleaved, int frames, float* left, float* right) {
    int frame = 0;
    for (; frame + 4 <= frames; frame += 4) {
        const float32x4x2_t lr = vld2q_f32(interleaved + frame * 2);
        vst1q_f32(left + frame, lr.val[0]);
        vst1q_f32(right + frame, lr.val[1]);
    }
    return frame;
}

inline int interleaveStereoNeon(
        const float* left, const float* right, int frames, float* interleaved) {
    int frame = 0;
    for (; frame + 4 <= frames; frame += 4) {
        const float32x4_t l = vld1q_f32(left + frame);
        const float32x4_t r = vld1q_f32(right + frame);
        const float32x4_t maxFinite = vdupq_n_f32(FLT_MAX);
        const uint32x4_t lFinite = vcleq_f32(vabsq_f32(l), maxFinite);
        const uint32x4_t rFinite = vcleq_f32(vabsq_f32(r), maxFinite);

        // Keep the existing fail-open contract. A vector store is used only
        // when every lane is finite; otherwise the scalar path sanitizes the
        // affected samples to zero before writing them.
        if (vminvq_u32(lFinite) == UINT32_MAX &&
            vminvq_u32(rFinite) == UINT32_MAX) {
            float32x4x2_t lr = {l, r};
            vst2q_f32(interleaved + frame * 2, lr);
        } else {
            for (int i = 0; i < 4; ++i) {
                const float ls = std::isfinite(left[frame + i])
                    ? left[frame + i] : 0.0f;
                const float rs = std::isfinite(right[frame + i])
                    ? right[frame + i] : 0.0f;
                interleaved[(frame + i) * 2] = ls;
                interleaved[(frame + i) * 2 + 1] = rs;
            }
        }
    }
    return frame;
}
#endif

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

// FIX Temuan #6 (LOW): log throttle is now frame-counter based, not
// steady_clock based. steady_clock::now() is a syscall (clock_gettime) that
// adds non-deterministic latency to every audio callback; a simple cumulative
// frame counter costs one integer add and one integer comparison per buffer —
// indistinguishable from zero overhead. The effective interval is ~2 seconds
// at the sample rate stored in StretchHandle::sampleRate.
constexpr uint64_t kProcessLogFrameInterval = 96000;  // fallback when sampleRate==0

struct StretchHandle {
    signalsmith::stretch::SignalsmithStretch<float> stretch;
    int channels = 0;

    // FIX Temuan #6 (LOW): replaces steady_clock::now() throttle with a
    // frame counter. No syscall overhead on the audio thread.
    float    sampleRate = 48000.0f;         // stored from nativeCreate
    uint64_t totalFramesProcessed = 0;      // cumulative input frames since create
    uint64_t lastLoggedAtFrame    = 0;      // totalFramesProcessed at last log emission

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
    handle->channels    = channels;
    handle->sampleRate  = static_cast<float>(sampleRate);
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
    // FIX Temuan #7 (LOW): pre-warm scratch buffers on the non-audio creation
    // thread. ExoPlayer's typical render buffer is ≤ 4096 frames; pre-allocating
    // 8192 frames ensures ensureCapacity() finds sufficient capacity on every
    // subsequent audio-thread call and never triggers a heap allocation there.
    // The cost is ~channels × 2 × 8192 × 4 bytes (≈ 128 KB stereo) at create
    // time — negligible for a one-time setup call.
    constexpr int kPreallocFrames = 8192;
    handle->ensureCapacity(kPreallocFrames, kPreallocFrames);
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

    // FIX Temuan #6 (LOW): frame-counter throttle — no syscall on audio thread.
    h->totalFramesProcessed += static_cast<uint64_t>(inputFrames > 0 ? inputFrames : 0);
    const uint64_t logIntervalFrames = h->sampleRate > 0.0f
        ? static_cast<uint64_t>(h->sampleRate * 2.0f)
        : kProcessLogFrameInterval;
    const bool shouldLog =
        (h->totalFramesProcessed - h->lastLoggedAtFrame) >= logIntervalFrames;

    try {
        h->ensureCapacity(inputFrames, outputFrames);

        double inSumSq = 0.0;
        if (h->channels == 2 && !shouldLog) {
#if defined(__aarch64__)
            const int processed = deinterleaveStereoNeon(
                inSamples, inputFrames, h->inPtrs[0], h->inPtrs[1]);
#else
            const int processed = 0;
#endif
            for (int i = processed; i < inputFrames; ++i) {
                h->inPtrs[0][i] = inSamples[i * 2];
                h->inPtrs[1][i] = inSamples[i * 2 + 1];
            }
        } else {
            for (int i = 0; i < inputFrames; ++i) {
                for (int c = 0; c < h->channels; ++c) {
                    const float s = inSamples[i * h->channels + c];
                    h->inPtrs[c][i] = s;
                    if (shouldLog) inSumSq += static_cast<double>(s) * s;
                }
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
        if (h->channels == 2 && !shouldLog) {
#if defined(__aarch64__)
            const int processed = interleaveStereoNeon(
                h->outPtrs[0], h->outPtrs[1],
                outputFrames, outSamples);
#else
            const int processed = 0;
#endif
            for (int i = processed; i < outputFrames; ++i) {
                const float left = h->outPtrs[0][i];
                const float right = h->outPtrs[1][i];
                const bool leftFinite = std::isfinite(left);
                const bool rightFinite = std::isfinite(right);
                outSamples[i * 2] = leftFinite ? left : 0.0f;
                outSamples[i * 2 + 1] = rightFinite ? right : 0.0f;
            }
        } else {
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
            h->lastLoggedAtFrame = h->totalFramesProcessed;
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
// Primes the STFT engine's spectral-analysis+synthesis history without
// producing any audible output.
//
// Called once immediately before the first real nativeProcess() call after a
// bypass→STFT transition.  Feeding the last outputLatency() frames of bypass
// audio into the engine ensures its spectral history is populated with real
// signal so the first stretched output frame is a seamless continuation of
// the bypass audio — true zero-flicker transition.
//
// ── Why outputSamples = inputFrames, not 0 ───────────────────────────────
//
// Signalsmith Stretch's process() drives analysis from the OUTPUT loop:
//
//   for (int outputIndex = 0; outputIndex < outputSamples; ++outputIndex) {
//       if (newBlock) { /* FFT analyse + phase-vocoder synthesise */ }
//       write output sample;
//   }
//
// When outputSamples == 0 the loop body NEVER executes — for non-silent
// audio, no STFT analysis runs and the spectral history is NOT populated.
// (Silent audio takes a separate early-return path that does buffer input,
// which is why priming appeared to work sometimes but not always.)
//
// By requesting outputSamples == inputFrames the analysis+synthesis loop
// runs fully.  The output lands in h->outFlat (reused scratch) and is
// intentionally NOT copied back to the caller — it corresponds to the
// already-played bypass audio shifted by STFT latency, so discarding it
// is correct.  The engine's synthesis window is now fully warm.
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
        // Size both input AND output scratch for inputFrames — the output loop
        // must be able to write inputFrames samples per channel into h->outFlat.
        h->ensureCapacity(inputFrames, inputFrames);

        // Deinterleave input into planar scratch (same layout as nativeProcess).
        for (int i = 0; i < inputFrames; ++i)
            for (int c = 0; c < h->channels; ++c)
                h->inPtrs[c][i] = inSamples[i * h->channels + c];

        // Run the full analysis+synthesis loop.  Output lands in h->outFlat and
        // is discarded — we only want the side-effect of warming the engine's
        // spectral-synthesis history with real bypass signal.
        h->stretch.process(h->inPtrs.data(), inputFrames, h->outPtrs.data(), inputFrames);
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
