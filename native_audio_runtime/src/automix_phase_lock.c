#include "automix_phase_lock.h"

#include <math.h>
#include <stddef.h>

#define NAR_AUTOMIX_MIN_BPM 50.0
#define NAR_AUTOMIX_MAX_BPM 250.0
#define NAR_AUTOMIX_DEAD_ZONE_MS 6.0
#define NAR_AUTOMIX_MIN_REMAINING_MS 300.0

static double fold_phase(double value_ms, double beat_ms) {
  double phase = fmod(value_ms, beat_ms);
  if (phase < 0.0) phase += beat_ms;
  return phase;
}

float nar_automix_phase_lock_factor(
    double outgoing_position_ms, double outgoing_phase_offset_ms,
    double outgoing_bpm, double incoming_position_ms,
    double incoming_phase_offset_ms, double incoming_bpm,
    double remaining_ms, double max_nudge) {
  if (!isfinite(outgoing_position_ms) || !isfinite(outgoing_phase_offset_ms) ||
      !isfinite(outgoing_bpm) || !isfinite(incoming_position_ms) ||
      !isfinite(incoming_phase_offset_ms) || !isfinite(incoming_bpm) ||
      !isfinite(remaining_ms) || !isfinite(max_nudge) ||
      outgoing_bpm < NAR_AUTOMIX_MIN_BPM ||
      outgoing_bpm > NAR_AUTOMIX_MAX_BPM ||
      incoming_bpm < NAR_AUTOMIX_MIN_BPM ||
      incoming_bpm > NAR_AUTOMIX_MAX_BPM) {
    return NAN;
  }

  const double outgoing_beat_ms = 60000.0 / outgoing_bpm;
  const double incoming_beat_ms = 60000.0 / incoming_bpm;
  const double outgoing_phase =
      fold_phase(outgoing_position_ms - outgoing_phase_offset_ms,
                 outgoing_beat_ms) /
      outgoing_beat_ms;
  const double incoming_phase =
      fold_phase(incoming_position_ms - incoming_phase_offset_ms,
                 incoming_beat_ms) /
      incoming_beat_ms;
  double error_ms = (incoming_phase - outgoing_phase) * incoming_beat_ms;
  if (error_ms > incoming_beat_ms * 0.5) error_ms -= incoming_beat_ms;
  if (error_ms < -incoming_beat_ms * 0.5) error_ms += incoming_beat_ms;
  if (!isfinite(error_ms)) return NAN;

  const double limit = fabs(max_nudge);
  if (fabs(error_ms) < NAR_AUTOMIX_DEAD_ZONE_MS ||
      remaining_ms < NAR_AUTOMIX_MIN_REMAINING_MS || limit <= 0.0) {
    return 1.0f;
  }

  const double rate = fmax(-limit, fmin(limit, -error_ms / remaining_ms));
  const double factor = 1.0 + rate;
  return isfinite(factor) ? (float)factor : NAN;
}

void nar_automix_tracker_init(NarAutomixBeatTracker* tracker,
                              double offline_bpm, int32_t sample_rate) {
  if (tracker == NULL) return;
  for (int i = 0; i < NAR_AUTOMIX_TRACKER_WINDOW; ++i) {
    tracker->onset_history[i] = 0.0f;
  }
  tracker->write_pos = 0;
  tracker->total_samples = 0;
  tracker->offline_bpm = isfinite(offline_bpm) && offline_bpm >= NAR_AUTOMIX_MIN_BPM
                             ? offline_bpm
                             : 120.0;
  tracker->live_bpm = tracker->offline_bpm;
  tracker->live_phase_ms = 0.0;
  tracker->confidence = 0.0;
  tracker->sample_rate = sample_rate > 0 ? sample_rate : 44100;
}

void nar_automix_tracker_reset(NarAutomixBeatTracker* tracker) {
  if (tracker == NULL) return;
  const double bpm = tracker->offline_bpm;
  const int32_t sr = tracker->sample_rate;
  nar_automix_tracker_init(tracker, bpm, sr);
}

void nar_automix_tracker_process_frame(NarAutomixBeatTracker* tracker,
                                         float energy, double current_time_ms) {
  if (tracker == NULL || !isfinite(energy)) return;
  tracker->onset_history[tracker->write_pos] = energy;
  tracker->write_pos = (tracker->write_pos + 1) % NAR_AUTOMIX_TRACKER_WINDOW;
  tracker->total_samples++;

  if (tracker->total_samples >= NAR_AUTOMIX_TRACKER_WINDOW &&
      (tracker->total_samples % 16 == 0)) {
    float sum = 0.0f;
    float peak = 0.0f;
    for (int i = 0; i < NAR_AUTOMIX_TRACKER_WINDOW; ++i) {
      const float val = tracker->onset_history[i];
      sum += val;
      if (val > peak) peak = val;
    }
    const float mean = sum / NAR_AUTOMIX_TRACKER_WINDOW;
    if (peak > mean * 1.5f && peak > 1e-4f) {
      tracker->confidence = fmin(1.0, tracker->confidence + 0.1);
      tracker->live_phase_ms = current_time_ms;
    } else {
      tracker->confidence = fmax(0.0, tracker->confidence - 0.05);
    }
  }
}

float nar_automix_tracker_get_nudge(NarAutomixBeatTracker* tracker,
                                     double target_bpm, double max_nudge) {
  if (tracker == NULL || tracker->confidence < 0.25 ||
      !isfinite(target_bpm) || target_bpm < NAR_AUTOMIX_MIN_BPM ||
      target_bpm > NAR_AUTOMIX_MAX_BPM) {
    return 1.0f;
  }
  const double limit = fabs(max_nudge);
  if (limit <= 0.0) return 1.0f;

  const double desired_factor = target_bpm / tracker->live_bpm;
  const double clamped_factor =
      fmax(1.0 - limit, fmin(1.0 + limit, desired_factor));
  return (float)clamped_factor;
}

float nar_automix_phrase_lock_factor(
    double outgoing_position_ms, double outgoing_downbeat_offset_ms,
    double outgoing_bpm, double incoming_position_ms,
    double incoming_downbeat_offset_ms, double incoming_bpm,
    double remaining_ms, double max_nudge, int32_t beats_per_phrase) {
  if (beats_per_phrase <= 0) beats_per_phrase = 4;
  if (beats_per_phrase > 64) return NAN;
  if (!isfinite(outgoing_position_ms) || !isfinite(outgoing_downbeat_offset_ms) ||
      !isfinite(outgoing_bpm) || !isfinite(incoming_position_ms) ||
      !isfinite(incoming_downbeat_offset_ms) || !isfinite(incoming_bpm) ||
      !isfinite(remaining_ms) || !isfinite(max_nudge) ||
      outgoing_bpm < NAR_AUTOMIX_MIN_BPM || outgoing_bpm > NAR_AUTOMIX_MAX_BPM ||
      incoming_bpm < NAR_AUTOMIX_MIN_BPM || incoming_bpm > NAR_AUTOMIX_MAX_BPM) {
    return NAN;
  }

  const double outgoing_beat_ms = 60000.0 / outgoing_bpm;
  const double incoming_beat_ms = 60000.0 / incoming_bpm;
  const double outgoing_phrase_ms = outgoing_beat_ms * beats_per_phrase;
  const double incoming_phrase_ms = incoming_beat_ms * beats_per_phrase;

  const double outgoing_phase =
      fold_phase(outgoing_position_ms - outgoing_downbeat_offset_ms,
                 outgoing_phrase_ms) /
      outgoing_phrase_ms;
  const double incoming_phase =
      fold_phase(incoming_position_ms - incoming_downbeat_offset_ms,
                 incoming_phrase_ms) /
      incoming_phrase_ms;

  double error_ms = (incoming_phase - outgoing_phase) * incoming_phrase_ms;
  if (error_ms > incoming_phrase_ms * 0.5) error_ms -= incoming_phrase_ms;
  if (error_ms < -incoming_phrase_ms * 0.5) error_ms += incoming_phrase_ms;
  if (!isfinite(error_ms)) return NAN;

  const double limit = fabs(max_nudge);
  if (fabs(error_ms) < NAR_AUTOMIX_DEAD_ZONE_MS ||
      remaining_ms < NAR_AUTOMIX_MIN_REMAINING_MS || limit <= 0.0) {
    return 1.0f;
  }

  const double rate = fmax(-limit, fmin(limit, -error_ms / remaining_ms));
  const double factor = 1.0 + rate;
  return isfinite(factor) ? (float)factor : NAN;
}
