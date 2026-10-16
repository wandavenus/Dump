#include "automix_native.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

enum { PROFILE_DJ = 0, PROFILE_HARMONIC = 1, PROFILE_ENERGY = 2 };

typedef struct {
  int32_t index;
  double tempo;
  int64_t song_id;
} TempoSlot;

typedef struct {
  int32_t index;
  double cost;
  int64_t song_id;
} ScoredCandidate;

static const double kProfileWeights[3][4] = {
    {0.40, 0.20, 0.25, 0.15},
    {0.20, 0.45, 0.20, 0.15},
    {0.15, 0.15, 0.55, 0.15},
};

static double feature(const double* rows, int32_t index, int32_t field) {
  return rows[(size_t)index * NAR_AUTOMIX_FEATURE_COUNT + field];
}

static int32_t key_field(const int32_t* keys, int32_t index, int32_t field) {
  return keys[(size_t)index * NAR_AUTOMIX_KEY_FIELD_COUNT + field];
}

static double clamp01(double value) {
  if (!isfinite(value)) return 0.0;
  return value < 0.0 ? 0.0 : value > 1.0 ? 1.0 : value;
}

static double confidence_blend(double measured, double confidence,
                               double neutral) {
  const double c = clamp01(confidence);
  return neutral + (measured - neutral) * c;
}

static double camelot_cost(int32_t a, int32_t minor_a,
                           int32_t b, int32_t minor_b) {
  if (a <= 0 || b <= 0 || minor_a < 0 || minor_b < 0) return 0.5;
  if (a == b) return minor_a == minor_b ? 0.0 : 0.15;
  int32_t distance = (a - b) % 12;
  if (distance < 0) distance += 12;
  if (distance > 6) distance = 12 - distance;
  if (minor_a != minor_b) {
    if (distance == 1) return 0.45;
    if (distance == 2) return 0.6;
    return 1.0;
  }
  if (distance == 1) return 0.2;
  if (distance == 2) return 0.3;
  if (distance == 3) return 0.6;
  return 1.0;
}

static int append_variant(double bpm, double alternate, double* values,
                          int count) {
  if (!isfinite(bpm) || bpm <= 0.0) return count;
  values[count++] = bpm;
  values[count++] = bpm * 2.0;
  values[count++] = bpm / 2.0;
  if (isfinite(alternate) && alternate > 0.0) values[count++] = alternate;
  return count;
}

static double tempo_cost(double bpm_a, double alt_a, double bpm_b,
                         double alt_b, double tolerance) {
  if (!isfinite(bpm_a) || !isfinite(bpm_b)) return 0.35;
  double variants_a[4];
  double variants_b[4];
  const int count_a = append_variant(bpm_a, alt_a, variants_a, 0);
  const int count_b = append_variant(bpm_b, alt_b, variants_b, 0);
  double best = INFINITY;
  for (int i = 0; i < count_a; ++i) {
    for (int j = 0; j < count_b; ++j) {
      const double x = variants_a[i];
      const double y = variants_b[j];
      if (x <= 0.0 || y <= 0.0) continue;
      const double slower = fmin(x, y);
      const double faster = fmax(x, y);
      const double distance = faster / slower - 1.0;
      if (distance < best) best = distance;
    }
  }
  if (!isfinite(best)) return 0.35;
  if (best <= 0.01) return 0.0;
  if (best <= tolerance) {
    const double scaled = tolerance > 0.0
        ? fmin(1.0, fmax(0.0, best / tolerance))
        : 1.0;
    return scaled * scaled * 0.5;
  }
  const double over = (best - tolerance) / 0.25;
  return fmin(1.0, fmax(0.0, 0.5 + over * 0.5));
}

static double percentile_sorted(const double* values, int32_t count,
                                double fraction) {
  if (count <= 0) return 0.5;
  const double index = (count - 1) * fraction;
  const int32_t low = (int32_t)floor(index);
  const int32_t high = (int32_t)ceil(index);
  if (low == high) return values[low];
  return values[low] + (values[high] - values[low]) * (index - low);
}

static int compare_double(const void* lhs, const void* rhs) {
  const double a = *(const double*)lhs;
  const double b = *(const double*)rhs;
  return (a > b) - (a < b);
}

static int compare_slot(const void* lhs, const void* rhs) {
  const TempoSlot* a = (const TempoSlot*)lhs;
  const TempoSlot* b = (const TempoSlot*)rhs;
  if (a->tempo < b->tempo) return -1;
  if (a->tempo > b->tempo) return 1;
  return (a->song_id > b->song_id) - (a->song_id < b->song_id);
}

static void normalize_energy(const double* rows, int32_t count,
                            double* energies) {
  double* raw = (double*)malloc((size_t)count * sizeof(double));
  double* present = (double*)malloc((size_t)count * sizeof(double));
  if (raw == NULL || present == NULL) {
    for (int32_t i = 0; i < count; ++i) energies[i] = 0.5;
    free(raw);
    free(present);
    return;
  }
  int32_t present_count = 0;
  for (int32_t i = 0; i < count; ++i) {
    const double rms = feature(rows, i, NAR_AUTOMIX_RMS_DB);
    const double centroid = feature(rows, i, NAR_AUTOMIX_CENTROID_HZ);
    const double onset = feature(rows, i, NAR_AUTOMIX_ONSET_RATE);
    const double lufs = feature(rows, i, NAR_AUTOMIX_LOUDNESS_LUFS);
    double value = NAN;
    if (isfinite(rms)) {
      const double rms_n = clamp01((rms + 30.0) / 24.0);
      const double centroid_n = isfinite(centroid)
          ? clamp01((centroid - 400.0) / 3600.0) : 0.5;
      const double onset_n = isfinite(onset)
          ? clamp01((onset - 0.5) / 5.5) : 0.5;
      value = 0.5 * rms_n + 0.25 * centroid_n + 0.25 * onset_n;
    } else if (isfinite(lufs)) {
      const double lufs_n = clamp01((lufs + 24.0) / 18.0);
      const double onset_n = isfinite(onset)
          ? clamp01((onset - 0.5) / 5.5) : 0.25;
      value = 0.75 * lufs_n + 0.25 * onset_n;
    }
    raw[i] = value;
    if (isfinite(value)) present[present_count++] = value;
  }
  if (present_count == 0) {
    for (int32_t i = 0; i < count; ++i) energies[i] = 0.5;
    free(raw);
    free(present);
    return;
  }
  qsort(present, (size_t)present_count, sizeof(double), compare_double);
  const double low = percentile_sorted(present, present_count, 0.10);
  const double high = percentile_sorted(present, present_count, 0.90);
  const double span = high - low < 0.08 ? 0.08 : high - low;
  for (int32_t i = 0; i < count; ++i) {
    energies[i] = isfinite(raw[i]) ? clamp01((raw[i] - low) / span) : 0.5;
  }
  free(raw);
  free(present);
}

static double energy_target(double position, int32_t profile) {
  if (profile == PROFILE_ENERGY) {
    const double p = clamp01(position);
    return p < 0.55 ? 0.30 + 0.70 * (p / 0.55)
                    : 1.00 - 0.55 * ((p - 0.55) / 0.45);
  }
  if (profile == PROFILE_DJ) return 0.25 + 0.50 * clamp01(position);
  return 0.60;
}

static double transition_cost(int32_t a, int32_t b, int32_t step_index,
                              int32_t total_steps, const int64_t* song_ids,
                              const int32_t* artist_groups,
                              const double* rows, const int32_t* keys,
                              const double* energies, int32_t profile,
                              double tolerance, int32_t avoid_artist_repeat,
                              int32_t harmonic_filter) {
  const double bpm_a = feature(rows, a, NAR_AUTOMIX_BPM);
  const double bpm_b = feature(rows, b, NAR_AUTOMIX_BPM);
  const double measured_tempo = tempo_cost(
      bpm_a, feature(rows, a, NAR_AUTOMIX_ALTERNATE_BPM), bpm_b,
      feature(rows, b, NAR_AUTOMIX_ALTERNATE_BPM), tolerance);
  const double confidence_a = feature(rows, a, NAR_AUTOMIX_BPM_CONFIDENCE);
  const double confidence_b = feature(rows, b, NAR_AUTOMIX_BPM_CONFIDENCE);
  const double tempo_confidence = clamp01(
      ((isfinite(confidence_a) ? confidence_a : 0.0) +
       (isfinite(confidence_b) ? confidence_b : 0.0)) * 0.5);
  const double tempo = confidence_blend(measured_tempo, tempo_confidence, 0.35);

  const int32_t num_a = key_field(keys, a, 0);
  const int32_t mode_a = key_field(keys, a, 1);
  const int32_t num_b = key_field(keys, b, 0);
  const int32_t mode_b = key_field(keys, b, 1);
  const double measured_key = camelot_cost(num_a, mode_a, num_b, mode_b);
  const double key_conf_a = feature(rows, a, NAR_AUTOMIX_KEY_CONFIDENCE);
  const double key_conf_b = feature(rows, b, NAR_AUTOMIX_KEY_CONFIDENCE);
  const double key_confidence = clamp01(
      ((isfinite(key_conf_a) ? key_conf_a : 0.0) +
       (isfinite(key_conf_b) ? key_conf_b : 0.0)) * 0.5);
  double key = confidence_blend(measured_key, key_confidence, 0.5);
  if (harmonic_filter && key_confidence >= 0.55 && measured_key >= 0.6) {
    key = fmax(key, 0.9);
  }

  const double position = total_steps <= 1
      ? 1.0 : clamp01((double)step_index / (total_steps - 1));
  const double delta = energies[b] - energies[a];
  double energy = 0.30 * fabs(delta) +
      0.55 * fabs(energies[b] - energy_target(position, profile));
  if (profile == PROFILE_ENERGY) {
    if (position < 0.55 && delta < -0.05) energy += 0.8 * -delta;
    else if (position >= 0.55 && delta > 0.05) energy += 0.8 * delta;
  }
  energy = fmin(1.0, fmax(0.0, energy));
  const int same_artist = artist_groups[a] > 0 &&
                          artist_groups[a] == artist_groups[b];
  const double variety = same_artist
      ? (avoid_artist_repeat ? 0.55 : 0.20) : 0.0;

  // Vocal conflict penalty
  const double vocal_a = feature(rows, a, NAR_AUTOMIX_VOCAL_LIKELIHOOD);
  const double vocal_b = feature(rows, b, NAR_AUTOMIX_VOCAL_LIKELIHOOD);
  double vocal_penalty = 0.0;
  if (isfinite(vocal_a) && isfinite(vocal_b) && vocal_a > 0.5 && vocal_b > 0.5) {
    vocal_penalty = (vocal_a - 0.5) * (vocal_b - 0.5) * 0.4;
  }

  const double* weights = kProfileWeights[profile];
  const double denominator =
      weights[0] + weights[1] + weights[2] + weights[3];
  const double total = weights[0] * tempo + weights[1] * key +
                       weights[2] * energy + weights[3] * variety + vocal_penalty;
  (void)song_ids;
  return fmin(1.0, fmax(0.0, total / denominator));
}

static int32_t lower_bound_tempo(double target, const TempoSlot* slots,
                                 int32_t count) {
  int32_t low = 0;
  int32_t high = count;
  while (low < high) {
    const int32_t middle = (low + high) >> 1;
    if (slots[middle].tempo < target) low = middle + 1;
    else high = middle;
  }
  if (low < 0) return 0;
  return low >= count ? count - 1 : low;
}

static void add_candidate_slot(int32_t slot, const TempoSlot* slots,
                               int32_t count, const uint8_t* played,
                               int32_t exclude_index, uint8_t* candidates) {
  if (slot < 0 || slot >= count) return;
  const int32_t index = slots[slot].index;
  if (!played[index] && index != exclude_index) candidates[index] = 1;
}

static void candidate_pool(int32_t current, const TempoSlot* slots,
                           int32_t count, const uint8_t* played,
                           int32_t exclude_index, const int64_t* song_ids,
                           const double* rows, double median_bpm,
                           uint8_t* candidates) {
  memset(candidates, 0, (size_t)count);
  int32_t slot = 0;
  while (slot < count && slots[slot].index != current) ++slot;
  for (int32_t reach = 1; reach <= 12; ++reach) {
    add_candidate_slot(slot + reach, slots, count, played, exclude_index,
                       candidates);
    add_candidate_slot(slot - reach, slots, count, played, exclude_index,
                       candidates);
  }

  const double bpm = feature(rows, current, NAR_AUTOMIX_BPM);
  if (isfinite(bpm) && bpm > 0.0) {
    double anchors[6] = {bpm, bpm / 2.0, bpm * 2.0,
                         NAN, NAN, NAN};
    int32_t anchor_count = 3;
    const double alternate = feature(rows, current, NAR_AUTOMIX_ALTERNATE_BPM);
    if (isfinite(alternate) && alternate > 0.0) {
      anchors[anchor_count++] = alternate;
      anchors[anchor_count++] = alternate / 2.0;
      anchors[anchor_count++] = alternate * 2.0;
    }
    for (int32_t a = 0; a < anchor_count; ++a) {
      const double target = anchors[a];
      if (!isfinite(target) || target < 60.0 || target > 200.0) continue;
      const int32_t insertion = lower_bound_tempo(target, slots, count);
      for (int32_t reach = 0; reach <= 4; ++reach) {
        add_candidate_slot(insertion + reach, slots, count, played,
                           exclude_index, candidates);
        add_candidate_slot(insertion - 1 - reach, slots, count, played,
                           exclude_index, candidates);
      }
    }
  }
  (void)song_ids;
  (void)median_bpm;
}

static void sort_scored(ScoredCandidate* scored, int32_t count) {
  for (int32_t i = 1; i < count; ++i) {
    const ScoredCandidate value = scored[i];
    int32_t j = i;
    while (j > 0 &&
           (value.cost < scored[j - 1].cost ||
            (value.cost == scored[j - 1].cost &&
             value.song_id < scored[j - 1].song_id))) {
      scored[j] = scored[j - 1];
      --j;
    }
    scored[j] = value;
  }
}

static int32_t pick_next(int32_t current, int32_t step_index,
                         int32_t total_steps, const uint8_t* played,
                         const TempoSlot* slots, const int64_t* song_ids,
                         const int32_t* artist_groups, const double* rows,
                         const int32_t* keys, const double* energies,
                         int32_t profile, double tolerance,
                         int32_t avoid_artist_repeat, int32_t harmonic_filter,
                         double median_bpm, uint8_t* candidates,
                         ScoredCandidate* scored, uint8_t* next_candidates) {
  candidate_pool(current, slots, total_steps, played, -1, song_ids, rows,
                 median_bpm, candidates);
  int32_t scored_count = 0;
  for (int32_t i = 0; i < total_steps; ++i) {
    if (!candidates[i]) continue;
    scored[scored_count++] = (ScoredCandidate){
        i,
        transition_cost(current, i, step_index, total_steps, song_ids,
                        artist_groups, rows, keys, energies, profile, tolerance,
                        avoid_artist_repeat, harmonic_filter),
        song_ids[i]};
  }

  if (scored_count == 0) {
    for (int32_t s = 0; s < total_steps; ++s) {
      const int32_t candidate = slots[s].index;
      if (played[candidate]) continue;
      if (scored_count == 0 ||
          transition_cost(current, candidate, step_index, total_steps,
                          song_ids, artist_groups, rows, keys, energies,
                          profile, tolerance, avoid_artist_repeat,
                          harmonic_filter) < scored[0].cost) {
        scored[0] = (ScoredCandidate){
            candidate,
            transition_cost(current, candidate, step_index, total_steps,
                            song_ids, artist_groups, rows, keys, energies,
                            profile, tolerance, avoid_artist_repeat,
                            harmonic_filter),
            song_ids[candidate]};
      }
      scored_count = 1;
    }
    return scored_count == 0 ? -1 : scored[0].index;
  }

  sort_scored(scored, scored_count);
  if (total_steps <= 24 || scored_count == 1) return scored[0].index;

  int32_t best = scored[0].index;
  double best_score = INFINITY;
  const int32_t limit = scored_count < 3 ? scored_count : 3;
  for (int32_t k = 0; k < limit; ++k) {
    const int32_t candidate = scored[k].index;
    double score = scored[k].cost;
    double min_next = INFINITY;
    candidate_pool(candidate, slots, total_steps, played, candidate,
                   song_ids, rows, median_bpm, next_candidates);
    for (int32_t next = 0; next < total_steps; ++next) {
      if (!next_candidates[next] || played[next] || next == current) continue;
      const double cost = transition_cost(
          candidate, next, step_index + 1, total_steps, song_ids,
          artist_groups, rows, keys, energies, profile, tolerance,
          avoid_artist_repeat, harmonic_filter);
      if (cost < min_next) min_next = cost;
    }
    if (isfinite(min_next)) score += 0.35 * min_next;
    if (score < best_score) {
      best_score = score;
      best = candidate;
    }
  }
  return best;
}

static double path_cost(const int32_t* plan, int32_t count,
                        const int64_t* song_ids, const int32_t* artist_groups,
                        const double* rows, const int32_t* keys,
                        const double* energies, int32_t profile,
                        double tolerance, int32_t avoid_artist_repeat,
                        int32_t harmonic_filter) {
  double sum = 0.0;
  for (int32_t i = 0; i + 1 < count; ++i) {
    sum += transition_cost(
        plan[i], plan[i + 1], i + 1, count, song_ids, artist_groups, rows,
        keys, energies, profile, tolerance, avoid_artist_repeat, harmonic_filter);
  }
  return sum;
}

static double link_cost(const int32_t* plan, int32_t from, int32_t to,
                        int32_t count, const int64_t* song_ids,
                        const int32_t* artist_groups, const double* rows,
                        const int32_t* keys, const double* energies,
                        int32_t profile, double tolerance,
                        int32_t avoid_artist_repeat, int32_t harmonic_filter) {
  return transition_cost(
      plan[from], plan[to], to, count, song_ids, artist_groups, rows, keys,
      energies, profile, tolerance, avoid_artist_repeat, harmonic_filter);
}

static double local_cost(const int32_t* plan, int32_t i, int32_t j,
                         int32_t count, const int64_t* song_ids,
                         const int32_t* artist_groups, const double* rows,
                         const int32_t* keys, const double* energies,
                         int32_t profile, double tolerance,
                         int32_t avoid_artist_repeat, int32_t harmonic_filter) {
  double sum = 0.0;
  if (i > 0) {
    sum += link_cost(plan, i - 1, i, count, song_ids, artist_groups, rows,
                     keys, energies, profile, tolerance, avoid_artist_repeat,
                     harmonic_filter);
  }
  sum += link_cost(plan, i, i + 1, count, song_ids, artist_groups, rows, keys,
                   energies, profile, tolerance, avoid_artist_repeat,
                   harmonic_filter);
  if (j != i + 1) {
    sum += link_cost(plan, j - 1, j, count, song_ids, artist_groups, rows,
                     keys, energies, profile, tolerance, avoid_artist_repeat,
                     harmonic_filter);
  }
  if (j + 1 < count) {
    sum += link_cost(plan, j, j + 1, count, song_ids, artist_groups, rows,
                     keys, energies, profile, tolerance, avoid_artist_repeat,
                     harmonic_filter);
  }
  return sum;
}

static double crossfade_seconds(const int32_t* plan, int32_t count,
                                const double* rows, int32_t crossfade_beats) {
  double* tempos = (double*)malloc((size_t)count * sizeof(double));
  if (tempos == NULL) return 2.0;
  int32_t tempo_count = 0;
  for (int32_t i = 0; i < count; ++i) {
    const double bpm = feature(rows, plan[i], NAR_AUTOMIX_BPM);
    if (isfinite(bpm) && bpm > 0.0) tempos[tempo_count++] = bpm;
  }
  if (tempo_count == 0) {
    free(tempos);
    return fmin(12.0, fmax(1.5, crossfade_beats * 60.0 / 110.0));
  }
  qsort(tempos, (size_t)tempo_count, sizeof(double), compare_double);
  const double median = tempos[tempo_count / 2];
  free(tempos);
  return fmin(12.0, fmax(1.5, crossfade_beats * 60.0 / median));
}

int32_t nar_automix_plan_set(
    const int64_t* song_ids, const int32_t* artist_groups,
    const double* features, const int32_t* keys, int32_t track_count,
    int32_t profile, double bpm_tolerance, int32_t crossfade_beats,
    int32_t avoid_artist_repeat, int32_t harmonic_filter, int32_t start_index,
    int32_t* output_order, double* output_metrics,
    int32_t output_metrics_count) {
  if (track_count < 0 || profile < PROFILE_DJ || profile > PROFILE_ENERGY ||
      !isfinite(bpm_tolerance) || bpm_tolerance <= 0.0 ||
      crossfade_beats <= 0 || output_metrics == NULL ||
      output_metrics_count < 2) {
    return 0;
  }
  if (track_count == 0) {
    output_metrics[0] = 0.0;
    output_metrics[1] = 0.0;
    return 1;
  }
  if (song_ids == NULL || artist_groups == NULL || features == NULL ||
      keys == NULL || output_order == NULL) {
    return 0;
  }
  if (track_count == 1) {
    output_order[0] = 0;
    output_metrics[0] = 2.0;
    output_metrics[1] = 0.0;
    return 1;
  }

  double* energies = (double*)malloc((size_t)track_count * sizeof(double));
  TempoSlot* slots = (TempoSlot*)malloc((size_t)track_count * sizeof(TempoSlot));
  uint8_t* played = (uint8_t*)calloc((size_t)track_count, sizeof(uint8_t));
  uint8_t* candidates = (uint8_t*)calloc((size_t)track_count, sizeof(uint8_t));
  uint8_t* next_candidates =
      (uint8_t*)calloc((size_t)track_count, sizeof(uint8_t));
  ScoredCandidate* scored =
      (ScoredCandidate*)malloc((size_t)track_count * sizeof(ScoredCandidate));
  if (energies == NULL || slots == NULL || played == NULL ||
      candidates == NULL || next_candidates == NULL || scored == NULL) {
    free(energies); free(slots); free(played); free(candidates);
    free(next_candidates); free(scored);
    return 0;
  }

  normalize_energy(features, track_count, energies);
  double* known_tempos = (double*)malloc((size_t)track_count * sizeof(double));
  if (known_tempos == NULL) {
    free(energies); free(slots); free(played); free(candidates);
    free(next_candidates); free(scored);
    return 0;
  }
  int32_t known_count = 0;
  for (int32_t i = 0; i < track_count; ++i) {
    const double bpm = feature(features, i, NAR_AUTOMIX_BPM);
    if (isfinite(bpm)) known_tempos[known_count++] = bpm;
  }
  double median_bpm = 110.0;
  if (known_count > 0) {
    qsort(known_tempos, (size_t)known_count, sizeof(double), compare_double);
    median_bpm = known_tempos[known_count / 2];
  }
  free(known_tempos);
  for (int32_t i = 0; i < track_count; ++i) {
    const double bpm = feature(features, i, NAR_AUTOMIX_BPM);
    slots[i] = (TempoSlot){i, isfinite(bpm) ? bpm : median_bpm, song_ids[i]};
  }
  qsort(slots, (size_t)track_count, sizeof(TempoSlot), compare_slot);

  const int32_t first = start_index < 0 ? 0
      : start_index >= track_count ? track_count - 1 : start_index;
  int32_t plan_count = 0;
  output_order[plan_count++] = first;
  played[first] = 1;
  int32_t current = first;
  while (plan_count < track_count) {
    int32_t next = pick_next(
        current, plan_count, track_count, played, slots, song_ids,
        artist_groups, features, keys, energies, profile, bpm_tolerance,
        avoid_artist_repeat, harmonic_filter, median_bpm, candidates, scored,
        next_candidates);
    if (next < 0 || next >= track_count || played[next]) {
      next = -1;
      for (int32_t i = 0; i < track_count; ++i) {
        if (!played[i]) {
          next = i;
          break;
        }
      }
    }
    if (next < 0) break;
    output_order[plan_count++] = next;
    played[next] = 1;
    current = next;
  }
  if (plan_count != track_count) {
    free(energies); free(slots); free(played); free(candidates);
    free(next_candidates); free(scored);
    return 0;
  }

  int32_t evaluations = 0;
  for (int32_t pass = 0; pass < 6 && evaluations < 4000; ++pass) {
    int improved = 0;
    for (int32_t i = 1; i < track_count - 1 && evaluations < 4000; ++i) {
      const int32_t end = (i + 4 < track_count - 1) ? i + 4 : track_count - 1;
      for (int32_t j = i + 1; j <= end && evaluations < 4000; ++j) {
        ++evaluations;
        const double before = local_cost(
            output_order, i, j, track_count, song_ids, artist_groups, features,
            keys, energies, profile, bpm_tolerance, avoid_artist_repeat,
            harmonic_filter);
        const int32_t original_i = output_order[i];
        const int32_t original_j = output_order[j];
        output_order[i] = original_j;
        output_order[j] = original_i;
        const double after = local_cost(
            output_order, i, j, track_count, song_ids, artist_groups, features,
            keys, energies, profile, bpm_tolerance, avoid_artist_repeat,
            harmonic_filter);
        if (after < before - 1e-9) {
          improved = 1;
        } else {
          output_order[i] = original_i;
          output_order[j] = original_j;
        }
      }
    }
    if (!improved) break;
  }

  output_metrics[0] = crossfade_seconds(
      output_order, track_count, features, crossfade_beats);
  output_metrics[1] = path_cost(
      output_order, track_count, song_ids, artist_groups, features, keys,
      energies, profile, bpm_tolerance, avoid_artist_repeat, harmonic_filter) /
      (track_count - 1);

  free(energies); free(slots); free(played); free(candidates);
  free(next_candidates); free(scored);
  return 1;
}
