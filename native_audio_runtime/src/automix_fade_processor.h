// Sample-timeline AutoMix fade processor for interleaved float32 PCM.
#ifndef NAR_AUTOMIX_FADE_PROCESSOR_H_
#define NAR_AUTOMIX_FADE_PROCESSOR_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NAR_AUTOMIX_FADE_STREAM_COUNT 2
#define NAR_AUTOMIX_FADE_MAX_CHANNELS 8

typedef enum NarAutomixFadeDirection {
  NAR_AUTOMIX_FADE_OUTGOING = 0,
  NAR_AUTOMIX_FADE_INCOMING = 1,
} NarAutomixFadeDirection;

typedef struct NarAutomixFadeStatus {
  int32_t configured;
  int32_t armed;
  int32_t failed;
  int64_t processed_frames;
  uint64_t process_calls;
  float current_gain;
} NarAutomixFadeStatus;

// Lifecycle calls are serialized with the corresponding Media3 processor
// lifecycle. Setters and arm/disarm are control-thread calls; process is called
// only from the deck's audio thread.
FFI_PLUGIN_EXPORT int32_t nar_automix_fade_configure(
    int32_t stream_slot, int32_t sample_rate, int32_t channel_count);

// The next audio block starts at this media-timeline position. This is a
// discontinuity contract for seeks and new media items, not a wall-clock
// timestamp. The audio thread applies it at a block boundary.
FFI_PLUGIN_EXPORT int32_t nar_automix_fade_set_timeline_position_ms(
    int32_t stream_slot, int64_t position_ms);

// Arm a fade at an absolute media position in the current item. The processor
// computes the envelope from PCM frame indices, so decoded-ahead buffers do not
// move the audible fade phase. A zero/negative duration is rejected so callers
// use the Kotlin fallback for degenerate transitions.
FFI_PLUGIN_EXPORT int32_t nar_automix_fade_arm(
    int32_t stream_slot, int64_t start_position_ms, int64_t duration_ms,
    float gamma, float outgoing_trim, float incoming_trim,
    int32_t direction);

FFI_PLUGIN_EXPORT int32_t nar_automix_fade_disarm(int32_t stream_slot);
FFI_PLUGIN_EXPORT int32_t nar_automix_fade_reset(int32_t stream_slot);

// In-place interleaved float32 PCM. The same gain is applied to every channel
// in a frame, preserving channel order and the stereo image.
FFI_PLUGIN_EXPORT int32_t nar_automix_fade_process(
    float* interleaved, int32_t frame_count, int32_t channel_count,
    int32_t stream_slot);

FFI_PLUGIN_EXPORT int32_t nar_automix_fade_get_status(
    int32_t stream_slot, NarAutomixFadeStatus* status);

#ifdef __cplusplus
}
#endif

#endif  // NAR_AUTOMIX_FADE_PROCESSOR_H_
