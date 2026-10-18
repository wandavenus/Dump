#include "automix_live_tracker.h"
#include <float.h>
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define LIVE_HISTORY_FRAMES 600
#define LIVE_MIN_FRAMES 200
#define LIVE_UPDATE_FRAMES 25
#define LIVE_MIN_BPM 60.0
#define LIVE_MAX_BPM 200.0

typedef struct {
  int32_t sample_rate;
  int32_t channel_count;
  int32_t frame_samples;
  int32_t samples_in_frame;
  double full_energy;
  double low_energy;
  double lowpass;
  double lowpass_alpha;
  double previous_full_db;
  double previous_low_db;
  int has_previous_db;
  int32_t history_write;
  int32_t history_count;
  int32_t frames_since_estimate;
  float onset_history[LIVE_HISTORY_FRAMES];
  double bpm;
  // Beat phase captured at the most recent autocorrelation estimate.
  // phase_elapsed_ms is re-projected at every PCM callback using this value.
  double phase_at_estimate_ms;
  double phase_elapsed_ms;
  double confidence;
} NarLiveTracker;

static NarLiveTracker g_tracker[NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT];
static _Atomic int g_reset_pending[NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT] = {1, 1};
static _Atomic double g_published[NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT]
                                  [NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT];
static _Atomic int g_tracker_enabled = 0;
static _Atomic uint32_t g_tracker_generation = 0;

// Published BPM / phase / confidence are read by the controller thread while
// the audio callback writes them. A seqlock keeps a reader from consuming a
// torn tuple (e.g. BPM from one estimate with phase from another): version is
// odd during a write, and a reader retries until it observes the same even
// version before and after its loads. Writers are serialized by a lightweight
// flag so two control threads (or a control thread and the audio callback)
// can never interleave sequence numbers; the audio-side writer uses a
// non-blocking try-acquire and simply skips this callback when busy.
static _Atomic uint32_t g_published_version[NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT];
static atomic_flag g_publish_lock = ATOMIC_FLAG_INIT;

static void publish_state_locked(int32_t slot, double bpm, double phase, double confidence) {
  const uint32_t version = atomic_load_explicit(
      &g_published_version[slot], memory_order_relaxed);
  atomic_store_explicit(&g_published_version[slot], version | 1u, memory_order_relaxed);
  atomic_thread_fence(memory_order_release);
  atomic_store_explicit(&g_published[slot][0], bpm, memory_order_relaxed);
  atomic_store_explicit(&g_published[slot][1], phase, memory_order_relaxed);
  atomic_store_explicit(&g_published[slot][2], confidence, memory_order_relaxed);
  atomic_thread_fence(memory_order_release);
  atomic_store_explicit(&g_published_version[slot], version + 2u, memory_order_release);
}

static void clear_published_state(int32_t slot) {
  // Control-thread path: bounded spin. The audio-side writer only holds the
  // flag for three stores, so the first CAS attempt almost always succeeds.
  for (int attempt = 0; attempt < 1024; ++attempt) {
    if (!atomic_flag_test_and_set_explicit(&g_publish_lock, memory_order_acquire)) {
      publish_state_locked(slot, 0.0, 0.0, 0.0);
      atomic_flag_clear_explicit(&g_publish_lock, memory_order_release);
      return;
    }
  }
  // Pathological contention: still zero the fields atomically. A reader would
  // at worst see a mixed tuple for one callback, which consumers reject via
  // their range validation.
  for (int32_t i = 0; i < NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT; ++i) {
    atomic_store_explicit(&g_published[slot][i], 0.0, memory_order_release);
  }
}

FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_is_enabled(void) {
  return atomic_load_explicit(&g_tracker_enabled, memory_order_acquire) != 0;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_set_enabled(int32_t enabled) {
  if (enabled != 0 && enabled != 1) return 0;
  const int requested = enabled != 0;
  const int current = atomic_load_explicit(&g_tracker_enabled, memory_order_acquire);
  if (current == requested) return 1;

  // Stop callbacks before clearing a disabled tracker. Enabling is published
  // only after both slots have a pending reset, so old phase/history can never
  // leak into a newly enabled AutoMix session.
  if (!requested) {
    // Atomic transition: if another control thread already disabled the
    // tracker, its clear+bump is authoritative and this call must not repeat
    // them (redundant generation bumps would discard live results for nothing).
    int expected = 1;
    if (!atomic_compare_exchange_strong_explicit(
            &g_tracker_enabled, &expected, 0, memory_order_acq_rel,
            memory_order_acquire)) {
      return 1;
    }
  }
  for (int32_t slot = 0; slot < NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT; ++slot) {
    clear_published_state(slot);
    atomic_store_explicit(&g_reset_pending[slot], 1, memory_order_release);
  }
  atomic_fetch_add_explicit(&g_tracker_generation, 1, memory_order_acq_rel);
  if (requested) {
    atomic_store_explicit(&g_tracker_enabled, 1, memory_order_release);
  }
  return 1;
}

static double clamp01(double value) { return fmin(1.0, fmax(0.0, value)); }

static void publish_state(int32_t slot, const NarLiveTracker* tracker) {
  // Audio-callback writer: never block. If a control thread is mid-clear or
  // mid-reset, skip this publish; the next callback (~10 ms) republishes.
  if (atomic_flag_test_and_set_explicit(&g_publish_lock, memory_order_acquire)) {
    return;
  }
  publish_state_locked(slot, tracker->bpm, tracker->phase_elapsed_ms,
                       tracker->confidence);
  atomic_flag_clear_explicit(&g_publish_lock, memory_order_release);
}

// Audio-callback variant of the clear: a busy flag means a control-thread
// clear is in progress (and will zero the tuple itself).
static void clear_published_state_audio(int32_t slot) {
  if (atomic_flag_test_and_set_explicit(&g_publish_lock, memory_order_acquire)) {
    return;
  }
  publish_state_locked(slot, 0.0, 0.0, 0.0);
  atomic_flag_clear_explicit(&g_publish_lock, memory_order_release);
}

static void reset_internal(int32_t slot) {
  memset(&g_tracker[slot], 0, sizeof(g_tracker[slot]));
  publish_state(slot, &g_tracker[slot]);
}

static float history_age(const NarLiveTracker* tracker, int32_t age) {
  int32_t index = tracker->history_write - 1 - age;
  while (index < 0) index += LIVE_HISTORY_FRAMES;
  return tracker->onset_history[index];
}

static double normalized_correlation(
    const NarLiveTracker* tracker, int32_t count, int32_t lag, double mean) {
  double numerator = 0.0;
  double energy_a = 0.0;
  double energy_b = 0.0;
  for (int32_t i = lag; i < count; ++i) {
    const double a = (double)history_age(tracker, count - 1 - i) - mean;
    const double b = (double)history_age(tracker, count - 1 - (i - lag)) - mean;
    numerator += a * b;
    energy_a += a * a;
    energy_b += b * b;
  }
  const double denominator = sqrt(energy_a * energy_b);
  return denominator > 1e-12 ? numerator / denominator : 0.0;
}

static void estimate_live_beat(int32_t slot) {
  NarLiveTracker* tracker = &g_tracker[slot];
  const int32_t count = tracker->history_count;
  if (count < LIVE_MIN_FRAMES || tracker->sample_rate <= 0 ||
      tracker->frame_samples <= 0) {
    tracker->confidence = 0.0;
    publish_state(slot, tracker);
    return;
  }

  double mean = 0.0;
  double squared = 0.0;
  for (int32_t age = 0; age < count; ++age) {
    const double value = history_age(tracker, age);
    mean += value;
    squared += value * value;
  }
  mean /= count;
  if (squared < 1e-7 || squared - count * mean * mean < 1e-7) {
    tracker->bpm = 0.0;
    tracker->phase_at_estimate_ms = 0.0;
    tracker->phase_elapsed_ms = 0.0;
    tracker->confidence = 0.0;
    publish_state(slot, tracker);
    return;
  }

  const double frames_per_second =
      (double)tracker->sample_rate / tracker->frame_samples;
  const int32_t min_lag =
      (int32_t)ceil(frames_per_second * 60.0 / LIVE_MAX_BPM);
  const int32_t max_lag =
      (int32_t)floor(frames_per_second * 60.0 / LIVE_MIN_BPM);
  double scores[LIVE_HISTORY_FRAMES / 2 + 1] = {0.0};
  int32_t best_lag = -1;
  double best_score = -DBL_MAX;
  for (int32_t lag = min_lag; lag <= max_lag && lag < count / 2; ++lag) {
    scores[lag] = normalized_correlation(tracker, count, lag, mean);
    if (scores[lag] > best_score) {
      best_score = scores[lag];
      best_lag = lag;
    }
  }
  if (best_lag < 0 || !isfinite(best_score) || best_score < 0.12) {
    tracker->confidence = 0.0;
    publish_state(slot, tracker);
    return;
  }

  double second_score = -DBL_MAX;
  for (int32_t lag = min_lag; lag <= max_lag && lag < count / 2; ++lag) {
    // Half/double-time correlation peaks are expected and should not alone
    // lower confidence in an otherwise stable pulse train.
    if (abs(lag - best_lag) <= 2 ||
        abs(2 * lag - best_lag) <= 4 ||
        abs(lag - 2 * best_lag) <= 4) continue;
    if (scores[lag] > second_score) second_score = scores[lag];
  }
  if (second_score == -DBL_MAX) second_score = 0.0;

  double candidate_bpm = 60.0 * frames_per_second / best_lag;
  if (tracker->bpm >= LIVE_MIN_BPM && tracker->bpm <= LIVE_MAX_BPM &&
      tracker->confidence >= 0.20) {
    const double octave_candidates[] = {
        candidate_bpm, candidate_bpm * 2.0, candidate_bpm * 0.5};
    double closest = candidate_bpm;
    double closest_error = fabs(log(candidate_bpm / tracker->bpm));
    for (int i = 1; i < 3; ++i) {
      const double candidate = octave_candidates[i];
      if (candidate < LIVE_MIN_BPM || candidate > LIVE_MAX_BPM) continue;
      const double error = fabs(log(candidate / tracker->bpm));
      if (error < closest_error && error <= 0.20) {
        closest = candidate;
        closest_error = error;
      }
    }
    candidate_bpm = closest;
    tracker->bpm = 0.70 * tracker->bpm + 0.30 * candidate_bpm;
  } else {
    tracker->bpm = candidate_bpm;
  }

  double peak = 0.0;
  int32_t peak_age = 0;
  const int32_t phase_search = best_lag < count ? best_lag : count;
  for (int32_t age = 0; age < phase_search; ++age) {
    const double value = history_age(tracker, age);
    if (value > peak) {
      peak = value;
      peak_age = age;
    }
  }
  tracker->phase_elapsed_ms =
      (double)peak_age * tracker->frame_samples * 1000.0 / tracker->sample_rate;
  tracker->phase_at_estimate_ms = tracker->phase_elapsed_ms;
  const double margin = fmax(0.0, best_score - second_score);
  const double periodicity = clamp01((best_score - 0.10) / 0.45);
  const double uniqueness = clamp01((margin + 0.025) / 0.18);
  tracker->confidence = peak > 1e-6 ? periodicity * uniqueness : 0.0;
  if (count < 450) tracker->confidence *= (double)(count - LIVE_MIN_FRAMES) / 150.0;
  tracker->confidence = clamp01(tracker->confidence);
  publish_state(slot, tracker);
}

FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_process(
    const float* interleaved_pcm, int32_t frame_count, int32_t channel_count,
    int32_t sample_rate, int32_t stream_slot) {
  if (interleaved_pcm == NULL || frame_count <= 0 || channel_count <= 0 ||
      channel_count > 8 || sample_rate < 8000 || sample_rate > 192000 ||
      stream_slot < 0 || stream_slot >= NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT) {
    return 0;
  }
  // Do not extract onset envelopes or run autocorrelation when AutoMix has
  // no active transition plan. Keep the API successful for safe pass-through.
  if (!atomic_load_explicit(&g_tracker_enabled, memory_order_acquire)) return 1;
  const uint32_t generation_at_start = atomic_load_explicit(
      &g_tracker_generation, memory_order_acquire);
  if (atomic_exchange_explicit(&g_reset_pending[stream_slot], 0,
                               memory_order_acq_rel) != 0) {
    reset_internal(stream_slot);
  }
  NarLiveTracker* tracker = &g_tracker[stream_slot];
  if (tracker->sample_rate != sample_rate ||
      tracker->channel_count != channel_count) {
    reset_internal(stream_slot);
    tracker->sample_rate = sample_rate;
    tracker->channel_count = channel_count;
    tracker->frame_samples = (int32_t)lround((double)sample_rate / 100.0);
    if (tracker->frame_samples < 1) tracker->frame_samples = 1;
    tracker->lowpass_alpha =
        1.0 - exp(-2.0 * 3.14159265358979323846 * 150.0 / sample_rate);
  }

  for (int32_t frame = 0; frame < frame_count; ++frame) {
    const int32_t base = frame * channel_count;
    double mono;
    if (channel_count == 1) {
      mono = interleaved_pcm[base];
    } else {
      const double left = interleaved_pcm[base];
      const double right = interleaved_pcm[base + 1];
      const double mid = (left + right) * 0.5;
      mono = fabs(mid) < 0.25 * fmax(fabs(left), fabs(right))
          ? (fabs(left) >= fabs(right) ? left : right)
          : mid;
      if (channel_count > 2) {
        double sum = mono;
        for (int32_t channel = 2; channel < channel_count; ++channel) {
          sum += interleaved_pcm[base + channel];
        }
        mono = sum / channel_count;
      }
    }
    if (!isfinite(mono)) mono = 0.0;
    tracker->lowpass += tracker->lowpass_alpha * (mono - tracker->lowpass);
    tracker->full_energy += mono * mono;
    tracker->low_energy += tracker->lowpass * tracker->lowpass;
    tracker->samples_in_frame++;

    if (tracker->samples_in_frame < tracker->frame_samples) continue;
    const double denominator = tracker->samples_in_frame;
    const double full_rms = sqrt(tracker->full_energy / denominator);
    const double low_rms = sqrt(tracker->low_energy / denominator);
    const double full_db = 20.0 * log10(full_rms + 1e-7);
    const double low_db = 20.0 * log10(low_rms + 1e-7);
    double flux = 0.0;
    if (tracker->has_previous_db) {
      flux = fmax(0.0, full_db - tracker->previous_full_db) +
             0.65 * fmax(0.0, low_db - tracker->previous_low_db);
    }
    tracker->previous_full_db = full_db;
    tracker->previous_low_db = low_db;
    tracker->has_previous_db = 1;
    const float onset = (float)fmin(24.0, fmax(0.0, flux - 1.5));
    tracker->onset_history[tracker->history_write] = onset;
    tracker->history_write = (tracker->history_write + 1) % LIVE_HISTORY_FRAMES;
    if (tracker->history_count < LIVE_HISTORY_FRAMES) tracker->history_count++;
    tracker->samples_in_frame = 0;
    tracker->full_energy = 0.0;
    tracker->low_energy = 0.0;
    tracker->frames_since_estimate++;
    if (tracker->frames_since_estimate >= LIVE_UPDATE_FRAMES) {
      tracker->frames_since_estimate = 0;
      estimate_live_beat(stream_slot);
    }
  }

  // The BPM/autocorrelation work is refreshed every 250 ms to bound CPU work,
  // but phase must advance on every audio callback; otherwise the crossfade
  // controller would repeatedly consume a stale beat phase between updates.
  if (tracker->bpm >= LIVE_MIN_BPM && tracker->bpm <= LIVE_MAX_BPM &&
      tracker->confidence > 0.0 && tracker->sample_rate > 0) {
    const int64_t unestimated_samples =
        (int64_t)tracker->frames_since_estimate * tracker->frame_samples +
        tracker->samples_in_frame;
    const double elapsed_ms = (double)unestimated_samples * 1000.0 /
        tracker->sample_rate;
    const double beat_period_ms = 60000.0 / tracker->bpm;
    tracker->phase_elapsed_ms = fmod(
        tracker->phase_at_estimate_ms + elapsed_ms, beat_period_ms);
    if (!isfinite(tracker->phase_elapsed_ms) || tracker->phase_elapsed_ms < 0.0) {
      tracker->confidence = 0.0;
      tracker->phase_elapsed_ms = 0.0;
    }
    publish_state(stream_slot, tracker);
  }
  // If AutoMix was disabled or re-enabled during this callback, discard any
  // results from the old tracking epoch. Audio callbacks stay lock-free.
  if (!atomic_load_explicit(&g_tracker_enabled, memory_order_acquire) ||
      atomic_load_explicit(&g_tracker_generation, memory_order_acquire) !=
          generation_at_start) {
    clear_published_state_audio(stream_slot);
    atomic_store_explicit(&g_reset_pending[stream_slot], 1, memory_order_release);
  }
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_get(
    int32_t stream_slot, double* output, int32_t output_count) {
  if (stream_slot < 0 || stream_slot >= NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT ||
      output == NULL || output_count < NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) {
    return 0;
  }
  // Seqlock read: BPM, phase and confidence must come from the same estimate.
  // Retry while a writer holds the sequence odd or moved between the loads.
  for (int attempt = 0; attempt < 16; ++attempt) {
    const uint32_t before = atomic_load_explicit(
        &g_published_version[stream_slot], memory_order_acquire);
    if ((before & 1u) != 0u) continue;
    const double bpm = atomic_load_explicit(&g_published[stream_slot][0],
                                            memory_order_relaxed);
    const double phase = atomic_load_explicit(&g_published[stream_slot][1],
                                              memory_order_relaxed);
    const double confidence = atomic_load_explicit(&g_published[stream_slot][2],
                                                   memory_order_relaxed);
    const uint32_t after = atomic_load_explicit(
        &g_published_version[stream_slot], memory_order_acquire);
    if (before == after) {
      output[0] = bpm;
      output[1] = phase;
      output[2] = confidence;
      return 1;
    }
  }
  // Extremely contended: report zeros rather than a possibly torn tuple.
  for (int32_t i = 0; i < NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT; ++i) {
    output[i] = 0.0;
  }
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_live_tracker_reset(int32_t stream_slot) {
  if (stream_slot < 0 || stream_slot >= NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT) return 0;
  clear_published_state(stream_slot);
  atomic_store_explicit(&g_reset_pending[stream_slot], 1, memory_order_release);
  // Bump the epoch so an in-flight audio callback cannot republish pre-reset
  // phase after this call; its tail check discards the stale results.
  atomic_fetch_add_explicit(&g_tracker_generation, 1, memory_order_acq_rel);
  return 1;
}
