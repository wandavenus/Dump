#ifndef NAR_AUTOMIX_PHASE_LOCK_H_
#define NAR_AUTOMIX_PHASE_LOCK_H_

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Returns the incoming deck's relative tempo factor (1 = unchanged), or NAN
// when the beat grids or timing inputs are invalid.
FFI_PLUGIN_EXPORT float nar_automix_phase_lock_factor(
    double outgoing_position_ms, double outgoing_phase_offset_ms,
    double outgoing_bpm, double incoming_position_ms,
    double incoming_phase_offset_ms, double incoming_bpm,
    double remaining_ms, double max_nudge);

// Phrase-aware phase lock factor (supports 4-beat / 16-beat downbeat alignment).
FFI_PLUGIN_EXPORT float nar_automix_phrase_lock_factor(
    double outgoing_position_ms, double outgoing_downbeat_offset_ms,
    double outgoing_bpm, double incoming_position_ms,
    double incoming_downbeat_offset_ms, double incoming_bpm,
    double remaining_ms, double max_nudge, int32_t beats_per_phrase);

#ifdef __cplusplus
}
#endif

#endif  // NAR_AUTOMIX_PHASE_LOCK_H_
