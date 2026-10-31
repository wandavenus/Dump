#include "automix_live_tracker.h"
#include "automix_native.h"
#include <float.h>
#ifdef AUTOMIX_DEBUG_METER
#include <stdio.h>
#endif
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define LIVE_HISTORY_FRAMES 600
#define LIVE_MIN_FRAMES 200
#define LIVE_UPDATE_FRAMES 25
#define LIVE_MIN_BPM NAR_AUTOMIX_BPM_MIN
#define LIVE_MAX_BPM NAR_AUTOMIX_BPM_MAX

typedef struct {
  int32_t sample_rate;
  int32_t channel_count;
  int32_t frame_samples;
  int32_t samples_in_frame;
  double full_energy;
  double low_energy;
  double mid_energy;
  double high_energy;
  double lowpass;
  double mid_lowpass;
  double lowpass_alpha;
  double mid_lowpass_alpha;
  double previous_full_db;
  double previous_low_db;
  double previous_mid_db;
  double previous_high_db;
  int has_previous_db;
  int32_t history_write;
  int32_t history_count;
  int32_t frames_since_estimate;
  float onset_history[LIVE_HISTORY_FRAMES];
  float level_history[LIVE_HISTORY_FRAMES];
  // Per-frame band levels. Bar phase needs the *sustained* low-band level (a
  // kick accent), not the clamped onset flux: a loud and a very loud kick both
  // saturate the onset history at 24, which erased exactly the accent that
  // identifies a downbeat on otherwise flat material. The mid/high bands are
  // kept for the timbre-change term.
  float low_history[LIVE_HISTORY_FRAMES];
  float mid_history[LIVE_HISTORY_FRAMES];
  float high_history[LIVE_HISTORY_FRAMES];
  double bpm;
  // Beat phase captured at the most recent autocorrelation estimate.
  // phase_elapsed_ms is re-projected at every PCM callback using this value.
  double phase_at_estimate_ms;
  double phase_elapsed_ms;
  double confidence;
  // Downbeat phase is estimated once per autocorrelation update and
  // re-projected against the bar period (4 beats) on every PCM callback.
  double downbeat_at_estimate_ms;
  double downbeat_elapsed_ms;
  double downbeat_confidence;
  // Beats per bar selected by the live bar-accent hypotheses (2, 3, 4 or 6).
  // Two covers compound 6/8 at a dotted-quarter pulse. Zero when the bar
  // length was not identifiable.
  int32_t meter;
  // Coarse section cue: recent frame-level RMS compared with the window
  // before it. Positive values mean the track is building up.
  double activity_trend;
} NarLiveTracker;

static NarLiveTracker g_tracker[NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT];
static _Atomic int g_reset_pending[NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT] = {1, 1};
static _Atomic double g_published[NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT]
                                  [NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT];
static _Atomic int g_tracker_enabled = 0;
static _Atomic uint32_t g_tracker_generation[NAR_AUTOMIX_LIVE_TRACKER_SLOT_COUNT] = {0, 0};

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

static void publish_state_locked(
    int32_t slot, double bpm, double phase, double confidence,
    double downbeat_phase, double downbeat_confidence, double trend,
    double meter) {
  // Use one sequentially-consistent order for the sequence and all payload
  // fields. This prevents weakly ordered ARM64 CPUs from making a payload
  // store visible before the odd version, or a payload load escape the read
  // window. The payload itself remains atomic, so there is no C data race.
  uint32_t version = atomic_load_explicit(
      &g_published_version[slot], memory_order_seq_cst);
  if ((version & 1u) != 0u) version++;
  atomic_store_explicit(&g_published_version[slot], version + 1u,
                        memory_order_seq_cst);
  atomic_store_explicit(&g_published[slot][0], bpm, memory_order_seq_cst);
  atomic_store_explicit(&g_published[slot][1], phase, memory_order_seq_cst);
  atomic_store_explicit(&g_published[slot][2], confidence, memory_order_seq_cst);
  atomic_store_explicit(&g_published[slot][3], downbeat_phase,
                        memory_order_seq_cst);
  atomic_store_explicit(&g_published[slot][4], downbeat_confidence,
                        memory_order_seq_cst);
  atomic_store_explicit(&g_published[slot][5], trend, memory_order_seq_cst);
  atomic_store_explicit(&g_published[slot][6], meter, memory_order_seq_cst);
  atomic_store_explicit(&g_published_version[slot], version + 2u,
                        memory_order_seq_cst);
}

static void clear_published_state(int32_t slot) {
  // Control-thread path: this may wait briefly for the audio callback's
  // non-blocking publisher. Never bypass the sequence protocol to clear fields:
  // doing so could let readers accept a mixed tuple as a consistent snapshot.
  while (atomic_flag_test_and_set_explicit(&g_publish_lock, memory_order_acquire)) {
  }
  publish_state_locked(slot, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
  atomic_flag_clear_explicit(&g_publish_lock, memory_order_release);
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
    // Invalidate callbacks already processing this slot before clearing its
    // published tuple. A reset on either deck must not invalidate the other.
    atomic_fetch_add_explicit(&g_tracker_generation[slot], 1, memory_order_acq_rel);
    atomic_store_explicit(&g_reset_pending[slot], 1, memory_order_release);
    clear_published_state(slot);
  }
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
                       tracker->confidence, tracker->downbeat_elapsed_ms,
                       tracker->downbeat_confidence, tracker->activity_trend,
                       (double)tracker->meter);
  atomic_flag_clear_explicit(&g_publish_lock, memory_order_release);
}

// Audio-callback variant of the clear: a busy flag means a control-thread
// clear is in progress (and will zero the tuple itself).
static void clear_published_state_audio(int32_t slot) {
  if (atomic_flag_test_and_set_explicit(&g_publish_lock, memory_order_acquire)) {
    return;
  }
  publish_state_locked(slot, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
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

static float level_age(const NarLiveTracker* tracker, int32_t age) {
  int32_t index = tracker->history_write - 1 - age;
  while (index < 0) index += LIVE_HISTORY_FRAMES;
  return tracker->level_history[index];
}

static float band_level_age(const NarLiveTracker* tracker, const float* band,
                            int32_t age) {
  int32_t index = tracker->history_write - 1 - age;
  while (index < 0) index += LIVE_HISTORY_FRAMES;
  return band[index];
}

static double onset_peak(const NarLiveTracker* tracker, double age,
                         int32_t count);

// One pulse-grid hypothesis. Coverage asks how much of the measured onset
// energy lands on the grid; fill asks how many grid slots actually carry an
// onset. Together they resolve the metrical level that autocorrelation cannot:
// a click train is equally periodic at P, P/2 and 2P, but at 2P only half of the
// slots are filled, and at P/2 only a fraction of the onsets land on the grid.
typedef struct {
  double period_frames;
  double phase_frames;
  double coverage;
  double fill;
  double score;
} LiveMetricalGrid;

static LiveMetricalGrid evaluate_live_grid(const NarLiveTracker* tracker,
                                           int32_t count, double period,
                                           double total_onset_energy) {
  LiveMetricalGrid grid = {0.0, 0.0, 0.0, 0.0, 0.0};
  if (!isfinite(period) || period < 3.0 || (double)count < period * 2.0 ||
      total_onset_energy <= 1e-9) {
    return grid;
  }
  double max_onset = 0.0;
  for (int32_t age = 0; age < count; ++age) {
    const double value = (double)history_age(tracker, age);
    if (value > max_onset) max_onset = value;
  }
  if (max_onset <= 1e-6) return grid;
  const double fill_floor = 0.35 * max_onset;
  const int32_t phase_limit = (int32_t)ceil(period);
  double best_sum = -1.0;
  int32_t best_phase = 0;
  int32_t best_filled = 0;
  int32_t best_slots = 0;
  for (int32_t phase = 0; phase < phase_limit; ++phase) {
    double sum = 0.0;
    int32_t filled = 0;
    int32_t slots = 0;
    for (double age = (double)phase; age < (double)count; age += period) {
      const double peak = onset_peak(tracker, age, count);
      sum += peak;
      if (peak >= fill_floor) ++filled;
      ++slots;
    }
    if (sum > best_sum ||
        (fabs(sum - best_sum) <= 1e-9 && slots > 0 &&
         (double)filled / (double)slots >
             (best_slots > 0 ? (double)best_filled / (double)best_slots : 0.0))) {
      best_sum = sum;
      best_phase = phase;
      best_filled = filled;
      best_slots = slots;
    }
  }
  if (best_slots <= 0) return grid;
  grid.period_frames = period;
  grid.phase_frames = (double)best_phase;
  grid.coverage = fmin(1.0, fmax(0.0, best_sum / total_onset_energy));
  grid.fill = fmin(1.0, fmax(0.0,
      (double)best_filled / (double)best_slots));
  // Coverage is what rejects a grid that only catches every second or third
  // onset; fill rejects a grid whose slots are mostly empty. Neither alone is
  // enough for both half-time and double-time errors.
  grid.score = 0.58 * grid.coverage + 0.42 * grid.fill;
  return grid;
}

// Fractional-frame onset lookup used by sub-frame phase refinement. Linear
// interpolation is enough: the envelope is already a smoothed frame RMS.
static double history_sample(const NarLiveTracker* tracker, double age) {
  if (age <= 0.0) return (double)history_age(tracker, 0);
  const int32_t base = (int32_t)age;
  const double fraction = age - (double)base;
  if (fraction <= 0.0) return (double)history_age(tracker, base);
  const double lower = (double)history_age(tracker, base);
  if (base + 1 >= tracker->history_count) return lower;
  const double upper = (double)history_age(tracker, base + 1);
  return lower * (1.0 - fraction) + upper * fraction;
}

static double onset_peak(
    const NarLiveTracker* tracker, double age, int32_t count) {
  const int32_t center = (int32_t)llround(age);
  double peak = history_sample(tracker, age);
  for (int32_t delta = -1; delta <= 1; ++delta) {
    const int32_t frame_age = center + delta;
    if (frame_age >= 0 && frame_age < count) {
      const double value = (double)history_age(tracker, frame_age);
      if (value > peak) peak = value;
    }
  }
  return peak > 0.0 ? peak : 0.0;
}

// Coarse section cue: compare the mean frame RMS of the most recent quarter of
// the history window with the quarter before it. Frame RMS (unlike onset flux)
// is not dominated by a single level jump, so a build-up reads as a sustained
// positive trend and a steady section reads near zero.
static double activity_trend(const NarLiveTracker* tracker) {
  const int32_t window = tracker->history_count / 4;
  if (window < 25) return 0.0;
  double recent = 0.0;
  double older = 0.0;
  for (int32_t age = 0; age < window; ++age) {
    recent += level_age(tracker, age);
    older += level_age(tracker, age + window);
  }
  const double total = recent + older;
  if (total < 1e-9) return 0.0;
  const double trend = (recent - older) / total;
  return fmin(1.0, fmax(-1.0, trend));
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
    tracker->downbeat_at_estimate_ms = 0.0;
    tracker->downbeat_elapsed_ms = 0.0;
    tracker->downbeat_confidence = 0.0;
    tracker->activity_trend = 0.0;
    publish_state(slot, tracker);
    return;
  }
  tracker->activity_trend = activity_trend(tracker);

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
    tracker->downbeat_at_estimate_ms = 0.0;
    tracker->downbeat_elapsed_ms = 0.0;
    tracker->downbeat_confidence = 0.0;
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
    tracker->downbeat_at_estimate_ms = 0.0;
    tracker->downbeat_elapsed_ms = 0.0;
    tracker->downbeat_confidence = 0.0;
    publish_state(slot, tracker);
    return;
  }

  double second_score = -DBL_MAX;
  for (int32_t lag = min_lag; lag <= max_lag && lag < count / 2; ++lag) {
    // Half/double-time and 3:1 correlation peaks are expected and should not
    // alone lower confidence in an otherwise stable pulse train. The 3:1 case
    // matters after the BPM floor moved to 50: at 150 BPM the 3P lag (50 BPM)
    // is now inside the search range and used to collapse uniqueness.
    if (abs(lag - best_lag) <= 2 ||
        abs(2 * lag - best_lag) <= 4 ||
        abs(lag - 2 * best_lag) <= 4 ||
        abs(3 * lag - best_lag) <= 6 ||
        abs(lag - 3 * best_lag) <= 6) continue;
    if (scores[lag] > second_score) second_score = scores[lag];
  }
  if (second_score == -DBL_MAX) second_score = 0.0;

  // Parabolic sub-frame refinement of the autocorrelation peak removes the
  // integer-lag quantization (at 100 fps the raw grid is 0.6 BPM at 120 BPM).
  double refined_lag = (double)best_lag;
  if (best_lag > min_lag && best_lag + 1 <= max_lag &&
      best_lag + 1 < count / 2) {
    const double left = scores[best_lag - 1];
    const double right = scores[best_lag + 1];
    const double denominator = left - 2.0 * best_score + right;
    if (fabs(denominator) > 1e-12) {
      double delta = 0.5 * (left - right) / denominator;
      if (delta > 1.0) delta = 1.0;
      if (delta < -1.0) delta = -1.0;
      refined_lag = (double)best_lag + delta;
    }
  }
  if (!isfinite(refined_lag) || refined_lag <= 0.0) {
    refined_lag = (double)best_lag;
  }
  double candidate_bpm = 60.0 * frames_per_second / refined_lag;
  // Metrical-level arbitration. Autocorrelation is equally strong at P, P/2
  // and 2P (and at 3P for a sparse onset train), so the raw peak cannot say
  // which level is the beat. Test every plausible level around the ACF peak
  // against the onset grid itself: the true beat keeps nearly all onset energy
  // *and* fills its slots, while a slower level only catches every second or
  // third onset and a faster level leaves half its slots empty. Replacing the
  // old one-directional "maybe double" rescue with this symmetric test fixes
  // both half-time and 2:1 / 3:1 errors without a tempo prior.
  double total_onset_energy = 0.0;
  for (int32_t age = 0; age < count; ++age) {
    total_onset_energy += onset_peak(tracker, (double)age, count);
  }
  static const double kLevelRatios[] = {
      1.0, 0.5, 2.0, 2.0 / 3.0, 3.0 / 2.0, 1.0 / 3.0, 3.0};
  LiveMetricalGrid best_grid_hypothesis = {0.0, 0.0, 0.0, 0.0, -1.0};
  LiveMetricalGrid second_grid_hypothesis = {0.0, 0.0, 0.0, 0.0, -1.0};
  for (size_t ratio_index = 0;
       ratio_index < sizeof(kLevelRatios) / sizeof(kLevelRatios[0]);
       ++ratio_index) {
    const double period = refined_lag * kLevelRatios[ratio_index];
    if (!isfinite(period) || period < (double)min_lag ||
        period > (double)max_lag || period >= (double)count * 0.5) {
      continue;
    }
    const double bpm = 60.0 * frames_per_second / period;
    if (bpm < LIVE_MIN_BPM || bpm > LIVE_MAX_BPM) continue;
    const LiveMetricalGrid grid = evaluate_live_grid(
        tracker, count, period, total_onset_energy);
    if (grid.score <= 0.0) continue;
    if (grid.score > best_grid_hypothesis.score) {
      second_grid_hypothesis = best_grid_hypothesis;
      best_grid_hypothesis = grid;
    } else if (grid.score > second_grid_hypothesis.score) {
      second_grid_hypothesis = grid;
    }
  }
  const double metrical_margin =
      best_grid_hypothesis.score > 1e-9 &&
              second_grid_hypothesis.score >= 0.0
          ? fmin(1.0, (best_grid_hypothesis.score -
                       second_grid_hypothesis.score) /
                          best_grid_hypothesis.score)
          : 0.0;
  if (best_grid_hypothesis.score > 0.0) {
    candidate_bpm =
        60.0 * frames_per_second / best_grid_hypothesis.period_frames;
  }
  // Keep a bounded prior for continuous material, but never let it pull the
  // estimate back to a wrong metrical level: a confident grid hypothesis is
  // allowed to replace the old tempo outright when the level changes.
  if (tracker->bpm >= LIVE_MIN_BPM && tracker->bpm <= LIVE_MAX_BPM &&
      tracker->confidence >= 0.20) {
    const double ratio = candidate_bpm / tracker->bpm;
    const double octave_error = fabs(log(ratio));
    const double octave_fold_error =
        fmin(fabs(log(ratio)), fmin(fabs(log(ratio * 2.0)),
                                    fabs(log(ratio * 0.5))));
    if (octave_fold_error > 0.20 && metrical_margin >= 0.12) {
      // A different metrical family won on grid evidence; switch instead of
      // averaging two incompatible pulses.
      tracker->bpm = candidate_bpm;
    } else {
      // Same family: follow the candidate, but do not smooth across an octave
      // boundary (that would land between the two levels).
      const double weight = octave_error > 0.20 ? 1.0 : 0.30;
      tracker->bpm =
          (1.0 - weight) * tracker->bpm + weight * candidate_bpm;
    }
  } else {
    tracker->bpm = candidate_bpm;
  }
  if (!isfinite(tracker->bpm) || tracker->bpm < LIVE_MIN_BPM ||
      tracker->bpm > LIVE_MAX_BPM) {
    tracker->bpm = candidate_bpm;
  }
  // Beat-phase selection: score every candidate grid phase by the total onset
  // energy it aligns across the whole history window. The grid advances by the
  // fractional beat period so non-integer tempos do not drift against the
  // onset history, and the most recent beat of the winning grid is published.
  // A single loud accent or noise spike can no longer hijack the phase the
  // way it could when the latest period's loudest onset won outright.
  //
  // Use the same (smoothed) tempo that will advance the phase between audio
  // callbacks. Scoring at the raw candidate while projecting at tracker->bpm
  // makes the anchor and its projection use different periods during a tempo
  // change, which shifts both the beat and downbeat phase.
  double phase_lag = 60.0 * frames_per_second / tracker->bpm;
  if (!isfinite(phase_lag) || phase_lag <= 0.0) phase_lag = refined_lag;
  double best_grid = 0.0;
  int32_t best_phase = 0;
  const double phase_limit = fmin((double)count, phase_lag);
  for (int32_t phase = 0; (double)phase < phase_limit; ++phase) {
    double sum = 0.0;
    for (double age = (double)phase; age < (double)count; age += phase_lag) {
      sum += history_sample(tracker, age);
    }
    if (sum > best_grid) {
      best_grid = sum;
      best_phase = phase;
    }
  }
  // Sub-frame phase: linear interpolation of the onset history around the
  // integer grid covers the between-frame latency left by the frame clock.
  double best_phase_fractional = (double)best_phase;
  if (phase_lag > 1.0) {
    const double lo = fmax(0.0, (double)best_phase - 0.5);
    const double hi = fmin(phase_lag - 0.001, (double)best_phase + 0.5);
    for (double phase = lo; phase <= hi; phase += 0.05) {
      double sum = 0.0;
      for (double age = phase; age < (double)count; age += phase_lag) {
        sum += history_sample(tracker, age);
      }
      if (sum > best_grid) {
        best_grid = sum;
        best_phase_fractional = phase;
      }
    }
  }
  tracker->phase_elapsed_ms = best_phase_fractional * tracker->frame_samples *
      1000.0 / tracker->sample_rate;
  tracker->phase_at_estimate_ms = tracker->phase_elapsed_ms;
  const double margin = fmax(0.0, best_score - second_score);
  const double periodicity = clamp01((best_score - 0.10) / 0.45);
  const double uniqueness = clamp01((margin + 0.025) / 0.18);
  tracker->confidence = best_grid > 1e-6 ? periodicity * uniqueness : 0.0;
  // A pulse train is equally periodic at 2x and 3x its beat, and the original
  // confidence measured only "is there a pulse", so a 180 BPM train published
  // 60 BPM at confidence 1.000. If a strong correlation peak exists at one
  // half or one third of the winning lag, the winning level is not certain:
  // cap confidence so downstream trust gates cannot accept it blindly.
  double sub_multiple_penalty = 1.0;
  for (int32_t divisor = 2; divisor <= 3; ++divisor) {
    const int32_t sub_lag = (int32_t)llround((double)best_lag / (double)divisor);
    if (sub_lag >= min_lag && sub_lag <= max_lag && sub_lag < count / 2 &&
        scores[sub_lag] >= 0.85 * best_score) {
      // A half/double reading is still usable for a beat-matched fade (every
      // other beat is a real beat), so cap it high enough to pass the 0.35
      // trust gate. A third is not usable: 60 for a 180 BPM track puts every
      // third beat on the grid, so force it below the gate and let the
      // analyzer's grid win.
      const double penalty = divisor == 2 ? 0.55 : 0.30;
      if (sub_multiple_penalty > penalty) sub_multiple_penalty = penalty;
    }
  }
  tracker->confidence *= sub_multiple_penalty;
  // Confidence must express "I know which metrical level this is", not merely
  // "there is a pulse". A clear grid hypothesis keeps full confidence; an
  // ambiguous one is capped so downstream trust gates cannot accept a 3:1
  // reading at 1.000 the way the old correlation-only confidence could.
  tracker->confidence *= 0.55 + 0.45 * metrical_margin;
  if (count < 450) tracker->confidence *= (double)(count - LIVE_MIN_FRAMES) / 150.0;
  tracker->confidence = clamp01(tracker->confidence);

  // Downbeat phase and metre. The old bar scan was hard-wired to four beats and
  // scored positions by clamped onset flux, which saturates at 24: a normal and
  // an accented kick both hit the cap, so flat material published zero bar
  // confidence even when every fourth beat was accented. Score positions from
  // the sustained low-band level (a real kick accent) plus a timbre-change
  // term (a fill or texture entry marks a bar line more reliably than loudness),
  // and evaluate 2, 3, 4 and 6 beat bars. The strongest bar position and metre
  // win only with a clear margin; otherwise no downbeat is published.
  const double frames_to_ms =
      (double)tracker->frame_samples * 1000.0 / tracker->sample_rate;
  tracker->meter = 0;
  tracker->downbeat_confidence = 0.0;
  int32_t pulse_count = 0;
  for (double age = best_phase_fractional; age < (double)count;
       age += phase_lag) {
    ++pulse_count;
  }
  if (pulse_count >= 8 && pulse_count <= 128) {
    double accent[128] = {0.0};
    double novelty[128] = {0.0};
    // Low-band *share* at each pulse. A real accented downbeat is usually also
    // low-heavy, while the frame-grid aliasing that fakes a bar on flat
    // material scales every band by the same factor and leaves the share
    // unchanged. This is the corroboration the metre decision needs.
    double low_share[128] = {0.0};
    double max_accent = 0.0;
    double max_novelty = 0.0;
    int32_t pulse = 0;
    for (double age = best_phase_fractional; age < (double)count;
         age += phase_lag, ++pulse) {
      if (pulse >= 128) break;
      const int32_t frame_age = (int32_t)llround(age);
      const int32_t previous_age = (int32_t)llround(age + phase_lag);
      double low = band_level_age(tracker, tracker->low_history, frame_age);
      // A kick accent can land between frame centres; take the local peak so a
      // one-frame offset does not erase it.
      for (int32_t delta = -1; delta <= 1; ++delta) {
        const int32_t neighbour = frame_age + delta;
        if (neighbour < 0 || neighbour >= count) continue;
        const double value =
            band_level_age(tracker, tracker->low_history, neighbour);
        if (value > low) low = value;
      }
      const double mid = band_level_age(tracker, tracker->mid_history, frame_age);
      const double high = band_level_age(tracker, tracker->high_history, frame_age);
      const double previous_low =
          band_level_age(tracker, tracker->low_history, previous_age);
      const double previous_mid =
          band_level_age(tracker, tracker->mid_history, previous_age);
      const double previous_high =
          band_level_age(tracker, tracker->high_history, previous_age);
      const double total = low + mid + high;
      const double previous_total = previous_low + previous_mid + previous_high;
      double change = 0.0;
      if (total > 1e-9 && previous_total > 1e-9) {
        change = fabs(low / total - previous_low / previous_total) +
                 fabs(mid / total - previous_mid / previous_total) +
                 fabs(high / total - previous_high / previous_total);
      }
      // Absolute low-band level is the kick accent: a one-pole lowpass keeps
      // the sustained 100 Hz body but only a fraction of an 800 Hz click, and
      // taking the local peak removes the grid-to-frame offset. (Band *share*
      // was tried and rejected: a 1 ms click is broadband, so every click looks
      // low-dominant regardless of its pitch.)
      accent[pulse] = low;
      novelty[pulse] = change;
      low_share[pulse] = total > 1e-9 ? low / total : 0.0;
      if (accent[pulse] > max_accent) max_accent = accent[pulse];
      if (change > max_novelty) max_novelty = change;
    }
    const int32_t usable_pulses = pulse < 128 ? pulse : 128;
    // Normalise both evidence streams before combining them so neither an
    // absolute level nor an absolute spectral distance dominates.
    double evidence[128] = {0.0};
    for (int32_t i = 0; i < usable_pulses; ++i) {
      const double accent_term = max_accent > 1e-12 ? accent[i] / max_accent : 0.0;
      const double novelty_term =
          max_novelty > 1e-12 ? novelty[i] / max_novelty : 0.0;
      evidence[i] = 0.80 * accent_term + 0.35 * novelty_term;
    }
    static const int32_t kLiveMeters[] = {4, 3, 6, 2};
    int32_t best_meter = 0;
    int32_t best_position = 0;
    double best_meter_contrast = 0.0;
    int best_meter_corroborated = 0;
    for (size_t meter_index = 0;
         meter_index < sizeof(kLiveMeters) / sizeof(kLiveMeters[0]);
         ++meter_index) {
      const int32_t meter = kLiveMeters[meter_index];
      // Two bars are enough to show a repeated accent; a full four-bar phrase
      // is only needed for phrase *phase*, not for bar length. Ten pulses at
      // 100 BPM are a common six-second history and must still identify the bar.
      if (usable_pulses < meter * 2) continue;
      double position_sum[6] = {0.0};
      int32_t position_count[6] = {0};
      for (int32_t i = 0; i < usable_pulses; ++i) {
        const int32_t position = i % meter;
        position_sum[position] += evidence[i];
        position_count[position]++;
      }
      double best = -1.0;
      double second = -1.0;
      int32_t best_index = 0;
      for (int32_t position = 0; position < meter; ++position) {
        if (position_count[position] <= 0) continue;
        const double value = position_sum[position] / position_count[position];
        if (value > best) {
          second = best;
          best = value;
          best_index = position;
        } else if (value > second) {
          second = value;
        }
      }
      if (second < 0.0) second = 0.0;
      // Low-band share of the winning position versus the rest. A frame-grid
      // alias scales all bands equally, so it cannot produce this evidence.
      double share_win = 0.0;
      double share_other = 0.0;
      int32_t share_win_count = 0;
      int32_t share_other_count = 0;
      for (int32_t i = 0; i < usable_pulses; ++i) {
        if (i % meter == best_index) {
          share_win += low_share[i];
          ++share_win_count;
        } else {
          share_other += low_share[i];
          ++share_other_count;
        }
      }
      const double win_share = share_win_count > 0
          ? share_win / (double)share_win_count : 0.0;
      const double other_share = share_other_count > 0
          ? share_other / (double)share_other_count : 0.0;
      const int corroborated = other_share > 1e-6 &&
          (win_share - other_share) / other_share >= 0.03;
      const double prior = meter == 4 ? 1.0 : 0.88;
      double contrast = (best - second) * prior;
      // The winning bar position must also win in two independent windows of
      // exactly two bars, one at the newest and one at the oldest end of the
      // history. On truly flat material the only bar-to-bar differences are
      // frame-grid aliasing, which drifts over time; requiring both ends to
      // agree removes those false positives without weakening a real repeated
      // accent. A hypothesis that wins only one end is not a metre.
      const int32_t bar = meter * 2;
      int32_t consistent_halves = 0;
      if (usable_pulses >= bar) {
        for (int32_t part = 0; part < 2; ++part) {
          const int32_t begin = part == 0 ? 0 : usable_pulses - bar;
          const int32_t end = part == 0 ? bar : usable_pulses;
          double part_sum[6] = {0.0};
          int32_t part_count[6] = {0};
          for (int32_t i = begin; i < end; ++i) {
            // Each half is indexed relative to its own newest pulse, so the
            // same musical bar phase maps to different local indices. The
            // expected local winner is the global winner rotated by the
            // half's offset; comparing raw indices would reject every metre
            // whenever the halves contain a non-integer number of bars.
            const int32_t position = (i - begin) % meter;
            part_sum[position] += evidence[i];
            part_count[position]++;
          }
          double part_best = -1.0;
          int32_t part_best_index = -1;
          for (int32_t position = 0; position < meter; ++position) {
            if (part_count[position] <= 0) continue;
            const double value = part_sum[position] / part_count[position];
            if (value > part_best) {
              part_best = value;
              part_best_index = position;
            }
          }
          const int32_t expected = ((best_index - begin) % meter + meter) % meter;
          if (part_best_index == expected) ++consistent_halves;
#ifdef AUTOMIX_DEBUG_METER
          fprintf(stderr,
                  "  part=%d begin=%d end=%d winner=%d expected=%d "
                  "partbest=%.4f\n",
                  part, begin, end, part_best_index, expected, part_best);
#endif
        }
        if (consistent_halves < 2) contrast = 0.0;
      } else {
        contrast = 0.0;
      }
      if (contrast > best_meter_contrast + 1e-6) {
        best_meter_contrast = contrast;
        best_meter = meter;
        best_position = best_index;
        best_meter_corroborated = corroborated;
      }
#ifdef AUTOMIX_DEBUG_METER
      fprintf(stderr,
              "meter=%d pulses=%d best=%.4f second=%.4f contrast=%.4f "
              "halves=%d win=%d\n",
              meter, usable_pulses, best, second, contrast,
              consistent_halves, best_index);
#endif
    }
    // A bar line needs a real accent margin; an unaccented loop stays unknown
    // instead of inventing a downbeat every four beats. A very large accent
    // margin is accepted on its own; a moderate one must be corroborated by a
    // low-band share increase at the winning position, which is exactly what
    // separates a real kick downbeat from the frame-grid aliasing of a flat
    // pulse train (measured at 0.19-0.22 contrast on synthetic flat clicks).
    const int strong_accent = best_meter_contrast >= 0.45;
    const int corroborated_accent =
        best_meter_contrast >= 0.18 && best_meter_corroborated;
    if (best_meter > 0 && (strong_accent || corroborated_accent)) {
      tracker->meter = best_meter;
      const double bar_period_ms =
          phase_lag * (double)best_meter * frames_to_ms;
      // best_position is the pulse index modulo the metre, counted back from
      // the newest pulse, so the most recent downbeat is that many pulses back.
      tracker->downbeat_at_estimate_ms =
          (best_phase_fractional + (double)best_position * phase_lag) *
          frames_to_ms;
      double downbeat_elapsed =
          fmod(tracker->downbeat_at_estimate_ms, bar_period_ms);
      if (!isfinite(downbeat_elapsed) || downbeat_elapsed < 0.0) {
        downbeat_elapsed = 0.0;
      }
      tracker->downbeat_elapsed_ms = downbeat_elapsed;
      tracker->downbeat_confidence =
          tracker->confidence * clamp01(best_meter_contrast * 2.5);
    } else {
      tracker->downbeat_at_estimate_ms = 0.0;
      tracker->downbeat_elapsed_ms = 0.0;
    }
  }
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
      &g_tracker_generation[stream_slot], memory_order_acquire);
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
    tracker->mid_lowpass_alpha =
        1.0 - exp(-2.0 * 3.14159265358979323846 * 1500.0 / sample_rate);
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
      // Multichannel layouts put LFE and surround channels after the L/R
      // pair. LFE carries sub-bass effects rather than tempo information, and
      // averaging every channel also attenuates L/R-only musical content by
      // 1/N. The live tracker only needs the stereo musical bed, so ignore the
      // remaining channels; the offline downsampler separately excludes LFE
      // using the container channel mask.
    }
    if (!isfinite(mono)) mono = 0.0;
    tracker->lowpass += tracker->lowpass_alpha * (mono - tracker->lowpass);
    tracker->mid_lowpass +=
        tracker->mid_lowpass_alpha * (mono - tracker->mid_lowpass);
    // Approximate three-band split from two one-pole lowpasses. The bands are
    // not brick-wall, but they separate kick/bass (low), snare/body (mid) and
    // hats/cymbals (high) for the onset weighting.
    const double low_sample = tracker->lowpass;
    const double mid_sample = tracker->mid_lowpass - tracker->lowpass;
    const double high_sample = mono - tracker->mid_lowpass;
    tracker->full_energy += mono * mono;
    tracker->low_energy += low_sample * low_sample;
    tracker->mid_energy += mid_sample * mid_sample;
    tracker->high_energy += high_sample * high_sample;
    tracker->samples_in_frame++;

    if (tracker->samples_in_frame < tracker->frame_samples) continue;
    const double denominator = tracker->samples_in_frame;
    const double full_rms = sqrt(tracker->full_energy / denominator);
    const double low_rms = sqrt(tracker->low_energy / denominator);
    const double mid_rms = sqrt(tracker->mid_energy / denominator);
    const double high_rms = sqrt(tracker->high_energy / denominator);
    const double full_db = 20.0 * log10(full_rms + 1e-7);
    const double low_db = 20.0 * log10(low_rms + 1e-7);
    const double mid_db = 20.0 * log10(mid_rms + 1e-7);
    const double high_db = 20.0 * log10(high_rms + 1e-7);
    double flux = 0.0;
    if (tracker->has_previous_db) {
      // Match the analyzer's band weighting: kick/bass carries the beat, the
      // mid band carries the snare and body, the high band mostly carries the
      // subdivision. A broadband hat no longer competes with a kick for the
      // beat phase or the confidence estimate.
      flux = fmax(0.0, low_db - tracker->previous_low_db) +
             0.55 * fmax(0.0, mid_db - tracker->previous_mid_db) +
             0.15 * fmax(0.0, high_db - tracker->previous_high_db);
    }
    tracker->previous_full_db = full_db;
    tracker->previous_low_db = low_db;
    tracker->previous_mid_db = mid_db;
    tracker->previous_high_db = high_db;
    tracker->has_previous_db = 1;
    const float onset = (float)fmin(24.0, fmax(0.0, flux - 1.5));
    tracker->onset_history[tracker->history_write] = onset;
    tracker->level_history[tracker->history_write] = (float)full_rms;
    tracker->low_history[tracker->history_write] = (float)low_rms;
    tracker->mid_history[tracker->history_write] = (float)mid_rms;
    tracker->high_history[tracker->history_write] = (float)high_rms;
    tracker->history_write = (tracker->history_write + 1) % LIVE_HISTORY_FRAMES;
    if (tracker->history_count < LIVE_HISTORY_FRAMES) tracker->history_count++;
    tracker->samples_in_frame = 0;
    tracker->full_energy = 0.0;
    tracker->low_energy = 0.0;
    tracker->mid_energy = 0.0;
    tracker->high_energy = 0.0;
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
    const int32_t bar_beats = tracker->meter >= 3 ? tracker->meter : 4;
    tracker->phase_elapsed_ms = fmod(
        tracker->phase_at_estimate_ms + elapsed_ms, beat_period_ms);
    tracker->downbeat_elapsed_ms = fmod(
        tracker->downbeat_at_estimate_ms + elapsed_ms,
        beat_period_ms * (double)bar_beats);
    if (!isfinite(tracker->phase_elapsed_ms) || tracker->phase_elapsed_ms < 0.0 ||
        !isfinite(tracker->downbeat_elapsed_ms) ||
        tracker->downbeat_elapsed_ms < 0.0) {
      tracker->confidence = 0.0;
      tracker->downbeat_confidence = 0.0;
      tracker->phase_elapsed_ms = 0.0;
      tracker->downbeat_elapsed_ms = 0.0;
    }
    publish_state(stream_slot, tracker);
  }
  // If AutoMix was disabled or re-enabled during this callback, discard any
  // results from the old tracking epoch. Audio callbacks stay lock-free.
  if (!atomic_load_explicit(&g_tracker_enabled, memory_order_acquire) ||
      atomic_load_explicit(&g_tracker_generation[stream_slot], memory_order_acquire) !=
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
    const double downbeat = atomic_load_explicit(&g_published[stream_slot][3],
                                                 memory_order_relaxed);
    const double downbeat_confidence = atomic_load_explicit(
        &g_published[stream_slot][4], memory_order_relaxed);
    const double trend = atomic_load_explicit(&g_published[stream_slot][5],
                                              memory_order_relaxed);
    const double meter = atomic_load_explicit(&g_published[stream_slot][6],
                                              memory_order_relaxed);
    const uint32_t after = atomic_load_explicit(
        &g_published_version[stream_slot], memory_order_acquire);
    if (before == after) {
      output[0] = bpm;
      output[1] = phase;
      output[2] = confidence;
      output[3] = downbeat;
      output[4] = downbeat_confidence;
      output[5] = trend;
      output[6] = meter;
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
  // Invalidate any callback already processing this deck first. Its tail check
  // will discard stale results and leave the reset pending for the next callback.
  atomic_fetch_add_explicit(&g_tracker_generation[stream_slot], 1, memory_order_acq_rel);
  atomic_store_explicit(&g_reset_pending[stream_slot], 1, memory_order_release);
  clear_published_state(stream_slot);
  return 1;
}
