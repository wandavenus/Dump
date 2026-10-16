#include "automix_phase_lock.h"

#include <math.h>

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
