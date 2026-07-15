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
#include <cmath>
#include <cstring>
#include <new>
#include <vector>

#include <android/log.h>

#include "signalsmith-stretch.h"

#define LOG_TAG "StretchNative"
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

// Defensive upper bound — real content is mono/stereo/5.1/7.1 at most.
// Rejecting anything above this in nativeCreate() avoids unbounded
// allocation from a malformed AudioFormat.
constexpr int kMaxChannels = 8;

struct StretchHandle {
    signalsmith::stretch::SignalsmithStretch<float> stretch;
    int channels = 0;

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
        JNIEnv *, jclass, jint sampleRate, jint channels) {
    if (sampleRate <= 0 || channels <= 0 || channels > kMaxChannels) {
        LOGW("nativeCreate: rejecting invalid params sampleRate=%d channels=%d", sampleRate, channels);
        return 0;
    }
    auto *handle = new (std::nothrow) StretchHandle();
    if (handle == nullptr) {
        LOGE("nativeCreate: allocation failed");
        return 0;
    }
    handle->channels = channels;
    try {
        // presetDefault(): ~120ms block / ~30ms interval — the library's
        // general-purpose preset, a good default for full-range music.
        handle->stretch.presetDefault(channels, static_cast<float>(sampleRate));
    } catch (...) {
        LOGE("nativeCreate: presetDefault() threw");
        delete handle;
        return 0;
    }
    return static_cast<jlong>(reinterpret_cast<intptr_t>(handle));
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeDestroy(
        JNIEnv *, jclass, jlong handlePtr) {
    delete fromPtr(handlePtr);
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeReset(
        JNIEnv *, jclass, jlong handlePtr) {
    auto *h = fromPtr(handlePtr);
    if (h == nullptr) return;
    try {
        h->stretch.reset();
    } catch (...) {
        LOGE("nativeReset: reset() threw");
    }
}

JNIEXPORT void JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeSetPitchSemitones(
        JNIEnv *, jclass, jlong handlePtr, jfloat semitones) {
    auto *h = fromPtr(handlePtr);
    if (h == nullptr) return;
    if (!std::isfinite(semitones)) semitones = 0.0f;
    try {
        h->stretch.setTransposeSemitones(semitones);
    } catch (...) {
        LOGE("nativeSetPitchSemitones: threw");
    }
}

JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeOutputLatencyFrames(
        JNIEnv *, jclass, jlong handlePtr) {
    auto *h = fromPtr(handlePtr);
    if (h == nullptr) return 0;
    try {
        return h->stretch.outputLatency();
    } catch (...) {
        return 0;
    }
}

// Processes exactly `inputFrames` interleaved input frames into exactly
// `outputFrames` interleaved output frames (the input/output ratio is how
// Signalsmith Stretch realises time-stretching — see README "Time-stretching").
// Returns 0 on success, negative on failure (Kotlin side treats this as
// "emit nothing for this call" — fail-open, never garbage audio).
JNIEXPORT jint JNICALL
Java_dev_wndavenz_music_effects_SignalsmithStretchAudioProcessor_nativeProcess(
        JNIEnv *env, jclass, jlong handlePtr,
        jobject inputBuffer, jint inputFrames,
        jobject outputBuffer, jint outputFrames) {
    auto *h = fromPtr(handlePtr);
    if (h == nullptr || inputFrames < 0 || outputFrames < 0) return -1;

    auto *inSamples = static_cast<float *>(env->GetDirectBufferAddress(inputBuffer));
    auto *outSamples = static_cast<float *>(env->GetDirectBufferAddress(outputBuffer));
    if (inSamples == nullptr || outSamples == nullptr) {
        LOGE("nativeProcess: GetDirectBufferAddress returned null");
        return -1;
    }

    try {
        h->ensureCapacity(inputFrames, outputFrames);

        for (int i = 0; i < inputFrames; ++i) {
            for (int c = 0; c < h->channels; ++c) {
                h->inPtrs[c][i] = inSamples[i * h->channels + c];
            }
        }

        h->stretch.process(h->inPtrs.data(), inputFrames, h->outPtrs.data(), outputFrames);

        for (int i = 0; i < outputFrames; ++i) {
            for (int c = 0; c < h->channels; ++c) {
                const float s = h->outPtrs[c][i];
                outSamples[i * h->channels + c] = std::isfinite(s) ? s : 0.0f;
            }
        }
    } catch (...) {
        LOGE("nativeProcess: exception during process()");
        return -1;
    }
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
    if (h == nullptr || outputFrames < 0) return -1;

    auto *outSamples = static_cast<float *>(env->GetDirectBufferAddress(outputBuffer));
    if (outSamples == nullptr) {
        LOGE("nativeFlush: GetDirectBufferAddress returned null");
        return -1;
    }

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
        LOGE("nativeFlush: exception during flush()");
        return -1;
    }
    return 0;
}

}  // extern "C"
