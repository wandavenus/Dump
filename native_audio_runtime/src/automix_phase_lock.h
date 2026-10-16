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

#define NAR_AUTOMIX_TRACKER_WINDOW 128

typedef struct NarAutomixBeatTracker {
  float onset_history[NAR_AUTOMIX_TRACKER_WINDOW];
  int32_t write_pos;
  int32_t total_samples;
  double offline_bpm;
  double live_bpm;
  double live_phase_ms;
  double confidence;
  int32_t sample_rate;
} NarAutomixBeatTracker;

FFI_PLUGIN_EXPORT void nar_automix_tracker_init(
    NarAutomixBeatTracker* tracker, double offline_bpm, int32_t sample_rate);

FFI_PLUGIN_EXPORT void nar_automix_tracker_reset(
    NarAutomixBeatTracker* tracker);

FFI_PLUGIN_EXPORT void nar_automix_tracker_process_frame(
    NarAutomixBeatTracker* tracker, float energy, double current_time_ms);

FFI_PLUGIN_EXPORT float nar_automix_tracker_get_nudge(
    NarAutomixBeatTracker* tracker, double target_bpm, double max_nudge);

#ifdef __cplusplus
}
#endif

#endif  // NAR_AUTOMIX_PHASE_LOCK_H_
