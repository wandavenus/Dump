// Per-stream AutoMix three-band isolator and crossfade gain stage.
#ifndef NAR_AUTOMIX_TONE_PROCESSOR_H_
#define NAR_AUTOMIX_TONE_PROCESSOR_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NAR_AUTOMIX_TONE_STREAM_COUNT 2
#define NAR_AUTOMIX_TONE_MAX_CHANNELS 8

// Keep offsets fixed: automix_tone_neon.S reads/writes this state directly.
typedef struct NarAutomixToneState {
  float low_pass_state[NAR_AUTOMIX_TONE_MAX_CHANNELS];  // offset 0
  float high_cut_state[NAR_AUTOMIX_TONE_MAX_CHANNELS];  // offset 32
  float low_pass_alpha;                                 // offset 64
  float high_cut_alpha;                                 // offset 68
  float gain_smoothing_alpha;                           // offset 72
  float current_bass_gain;                              // offset 76
  float current_high_gain;                              // offset 80
  int32_t sample_rate;                                  // offset 84
  int32_t channel_count;                                // offset 88
  float current_fade_gain;                              // offset 92
  int32_t configured;                                   // offset 96
  float current_mid_gain;                               // offset 100
  // True-peak limiter state. Appended after the NEON-visible fields; the
  // assembly never reads beyond offset 100.
  float true_peak_gain;                                 // offset 104
  float true_peak_release_alpha;                        // offset 108
  float true_peak_history[NAR_AUTOMIX_TONE_MAX_CHANNELS][4];  // offset 112
  int32_t true_peak_primed;                             // offset 240
} NarAutomixToneState;

// Configure/reset are lifecycle calls; never call configure concurrently with
// process on the same stream. Target setters are lock-free and safe from the
// control thread while each stream's audio thread is processing.
FFI_PLUGIN_EXPORT int32_t nar_automix_tone_configure(
    int32_t stream_slot, int32_t sample_rate, int32_t channel_count);
FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_bass_gain(
    int32_t stream_slot, float gain);
FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_mid_gain(
    int32_t stream_slot, float gain);
FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_high_gain(
    int32_t stream_slot, float gain);
FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_fade_gain(
    int32_t stream_slot, float gain);
// Enables the per-deck true-peak limiter for the given ceiling (0 < ceiling
// <= 1). A ceiling <= 0 or a non-finite value disables it and leaves the
// stream bit-transparent. Disabled by default.
FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_true_peak_limit(
    int32_t stream_slot, float ceiling);
FFI_PLUGIN_EXPORT int32_t nar_automix_tone_compute_fade_gains(
    float progress, float gamma, float outgoing_trim, float incoming_trim,
    float* outgoing_gain, float* incoming_gain);
FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_crossfade_gains(
    int32_t outgoing_slot, int32_t incoming_slot, float progress, float gamma,
    float outgoing_trim, float incoming_trim);
FFI_PLUGIN_EXPORT int32_t nar_automix_tone_reset(int32_t stream_slot);

// In-place float32 interleaved PCM. Returns 1 on success, 0 on invalid or
// unconfigured input. Does not allocate, lock, or modify another stream slot.
FFI_PLUGIN_EXPORT int32_t nar_automix_tone_process(
    float* interleaved, int32_t frame_count, int32_t channel_count,
    int32_t stream_slot);

#ifdef __cplusplus
}
#endif

#endif  // NAR_AUTOMIX_TONE_PROCESSOR_H_
