// ─────────────────────────────────────────────────────────────────────────────
// pcm_native — real-time PCM conversion, resampling and stereo bus mixing.
//
// This module owns the sample-domain work of the dual-player / single
// AudioTrack path:
//
//   decoder PCM (any supported encoding) ──► DeckConverter
//        ──► stereo float at the shared bus rate (windowed-sinc resampler)
//        ──► per-deck ring (Kotlin, timeline metadata only)
//        ──► StereoMixer (gain ramp + sum + bus limiter)
//        ──► the one Media3 DefaultAudioSink / AudioTrack
//
// All hot loops are allocation-free after warm-up. ARM64 builds use NEON
// intrinsics for the common decoder formats (U8/S16/S32/F32), stereo
// downmix/copy, and bus summation. Other ABIs use equivalent scalar code.
//
// Ownership / threading:
//   • One DeckConverter per deck. It is called only by that deck's ExoPlayer
//     renderer thread.
//   • One StereoMixer per engine. It is called only by the engine's single mix
//     thread (the only caller of the hardware sink).
//   • No locks, no file I/O and no logging on the process path.
// ─────────────────────────────────────────────────────────────────────────────

#ifndef NOISEGRAPH_PCM_NATIVE_H
#define NOISEGRAPH_PCM_NATIVE_H

#include <cstdint>

#if defined(__cplusplus)
extern "C" {
#endif

// Keep in sync with PcmSampleFormat in PcmConversions.kt. The numeric values
// are part of the JNI contract; never renumber them.
enum NarPcmFormat {
    NAR_PCM_U8 = 0,
    NAR_PCM_S16 = 1,
    NAR_PCM_S24 = 2,
    NAR_PCM_S32 = 3,
    NAR_PCM_F32 = 4,
    NAR_PCM_F64 = 5,
};

// Return values for the JNI-facing entry points. Positive values are frame
// counts, so every error is negative.
enum NarPcmStatus {
    NAR_PCM_ERROR = -1,
    NAR_PCM_ERROR_ARGUMENT = -2,
    NAR_PCM_ERROR_MEMORY = -3,
};

#define NAR_PCM_BUS_CHANNELS 2

// Opaque C++ objects. The JNI layer passes them as jlong handles.
typedef struct NarDeckConverter NarDeckConverter;
typedef struct NarStereoMixer NarStereoMixer;

NarDeckConverter* nar_deck_converter_create(
    int input_rate,
    int output_rate,
    int taps,
    int phases);

void nar_deck_converter_destroy(NarDeckConverter* converter);

void nar_deck_converter_reset(NarDeckConverter* converter);

int nar_deck_converter_max_output_frames(
    const NarDeckConverter* converter,
    int input_frames);

// Converts input_frames interleaved frames from `input` to stereo float at the
// converter's output rate. Writes at most output_capacity_frames frames to
// `output` and returns the number written, or a negative NarPcmStatus.
int nar_deck_converter_process(
    NarDeckConverter* converter,
    const void* input,
    int input_frames,
    int channels,
    int format,
    int big_endian,
    float* output,
    int output_capacity_frames);

NarStereoMixer* nar_stereo_mixer_create(int sample_rate, int max_frames);

void nar_stereo_mixer_destroy(NarStereoMixer* mixer);

void nar_stereo_mixer_reset(NarStereoMixer* mixer);

// Mixes up to two stereo float decks with a per-frame gain ramp and applies
// the post-sum safety limiter in place. `active_mask` bit 0 selects deck 0,
// bit 1 selects deck 1. `gains` and `targets` are two-element arrays; `gains`
// is updated in place. Returns 1 on success, 0 on an invalid argument.
int nar_stereo_mixer_process(
    NarStereoMixer* mixer,
    const float* deck0,
    const float* deck1,
    unsigned int active_mask,
    int frames,
    float* gains,
    const float* targets,
    float* output);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // NOISEGRAPH_PCM_NATIVE_H
