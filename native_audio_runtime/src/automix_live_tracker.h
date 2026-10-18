#ifndef NAR_AUTOMIX_LIVE_TRACKER_H_
#define NAR_AUTOMIX_LIVE_TRACKER_H_
#include <stdint.h>
#include "native_audio_runtime.h"
#ifdef __cplusplus
extern "C" {
#endif
#define NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT 2
#define NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT 6
// Output order: BPM, elapsed ms since latest beat pulse, confidence [0,1],
// elapsed ms since the latest estimated downbeat, downbeat confidence [0,1],
// recent energy trend in [-1,1] (positive = the section is building up).
// Realtime tracking is per deck, bounded, allocation-free and non-blocking in
// process() (the publish path uses a try-lock and skips a callback under
// contention). get() returns a seqlock-consistent snapshot of one estimate.
// Tracking is off by default and must be enabled only while AutoMix can use it.
FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_set_enabled(int32_t enabled);
FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_is_enabled(void);
FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_process(
    const float* interleaved_pcm, int32_t frame_count, int32_t channel_count,
    int32_t sample_rate, int32_t stream_slot);
FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_get(
    int32_t stream_slot, double* output, int32_t output_count);
// Request reset on the deck's next audio callback; never blocks the caller.
// Also bumps the tracking epoch so an in-flight callback cannot republish
// pre-reset phase.
FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_reset(int32_t stream_slot);
#ifdef __cplusplus
}
#endif
#endif
