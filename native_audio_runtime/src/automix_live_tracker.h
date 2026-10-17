#ifndef NAR_AUTOMIX_LIVE_TRACKER_H_
#define NAR_AUTOMIX_LIVE_TRACKER_H_
#include <stdint.h>
#include "native_audio_runtime.h"
#ifdef __cplusplus
extern "C" {
#endif
#define NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT 2
#define NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT 3
// Output order: BPM, elapsed ms since latest beat pulse, confidence [0,1].
// Realtime tracking is per deck, bounded, allocation-free and lock-free in process().
FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_process(
    const float* interleaved_pcm, int32_t frame_count, int32_t channel_count,
    int32_t sample_rate, int32_t stream_slot);
FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_get(
    int32_t stream_slot, double* output, int32_t output_count);
// Request reset on the deck's next audio callback; never blocks the caller.
FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_reset(int32_t stream_slot);
#ifdef __cplusplus
}
#endif
#endif
