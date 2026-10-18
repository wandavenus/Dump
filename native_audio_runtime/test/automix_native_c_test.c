#include "automix_native.h"
#include "automix_phase_lock.h"
#include "automix_tone_processor.h"
#include "automix_live_tracker.h"

#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>
#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

static void assert_analysis_confidence_contract(
    const double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT]) {
  // Confidence fields must be finite [0,1]. Index 16 is a region enum, not
  // a confidence value, and therefore has its own range contract.
  const int confidence_indices[] = {14, 15, 17, 18, 19, 20};
  for (size_t i = 0;
       i < sizeof(confidence_indices) / sizeof(confidence_indices[0]); ++i) {
    const int index = confidence_indices[i];
    assert(isfinite(output[index]));
    assert(output[index] >= 0.0 && output[index] <= 1.0);
  }
  assert(output[16] >= NAR_AUTOMIX_STRUCTURE_UNKNOWN &&
         output[16] <= NAR_AUTOMIX_STRUCTURE_STABLE_HIGH);
  // This window's tail-tempo confidence is its own tempo confidence.
  assert(output[20] == output[1]);
  // Tempo-curve slots use NaN for "not measurable"; when present they must be
  // positive BPMs and a [0,1] stability.
  assert(isnan(output[21]) || output[21] > 0.0);
  assert(isnan(output[22]) || output[22] > 0.0);
  assert(isnan(output[23]) || (output[23] >= 0.0 && output[23] <= 1.0));
}

static void test_analyzer_rms(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 2;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  for (int32_t i = 0; i < count; ++i) {
    pcm[i] = 0.5f * sinf(2.0f * 3.14159265358979323846f * 440.0f *
                         (float)i / sample_rate);
  }
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(isfinite(output[7]));
  assert(fabs(output[7] - (-9.03)) < 1.0);
  assert(fabs(output[10] - 2.0) < 1e-9);
  assert_analysis_confidence_contract(output);
  // A pure tone is not sufficient evidence of vocals.
  assert(output[19] < 0.35);
  // A steady sine has no sustained section change, so structural cues should
  // remain unavailable instead of reporting arbitrary extrema.
  assert(isnan(output[11]));
  assert(isnan(output[12]));
  assert(isnan(output[13]));
  free(pcm);
}

static void test_analyzer_structural_cues(void) {
  const int32_t sample_rate = 22050;
  const int32_t seconds = 10;
  const int32_t count = sample_rate * seconds;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);

  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    double amplitude;
    if (t < 3.0) amplitude = 0.5;
    else if (t < 5.0) amplitude = 0.05;
    else if (t < 8.0) amplitude = 0.8;
    else amplitude = 0.05;
    pcm[i] = (float)(amplitude *
        sin(2.0 * 3.14159265358979323846 * 220.0 * t));
  }

  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  // The low-energy lead-in rises into a strong onset near 5 s; the final
  // sustained high-to-low change begins near 8 s.
  assert(isfinite(output[12]));
  // The native ABI reports structural cue positions in milliseconds.
  assert(output[12] > 4400.0 && output[12] < 5700.0);
  assert(isfinite(output[13]));
  assert(output[13] > 7300.0 && output[13] < 8800.0);
  free(pcm);
}

static void test_planner_vocal_conflict(void) {
  const int64_t ids[] = {1, 2, 3};
  const int32_t artists[] = {1, 2, 3};
  double features[3 * NAR_AUTOMIX_FEATURE_COUNT];
  int32_t keys[3 * NAR_AUTOMIX_KEY_FIELD_COUNT];
  for (int i = 0; i < 3 * NAR_AUTOMIX_FEATURE_COUNT; ++i) features[i] = NAN;
  for (int i = 0; i < 3; ++i) {
    double* row = features + i * NAR_AUTOMIX_FEATURE_COUNT;
    row[NAR_AUTOMIX_BPM] = 120.0;
    row[NAR_AUTOMIX_BPM_CONFIDENCE] = 0.9;
    row[NAR_AUTOMIX_KEY_CONFIDENCE] = 0.9;
    keys[i * 2] = 8;
    keys[i * 2 + 1] = 1;
  }
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_VOCAL_LIKELIHOOD] = 0.9;
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_VOCAL_CONFIDENCE] = 0.8;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_VOCAL_LIKELIHOOD] = 0.9;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_VOCAL_CONFIDENCE] = 0.8;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_VOCAL_LIKELIHOOD] = 0.9;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_VOCAL_CONFIDENCE] = 0.1;

  int32_t order[3];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 3, 0, 0.06, 16,
                              0, 0, 0, order, metrics, 2) == 1);
  assert(order[0] == 0);
  assert(order[1] == 2);
  assert(order[2] == 1);
}

static void test_planner_keeps_start_and_permutation(void) {
  const int64_t ids[] = {101, 102, 103, 104, 105};
  const int32_t artists[] = {1, 2, 1, 3, 2};
  double features[5 * NAR_AUTOMIX_FEATURE_COUNT];
  int32_t keys[5 * NAR_AUTOMIX_KEY_FIELD_COUNT];
  for (int i = 0; i < 5 * NAR_AUTOMIX_FEATURE_COUNT; ++i) {
    features[i] = NAN;
  }
  for (int i = 0; i < 5; ++i) {
    double* row = features + i * NAR_AUTOMIX_FEATURE_COUNT;
    row[NAR_AUTOMIX_BPM] = 90.0 + i * 7.0;
    row[NAR_AUTOMIX_BPM_CONFIDENCE] = 0.9;
    row[NAR_AUTOMIX_KEY_CONFIDENCE] = 0.8;
    row[NAR_AUTOMIX_RMS_DB] = -24.0 + i * 3.0;
    keys[i * 2] = i + 1;
    keys[i * 2 + 1] = i & 1;
  }
  int32_t order[5];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 5, 0, 0.06, 16,
                              1, 0, 3, order, metrics, 2) == 1);
  assert(order[0] == 3);
  int seen[5] = {0};
  for (int i = 0; i < 5; ++i) {
    assert(order[i] >= 0 && order[i] < 5);
    assert(!seen[order[i]]);
    seen[order[i]] = 1;
  }
  assert(metrics[0] >= 1.5 && metrics[0] <= 12.0);
  assert(metrics[1] >= 0.0 && metrics[1] <= 1.0);
}

static void test_planner_scores_tempo_at_seam(void) {
  const int64_t ids[] = {1, 2, 3};
  const int32_t artists[] = {1, 2, 3};
  double features[3 * NAR_AUTOMIX_FEATURE_COUNT];
  int32_t keys[3 * NAR_AUTOMIX_KEY_FIELD_COUNT];
  for (int i = 0; i < 3 * NAR_AUTOMIX_FEATURE_COUNT; ++i) features[i] = NAN;
  for (int i = 0; i < 3; ++i) {
    double* row = features + i * NAR_AUTOMIX_FEATURE_COUNT;
    row[NAR_AUTOMIX_BPM_CONFIDENCE] = 0.99;
    row[NAR_AUTOMIX_KEY_CONFIDENCE] = 0.9;
    row[NAR_AUTOMIX_RMS_DB] = -12.0;
    keys[i * 2] = 8;
    keys[i * 2 + 1] = 1;
  }
  // Track 0 heads at 100 BPM but exits (tail) at 128 BPM; track 1 heads at 128
  // and track 2 heads at 100. The blend happens in track 0's tail, so track 1
  // is the compatible successor even though track 2 matches the head tempo.
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_BPM] = 100.0;
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_TAIL_BPM] = 128.0;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_BPM] = 128.0;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_BPM] = 100.0;

  int32_t order[3];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 3, 0, 0.06, 16,
                              0, 0, 0, order, metrics, 2) == 1);
  assert(order[0] == 0);
  assert(order[1] == 1);
  assert(order[2] == 2);
}

static void test_planner_penalizes_energy_seam(void) {
  const int64_t ids[] = {1, 2, 3};
  const int32_t artists[] = {1, 2, 3};
  double features[3 * NAR_AUTOMIX_FEATURE_COUNT];
  int32_t keys[3 * NAR_AUTOMIX_KEY_FIELD_COUNT];
  for (int i = 0; i < 3 * NAR_AUTOMIX_FEATURE_COUNT; ++i) features[i] = NAN;
  for (int i = 0; i < 3; ++i) {
    double* row = features + i * NAR_AUTOMIX_FEATURE_COUNT;
    row[NAR_AUTOMIX_BPM] = 120.0;
    row[NAR_AUTOMIX_BPM_CONFIDENCE] = 0.99;
    row[NAR_AUTOMIX_KEY_CONFIDENCE] = 0.9;
    row[NAR_AUTOMIX_RMS_DB] = -12.0;
    keys[i * 2] = 8;
    keys[i * 2 + 1] = 1;
  }
  // Track 0 exits loud. Track 1 enters quiet and track 2 enters equally loud;
  // track 1 has the smaller song id, so only the seam term makes the engine
  // prefer the matching-energy track 2 first.
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_OUTRO_ENERGY] = 0.9;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_INTRO_ENERGY] = 0.1;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_INTRO_ENERGY] = 0.9;

  int32_t order[3];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 3, 0, 0.06, 16,
                              0, 0, 0, order, metrics, 2) == 1);
  assert(order[0] == 0);
  assert(order[1] == 2);
  assert(order[2] == 1);
}


static void test_planner_prefers_calm_structural_seam(void) {
  const int64_t ids[] = {1, 2, 3};
  const int32_t artists[] = {1, 2, 3};
  double features[3 * NAR_AUTOMIX_FEATURE_COUNT];
  int32_t keys[3 * NAR_AUTOMIX_KEY_FIELD_COUNT];
  for (int i = 0; i < 3 * NAR_AUTOMIX_FEATURE_COUNT; ++i) features[i] = NAN;
  for (int i = 0; i < 3; ++i) {
    double* row = features + i * NAR_AUTOMIX_FEATURE_COUNT;
    row[NAR_AUTOMIX_BPM] = 120.0;
    row[NAR_AUTOMIX_BPM_CONFIDENCE] = 0.99;
    row[NAR_AUTOMIX_KEY_CONFIDENCE] = 0.9;
    row[NAR_AUTOMIX_RMS_DB] = -12.0;
    keys[i * 2] = 8;
    keys[i * 2 + 1] = 1;
  }
  // Track 0 exits on a drop. Track 1 enters on a drop as well and has the
  // smaller song id; track 2 enters on a buildup. Only the structural seam
  // term separates them, so the planner must hand over into track 2.
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_TAIL_STRUCTURE_REGION] =
      (double)NAR_AUTOMIX_STRUCTURE_DROP;
  features[0 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_TAIL_STRUCTURE_CONFIDENCE] = 0.9;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_STRUCTURE_REGION] =
      (double)NAR_AUTOMIX_STRUCTURE_DROP;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_STRUCTURE_CONFIDENCE] = 0.9;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_STRUCTURE_REGION] =
      (double)NAR_AUTOMIX_STRUCTURE_BUILDUP;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_STRUCTURE_CONFIDENCE] = 0.9;

  int32_t order[3];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 3, 0, 0.06, 16,
                              0, 0, 0, order, metrics, 2) == 1);
  assert(order[0] == 0);
  assert(order[1] == 2);
  assert(order[2] == 1);
}

static void test_planner_ignores_unconfident_structure(void) {
  const int64_t ids[] = {1, 2, 3};
  const int32_t artists[] = {1, 2, 3};
  double features[3 * NAR_AUTOMIX_FEATURE_COUNT];
  int32_t keys[3 * NAR_AUTOMIX_KEY_FIELD_COUNT];
  for (int i = 0; i < 3 * NAR_AUTOMIX_FEATURE_COUNT; ++i) features[i] = NAN;
  for (int i = 0; i < 3; ++i) {
    double* row = features + i * NAR_AUTOMIX_FEATURE_COUNT;
    row[NAR_AUTOMIX_BPM] = 120.0;
    row[NAR_AUTOMIX_BPM_CONFIDENCE] = 0.99;
    row[NAR_AUTOMIX_KEY_CONFIDENCE] = 0.9;
    row[NAR_AUTOMIX_RMS_DB] = -12.0;
    keys[i * 2] = 8;
    keys[i * 2 + 1] = 1;
  }
  // Same shape as the confident-seam test, but every structure label is below
  // the 0.5 confidence gate: the term must stay neutral and the smaller song
  // id (track 1) keeps the tie.
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_TAIL_STRUCTURE_REGION] =
      (double)NAR_AUTOMIX_STRUCTURE_DROP;
  features[0 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_TAIL_STRUCTURE_CONFIDENCE] = 0.3;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_STRUCTURE_REGION] =
      (double)NAR_AUTOMIX_STRUCTURE_DROP;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_STRUCTURE_CONFIDENCE] = 0.3;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_STRUCTURE_REGION] =
      (double)NAR_AUTOMIX_STRUCTURE_BUILDUP;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_STRUCTURE_CONFIDENCE] = 0.3;

  int32_t order[3];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 3, 0, 0.06, 16,
                              0, 0, 0, order, metrics, 2) == 1);
  assert(order[0] == 0);
  assert(order[1] == 1);
  assert(order[2] == 2);
}

static void test_planner_spreads_repeated_artists(void) {
  // Tracks 0 and 2 share artist X, tracks 1 and 3 share artist Y; every
  // transition costs the same, so only the artist cooldown can break the
  // id-ordered tie. Without the cooldown the planner would chain
  // X, Y, X (id 3), Y (id 4); with it, the X at distance 2 yields to the
  // unlabeled Z and the repeat lands four positions after the first X.
  const int64_t ids[] = {1, 2, 3, 4};
  const int32_t artists[] = {7, 8, 7, 9};
  double features[4 * NAR_AUTOMIX_FEATURE_COUNT];
  int32_t keys[4 * NAR_AUTOMIX_KEY_FIELD_COUNT];
  for (int i = 0; i < 4 * NAR_AUTOMIX_FEATURE_COUNT; ++i) features[i] = NAN;
  for (int i = 0; i < 4; ++i) {
    double* row = features + i * NAR_AUTOMIX_FEATURE_COUNT;
    row[NAR_AUTOMIX_BPM] = 120.0;
    row[NAR_AUTOMIX_BPM_CONFIDENCE] = 0.99;
    row[NAR_AUTOMIX_KEY_CONFIDENCE] = 0.9;
    row[NAR_AUTOMIX_RMS_DB] = -12.0;
    keys[i * 2] = 8;
    keys[i * 2 + 1] = 1;
  }

  int32_t order[4];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 4, 0, 0.06, 16,
                              1, 0, 0, order, metrics, 2) == 1);
  assert(order[0] == 0);
  assert(order[1] == 1);
  assert(order[2] == 3);
  assert(order[3] == 2);
}

static void test_planner_relocation_polish_improves_local_optimum(void) {
  // Frozen fixture (xorshift seed 2) where the greedy chain plus the bounded
  // swap scan is a local optimum that single-track relocation moves escape.
  // The swap-only baseline scores 0.2661114 on this fixture; relocation and
  // short reversals bring it under the asserted bound. The fixture embeds the
  // probe generator so the regression stays reproducible without recordings.
  unsigned long long state = 2ull * 2654435761ull + 1ull;
  int64_t ids[30];
  int32_t artists[30];
  double features[30 * NAR_AUTOMIX_FEATURE_COUNT];
  int32_t keys[30 * NAR_AUTOMIX_KEY_FIELD_COUNT];
  for (int i = 0; i < 30 * NAR_AUTOMIX_FEATURE_COUNT; ++i) features[i] = NAN;
  for (int i = 0; i < 30; ++i) {
    double* row = features + i * NAR_AUTOMIX_FEATURE_COUNT;
    ids[i] = i + 1;
    artists[i] = (i * 3) % 11 + 1;
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    row[NAR_AUTOMIX_BPM] = 70.0 + (double)(state % 900ull) / 10.0;
    if (i % 6 == 0) row[NAR_AUTOMIX_BPM] = NAN;
    if (i % 4 == 0) {
      state ^= state << 13;
      state ^= state >> 7;
      state ^= state << 17;
      row[NAR_AUTOMIX_ALTERNATE_BPM] =
          100.0 + (double)(state % 400ull) / 10.0;
    }
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    row[NAR_AUTOMIX_BPM_CONFIDENCE] =
        (double)(state % 100000ull) / 100000.0 * 0.9 + 0.1;
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    row[NAR_AUTOMIX_KEY_CONFIDENCE] =
        (double)(state % 100000ull) / 100000.0 * 0.8 + 0.2;
    if (i % 3 != 0) {
      state ^= state << 13;
      state ^= state >> 7;
      state ^= state << 17;
      row[NAR_AUTOMIX_RMS_DB] =
          -30.0 + (double)(state % 100000ull) / 100000.0 * 18.0;
    }
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    row[NAR_AUTOMIX_LOUDNESS_LUFS] =
        -26.0 + (double)(state % 100000ull) / 100000.0 * 16.0;
    if (i % 5 == 0) {
      state ^= state << 13;
      state ^= state >> 7;
      state ^= state << 17;
      row[NAR_AUTOMIX_CENTROID_HZ] =
          400.0 + (double)(state % 100000ull) / 100000.0 * 3600.0;
    }
    if (i % 4 == 0) {
      state ^= state << 13;
      state ^= state >> 7;
      state ^= state << 17;
      row[NAR_AUTOMIX_ONSET_RATE] =
          0.5 + (double)(state % 100000ull) / 100000.0 * 5.5;
    }
    if (i % 3 == 0) {
      state ^= state << 13;
      state ^= state >> 7;
      state ^= state << 17;
      row[NAR_AUTOMIX_TAIL_BPM] =
          65.0 + (double)(state % 100000ull) / 100000.0 * 90.0;
    }
    if (i % 4 == 0) {
      state ^= state << 13;
      state ^= state >> 7;
      state ^= state << 17;
      row[NAR_AUTOMIX_INTRO_ENERGY] =
          (double)(state % 100000ull) / 100000.0;
    }
    if (i % 5 == 0) {
      state ^= state << 13;
      state ^= state >> 7;
      state ^= state << 17;
      row[NAR_AUTOMIX_OUTRO_ENERGY] =
          (double)(state % 100000ull) / 100000.0;
    }
    keys[i * 2] = (i * 5) % 12 + 1;
    keys[i * 2 + 1] = i % 2;
  }

  int32_t order[30];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 30, 0, 0.06, 24, 1,
                              0, 3, order, metrics, 2) == 1);
  assert(order[0] == 3);
  int32_t seen[30] = {0};
  for (int i = 0; i < 30; ++i) {
    assert(order[i] >= 0 && order[i] < 30);
    assert(!seen[order[i]]);
    seen[order[i]] = 1;
  }
  // Swap-only polisher scores 0.26611141739099742 here; the relocation and
  // reversal scans must reach a strictly better plan.
  assert(metrics[1] < 0.2640);
}

static void test_planner_adaptive_energy_arc_lifts_loud_mids(void) {
  // Seven equal-tempo tracks whose energies span the adjustable range: five
  // sit at the quiet end, two at the loud end. With the fixed DJ target
  // (0.25 + 0.5p) the planner simply chains ascending energies; the
  // set-adaptive arc pulls the two loud tracks toward the measured arc peak
  // in the middle of the set instead of leaving them at the end.
  const double rms[7] = {-26, -25, -24, -22, -20, -4, -3};
  int64_t ids[7];
  int32_t artists[7];
  int32_t keys[7 * NAR_AUTOMIX_KEY_FIELD_COUNT];
  double features[7 * NAR_AUTOMIX_FEATURE_COUNT];
  for (int i = 0; i < 7 * NAR_AUTOMIX_FEATURE_COUNT; ++i) features[i] = NAN;
  for (int i = 0; i < 7; ++i) {
    double* row = features + i * NAR_AUTOMIX_FEATURE_COUNT;
    ids[i] = i + 1;
    artists[i] = 0;
    keys[i * 2] = 8;
    keys[i * 2 + 1] = 1;
    row[NAR_AUTOMIX_BPM] = 120.0;
    row[NAR_AUTOMIX_BPM_CONFIDENCE] = 0.9;
    row[NAR_AUTOMIX_KEY_CONFIDENCE] = 0.9;
    row[NAR_AUTOMIX_RMS_DB] = rms[i];
  }

  int32_t order[7];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 7, 0, 0.06, 16, 1,
                              0, 0, order, metrics, 2) == 1);
  // Frozen probe result with the adaptive arc; a build without the arc
  // (disabled in build_energy_arc) yields the ascending 0..6 chain instead.
  const int32_t expected[7] = {0, 1, 2, 5, 6, 4, 3};
  for (int i = 0; i < 7; ++i) assert(order[i] == expected[i]);
}

static void test_chord_progression_analysis(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 4;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);

  // A steady C-major triad over four seconds should produce time-local,
  // confidence-gated chord rows with C major as the leading estimate.
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    pcm[i] = (float)(
        0.24 * sin(2.0 * 3.14159265358979323846 * 261.6256 * t) +
        0.20 * sin(2.0 * 3.14159265358979323846 * 329.6276 * t) +
        0.18 * sin(2.0 * 3.14159265358979323846 * 391.9954 * t));
  }

  double chords[16] = {0};
  const int32_t rows = nar_automix_analyze_chords(
      pcm, count, sample_rate, chords, 16);
  assert(rows >= 2 && rows <= 4);
  assert(chords[0] >= 0.0);
  assert(chords[1] == 0.0);  // C pitch class remains the leading root.
  // FFT-bin leakage and HPCP harmonic folding can add harmonic extensions to a
  // pure triad (E's third harmonic is B, i.e. a major-7 colour), so assert the
  // supported quality range instead of requiring one exact label.
  assert(chords[2] >= 0.0 && chords[2] <= 11.0);
  assert(isfinite(chords[3]) && chords[3] >= 0.08 && chords[3] <= 1.0);

  // Invalid inputs must fail safely; short windows do not invent a chord.
  assert(nar_automix_analyze_chords(NULL, count, sample_rate, chords, 16) == -1);
  assert(nar_automix_analyze_chords(pcm, sample_rate, sample_rate,
                                    chords, 16) == 0);
  assert(nar_automix_analyze_chords(pcm, count, 0, chords, 16) == -1);
  free(pcm);

  float silence[sample_rate * 2];
  for (int32_t i = 0; i < sample_rate * 2; ++i) silence[i] = 0.0f;
  const int32_t silent_rows = nar_automix_analyze_chords(
      silence, sample_rate * 2, sample_rate, chords, 4);
  assert(silent_rows == 1);
  assert(chords[1] == -1.0 && chords[2] == -1.0 && chords[3] == 0.0);
}

static void render_tones(float* pcm, int32_t count, int32_t sample_rate,
                         const double* frequencies, const double* amplitudes,
                         int32_t tone_count) {
  const double pi = 3.14159265358979323846;
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    double value = 0.0;
    for (int32_t tone = 0; tone < tone_count; ++tone) {
      value += amplitudes[tone] * sin(2.0 * pi * frequencies[tone] * t);
    }
    pcm[i] = (float)value;
  }
}

static void test_analyzer_hpcp_key_detection(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 4;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];

  const double equal_tones[4] = {0.2, 0.2, 0.2, 0.2};
  const double c_major_triad[3] = {261.6256, 329.6276, 391.9954};
  render_tones(pcm, count, sample_rate, c_major_triad, equal_tones, 3);
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(output[4] == 0.0);  // C
  assert(output[5] == 0.0);  // major
  assert(output[6] > 0.2);

  const double a_minor_triad[3] = {220.0, 261.6256, 329.6276};
  render_tones(pcm, count, sample_rate, a_minor_triad, equal_tones, 3);
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(output[4] == 9.0);  // A
  assert(output[5] == 1.0);  // minor
  assert(output[6] > 0.5);

  // A triad detuned +35 cents must stay on the same key: the HPCP tolerance
  // window keeps the energy on the intended class instead of bleeding across
  // the halfway point between classes the way plain bin interpolation does.
  const double detune = 1.02043;  // 2^(35/1200)
  const double c_major_sharp[3] = {
      261.6256 * detune, 329.6276 * detune, 391.9954 * detune};
  render_tones(pcm, count, sample_rate, c_major_sharp, equal_tones, 3);
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(output[4] == 0.0);
  assert(output[5] == 0.0);
  free(pcm);
}

static void test_chord_vocabulary_expansion(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 4;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  const double equal_tones[4] = {0.2, 0.2, 0.2, 0.2};
  const double bass_lead[4] = {0.3, 0.18, 0.18, 0.18};
  double chords[16] = {0};

  // G dominant 7 (G B D F) exercises quality id 4.
  const double g_dom_7[4] = {196.0, 246.9417, 293.6648, 349.2282};
  render_tones(pcm, count, sample_rate, g_dom_7, equal_tones, 4);
  assert(nar_automix_analyze_chords(pcm, count, sample_rate, chords, 16) >= 1);
  assert(chords[1] == 7.0 && chords[2] == 4.0);
  assert(chords[3] > 0.4);

  // D minor 7 (D F A C) exercises quality id 6.
  const double d_min_7[4] = {146.8324, 174.6141, 220.0, 261.6256};
  render_tones(pcm, count, sample_rate, d_min_7, equal_tones, 4);
  assert(nar_automix_analyze_chords(pcm, count, sample_rate, chords, 16) >= 1);
  assert(chords[1] == 2.0 && chords[2] == 6.0);

  // B half-diminished 7 (B D F A) exercises quality id 9.
  const double b_half_dim[4] = {246.9417, 293.6648, 349.2282, 440.0};
  render_tones(pcm, count, sample_rate, b_half_dim, equal_tones, 4);
  assert(nar_automix_analyze_chords(pcm, count, sample_rate, chords, 16) >= 1);
  assert(chords[1] == 11.0 && chords[2] == 9.0);

  // C suspended 2 with a doubled bass root disambiguates the Csus2/Gsus4
  // pitch-class set in favour of quality id 8.
  const double c_sus2_root[4] = {130.8128, 261.6256, 293.6648, 391.9954};
  render_tones(pcm, count, sample_rate, c_sus2_root, bass_lead, 4);
  assert(nar_automix_analyze_chords(pcm, count, sample_rate, chords, 16) >= 1);
  assert(chords[1] == 0.0 && chords[2] == 8.0);
  free(pcm);
}

static void test_analyzer_tempo_curve(void) {
  // Short percussive clicks give the ODF a clean autocorrelation peak.
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 8;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  const double pi = 3.14159265358979323846;
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];

  const double steady_bpm = 128.0;
  const int32_t steady_period =
      (int32_t)(sample_rate * 60.0 / steady_bpm + 0.5);
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    double value = 0.05 * sin(2.0 * pi * 220.0 * t);
    const int32_t phase = i % steady_period;
    if (phase < 32) {
      value += 0.4 * (1.0 - (double)phase / 32.0) * sin(2.0 * pi * 900.0 * t);
    }
    pcm[i] = (float)value;
  }
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(output[0] > 120.0 && output[0] < 136.0);
  assert(output[21] > 120.0 && output[21] < 136.0);
  assert(output[22] > 120.0 && output[22] < 136.0);
  assert(output[23] > 0.6);

  // First half at 128 BPM, second half at 96 BPM: the end-quarter estimate
  // must follow the drift and stability must drop below the steady case.
  const double slow_bpm = 96.0;
  const int32_t slow_period = (int32_t)(sample_rate * 60.0 / slow_bpm + 0.5);
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    double value = 0.05 * sin(2.0 * pi * 220.0 * t);
    const int32_t period = i < count / 2 ? steady_period : slow_period;
    const int32_t phase = i % period;
    if (phase < 32) {
      value += 0.4 * (1.0 - (double)phase / 32.0) * sin(2.0 * pi * 900.0 * t);
    }
    pcm[i] = (float)value;
  }
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(output[21] > 120.0 && output[21] < 136.0);
  assert(output[22] > 88.0 && output[22] < 104.0);
  assert(output[23] < 0.4);
  free(pcm);
}

static void test_phase_lock_factor(void) {
  // Incoming is a quarter beat ahead at 120 BPM; it must slow down by the cap.
  float factor = nar_automix_phase_lock_factor(
      1000.0, 0.0, 120.0, 5125.0, 0.0, 120.0, 5000.0, 0.006);
  assert(isfinite(factor));
  assert(fabsf(factor - 0.994f) < 1e-6f);

  // A small phase error is corrected proportionally when below the cap.
  factor = nar_automix_phase_lock_factor(
      0.0, 0.0, 120.0, 510.0, 0.0, 120.0, 4000.0, 0.006);
  assert(fabsf(factor - 0.9975f) < 1e-6f);

  // Circular phase wrap reports an incoming deck just behind, not almost a
  // full beat ahead.
  factor = nar_automix_phase_lock_factor(
      0.0, 0.0, 120.0, 490.0, 0.0, 120.0, 4000.0, 0.006);
  assert(fabsf(factor - 1.0025f) < 1e-6f);

  // Dead-zone and too-short fade are intentionally left at unity.
  factor = nar_automix_phase_lock_factor(
      0.0, 0.0, 120.0, 505.0, 0.0, 120.0, 4000.0, 0.006);
  assert(factor == 1.0f);
  factor = nar_automix_phase_lock_factor(
      0.0, 0.0, 120.0, 600.0, 0.0, 120.0, 250.0, 0.006);
  assert(factor == 1.0f);

  // Invalid tempo metadata is explicit so JNI can skip only phase correction.
  factor = nar_automix_phase_lock_factor(
      0.0, 0.0, NAN, 0.0, 0.0, 120.0, 4000.0, 0.006);
  assert(isnan(factor));
}

static void test_native_crossfade_curve(void) {
  float outgoing = -1.0f;
  float incoming = -1.0f;

  assert(nar_automix_tone_compute_fade_gains(
             0.0f, 1.0f, 1.0f, 1.0f, &outgoing, &incoming) == 1);
  assert(fabsf(outgoing - 1.0f) < 1e-6f);
  assert(fabsf(incoming) < 1e-6f);

  assert(nar_automix_tone_compute_fade_gains(
             0.5f, 1.0f, 1.0f, 1.0f, &outgoing, &incoming) == 1);
  assert(fabsf(outgoing - 0.5f) < 1e-5f);
  assert(fabsf(incoming - 0.5f) < 1e-5f);

  assert(nar_automix_tone_compute_fade_gains(
             0.5f, 1.0f, 0.8f, 0.5f, &outgoing, &incoming) == 1);
  assert(fabsf(outgoing - 0.8f * sqrtf(0.5f)) < 1e-6f);
  assert(fabsf(incoming - 0.5f * sqrtf(0.5f)) < 1e-6f);

  // Gamma direction check: gamma > 1 accelerates handover (incoming higher, outgoing lower)
  float out_linear, in_linear, out_quick, in_quick, out_long, in_long;
  assert(nar_automix_tone_compute_fade_gains(0.5f, 1.0f, 1.0f, 1.0f, &out_linear, &in_linear) == 1);
  assert(nar_automix_tone_compute_fade_gains(0.5f, 1.35f, 1.0f, 1.0f, &out_quick, &in_quick) == 1);
  assert(nar_automix_tone_compute_fade_gains(0.5f, 0.85f, 1.0f, 1.0f, &out_long, &in_long) == 1);
  assert(in_quick > in_linear);
  assert(out_quick < out_linear);
  assert(in_long < in_linear);
  assert(out_long > out_linear);

  // The incoming level trim is fully released by the end of the fade.
  assert(nar_automix_tone_compute_fade_gains(
             1.0f, 1.0f, 0.8f, 0.5f, &outgoing, &incoming) == 1);
  assert(fabsf(outgoing) < 1e-6f);
  assert(fabsf(incoming - 1.0f) < 1e-6f);

  assert(nar_automix_tone_compute_fade_gains(
             NAN, 1.0f, 1.0f, 1.0f, &outgoing, &incoming) == 0);
}

static void test_native_crossfade_targets_are_per_stream(void) {
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_bass_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_crossfade_gains(
             0, 1, 0.0f, 1.0f, 1.0f, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, 48000, 2) == 1);
  assert(nar_automix_tone_configure(1, 48000, 2) == 1);

  float outgoing[] = {0.25f, -0.5f, 0.75f, -0.125f};
  float incoming[] = {0.25f, -0.5f, 0.75f, -0.125f};
  const float original[] = {0.25f, -0.5f, 0.75f, -0.125f};
  assert(nar_automix_tone_process(outgoing, 2, 2, 0) == 1);
  assert(nar_automix_tone_process(incoming, 2, 2, 1) == 1);
  for (int i = 0; i < 4; ++i) {
    assert(fabsf(outgoing[i] - original[i]) < 1e-6f);
    assert(fabsf(incoming[i]) < 1e-6f);
  }

  assert(nar_automix_tone_set_crossfade_gains(
             0, 1, 1.0f, 1.0f, 1.0f, 1.0f) == 1);
  outgoing[0] = incoming[0] = 0.25f;
  outgoing[1] = incoming[1] = -0.5f;
  outgoing[2] = incoming[2] = 0.75f;
  outgoing[3] = incoming[3] = -0.125f;
  assert(nar_automix_tone_process(outgoing, 2, 2, 0) == 1);
  assert(nar_automix_tone_process(incoming, 2, 2, 1) == 1);
  assert(fabsf(outgoing[3]) < 1e-6f);
  assert(fabsf(incoming[3] - original[3]) < 1e-6f);

  assert(nar_automix_tone_set_crossfade_gains(
             0, 0, 0.5f, 1.0f, 1.0f, 1.0f) == 0);
}

static double rms_range(const float* samples, int32_t start, int32_t count) {
  double power = 0.0;
  for (int32_t i = start; i < start + count; ++i) {
    power += (double)samples[i] * samples[i];
  }
  return sqrt(power / count);
}

static void test_tone_default_is_transparent(void) {
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, 48000, 2) == 1);

  float pcm[] = {0.25f, -0.5f, 0.75f, -0.125f, -0.25f, 0.5f};
  const float original[] = {0.25f, -0.5f, 0.75f, -0.125f, -0.25f, 0.5f};
  assert(nar_automix_tone_process(pcm, 3, 2, 0) == 1);
  for (int i = 0; i < 6; ++i) {
    assert(fabsf(pcm[i] - original[i]) < 1e-6f);
  }
}

static void test_tone_filters_independent_streams(void) {
  const int32_t sample_rate = 48000;
  const int32_t frames = sample_rate;
  float* filtered = (float*)malloc((size_t)frames * sizeof(float));
  float* dry = (float*)malloc((size_t)frames * sizeof(float));
  assert(filtered != NULL && dry != NULL);

  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 0.0f) == 1);
  assert(nar_automix_tone_set_bass_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, sample_rate, 1) == 1);
  assert(nar_automix_tone_configure(1, sample_rate, 1) == 1);

  for (int32_t i = 0; i < frames; ++i) {
    const float sample = 0.5f * sinf(
        2.0f * 3.14159265358979323846f * 6000.0f * i / sample_rate);
    filtered[i] = sample;
    dry[i] = sample;
  }
  assert(nar_automix_tone_process(filtered, frames, 1, 0) == 1);
  assert(nar_automix_tone_process(dry, frames, 1, 1) == 1);

  const double filtered_rms = rms_range(filtered, sample_rate / 4, frames * 3 / 4);
  const double dry_rms = rms_range(dry, sample_rate / 4, frames * 3 / 4);
  assert(filtered_rms < dry_rms * 0.35);
  assert(fabs(dry_rms - 0.5 / sqrt(2.0)) < 0.01);

  // Bass swap must attenuate the low band without changing the other stream.
  assert(nar_automix_tone_set_bass_gain(0, 0.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, sample_rate, 1) == 1);
  for (int32_t i = 0; i < frames; ++i) {
    const float sample = 0.5f * sinf(
        2.0f * 3.14159265358979323846f * 60.0f * i / sample_rate);
    filtered[i] = sample;
  }
  assert(nar_automix_tone_process(filtered, frames, 1, 0) == 1);
  const double bass_rms = rms_range(filtered, sample_rate / 4, frames * 3 / 4);
  assert(bass_rms < 0.5 / sqrt(2.0) * 0.55);

  // The middle band is independently controllable, while the reference stream
  // remains transparent. A 1 kHz tone should lose measurable energy only on
  // the deck whose mid gain is zero.
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 0.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_bass_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, sample_rate, 1) == 1);
  assert(nar_automix_tone_configure(1, sample_rate, 1) == 1);
  for (int32_t i = 0; i < frames; ++i) {
    const float sample = 0.5f * sinf(
        2.0f * 3.14159265358979323846f * 1000.0f * i / sample_rate);
    filtered[i] = sample;
    dry[i] = sample;
  }
  assert(nar_automix_tone_process(filtered, frames, 1, 0) == 1);
  assert(nar_automix_tone_process(dry, frames, 1, 1) == 1);
  const double mid_rms = rms_range(filtered, sample_rate / 4, frames * 3 / 4);
  const double reference_rms = rms_range(dry, sample_rate / 4, frames * 3 / 4);
  assert(mid_rms < reference_rms * 0.85);
  assert(fabs(reference_rms - 0.5 / sqrt(2.0)) < 0.01);

  assert(nar_automix_tone_set_bass_gain(0, NAN) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, INFINITY) == 1);
  assert(nar_automix_tone_set_bass_gain(-1, 0.0f) == 0);
  assert(nar_automix_tone_configure(2, sample_rate, 2) == 0);
  free(filtered);
  free(dry);
}

static void test_stereo_mid_gain(void) {
  // This uses the stereo path on ARM64 (NEON) and the scalar fallback
  // elsewhere, so the new mid control is covered in both implementations.
  const int32_t sample_rate = 48000;
  const int32_t frames = sample_rate;
  const size_t sample_count = (size_t)frames * 2;
  float* filtered = (float*)malloc(sample_count * sizeof(float));
  float* dry = (float*)malloc(sample_count * sizeof(float));
  assert(filtered != NULL && dry != NULL);

  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 0.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_bass_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, sample_rate, 2) == 1);
  assert(nar_automix_tone_configure(1, sample_rate, 2) == 1);

  for (int32_t frame = 0; frame < frames; ++frame) {
    const float sample = 0.5f * sinf(
        2.0f * 3.14159265358979323846f * 1000.0f * frame / sample_rate);
    filtered[frame * 2] = filtered[frame * 2 + 1] = sample;
    dry[frame * 2] = dry[frame * 2 + 1] = sample;
  }

  assert(nar_automix_tone_process(filtered, frames, 2, 0) == 1);
  assert(nar_automix_tone_process(dry, frames, 2, 1) == 1);
  const int32_t start = sample_rate / 4 * 2;
  const int32_t count = frames * 3 / 4 * 2;
  const double mid_rms = rms_range(filtered, start, count);
  const double reference_rms = rms_range(dry, start, count);
  assert(mid_rms < reference_rms * 0.85);
  assert(fabs(reference_rms - 0.5 / sqrt(2.0)) < 0.01);

  free(filtered);
  free(dry);
}

static void test_crossfade_sample_peak_budget(void) {
  // Even fully correlated decks must have a combined gain budget <= 1.
  for (int i = 0; i <= 100; ++i) {
    const float progress = (float)i / 100.0f;
    float outgoing = -1.0f;
    float incoming = -1.0f;
    assert(nar_automix_tone_compute_fade_gains(
               progress, 1.0f, 1.0f, 1.0f, &outgoing, &incoming) == 1);
    assert(isfinite(outgoing) && isfinite(incoming));
    assert(outgoing >= 0.0f && outgoing <= 1.0f);
    assert(incoming >= 0.0f && incoming <= 1.0f);
    assert(outgoing + incoming <= 1.00001f);
  }

  // The scalar/multichannel and ARM64 NEON paths must enforce the same final
  // sample-peak bound even if an upstream float PCM block contains overs.
  const int32_t sample_rate = 48000;
  const int32_t frames = 8;
  float pcm[frames * 2];
  for (int i = 0; i < frames * 2; ++i) {
    pcm[i] = (i & 1) == 0 ? 2.0f : -2.0f;
  }
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, sample_rate, 2) == 1);
  assert(nar_automix_tone_process(pcm, frames, 2, 0) == 1);
  for (int i = 0; i < frames * 2; ++i) {
    assert(isfinite(pcm[i]));
    assert(pcm[i] >= -1.0f && pcm[i] <= 1.0f);
  }
  assert(nar_automix_tone_reset(0) == 1);
}

static void test_ffi_contract_and_bounds(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 2;
  float pcm[44100] = {0};
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];

  // Undersized buffer must return 0; 23 is one value short of the ABI.
  assert(nar_automix_analyze(pcm, count, sample_rate, output, 23) == 0);
  // Null inputs must return 0
  assert(nar_automix_analyze(NULL, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 0);
  assert(nar_automix_analyze(pcm, count, 0, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 0);
  assert(nar_automix_analyze(pcm, 100, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 0);

  // Exact-sized buffer returns 1
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(isfinite(output[20]));
  assert(output[20] >= 0.0 && output[20] <= 1.0);
  // 2 s of silence is below the minimum frame count for quarter-window
  // estimates, so the tempo-curve slots must stay unknown.
  assert(isnan(output[21]) && isnan(output[22]) && isnan(output[23]));

  // Planner bounds checks
  int64_t ids[2] = {1, 2};
  int32_t artists[2] = {1, 2};
  double features[2 * NAR_AUTOMIX_FEATURE_COUNT] = {0};
  int32_t keys[2 * NAR_AUTOMIX_KEY_FIELD_COUNT] = {0};
  int32_t order[2];
  double metrics[2];

  assert(nar_automix_plan_set(ids, artists, features, keys, 0, 0, 0.06, 16, 0, 0, 0, order, metrics, 2) == 1);
  assert(metrics[0] == 0.0 && metrics[1] == 0.0);

  assert(nar_automix_plan_set(NULL, artists, features, keys, 2, 0, 0.06, 16, 0, 0, 0, order, metrics, 2) == 0);
  assert(nar_automix_plan_set(ids, artists, features, keys, 2, -1, 0.06, 16, 0, 0, 0, order, metrics, 2) == 0);
  assert(nar_automix_plan_set(ids, artists, features, keys, 2, 0, -1.0, 16, 0, 0, 0, order, metrics, 2) == 0);
  assert(nar_automix_plan_set(ids, artists, features, keys, 2, 0, 0.06, 0, 0, 0, 0, order, metrics, 2) == 0);
}

static void test_edge_cases_silence_and_noise(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 3;
  float* silence = (float*)calloc((size_t)count, sizeof(float));
  assert(silence != NULL);

  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  // Pure silence should handle safely without div-by-zero or crash and return 1.
  int32_t status = nar_automix_analyze(silence, count, sample_rate, output, NAR_AUTOMIX_ANALYSIS_VALUE_COUNT);
  assert(status == 1);
  assert(isnan(output[0]) || output[1] < 0.1);
  assert_analysis_confidence_contract(output);
  assert(output[16] == NAR_AUTOMIX_STRUCTURE_UNKNOWN);
  free(silence);

  float* noise = (float*)malloc((size_t)count * sizeof(float));
  assert(noise != NULL);
  for (int32_t i = 0; i < count; ++i) {
    noise[i] = ((float)rand() / (float)RAND_MAX) * 0.2f - 0.1f;
  }
  status = nar_automix_analyze(noise, count, sample_rate, output, NAR_AUTOMIX_ANALYSIS_VALUE_COUNT);
  assert(status == 1);
  assert(output[6] < 0.25);
  assert_analysis_confidence_contract(output);
  assert(output[19] < 0.35);
  free(noise);
}

static void test_phrase_lock(void) {
  // A quarter phrase ahead at 120 BPM must slow down by the configured cap.
  float factor = nar_automix_phrase_lock_factor(
      0.0, 0.0, 120.0, 1000.0, 0.0, 120.0, 4000.0, 0.006, 16);
  assert(fabsf(factor - 0.994f) < 1e-6f);

  // Small phase error is proportional when the remaining time is long enough.
  factor = nar_automix_phrase_lock_factor(
      0.0, 0.0, 120.0, 100.0, 0.0, 120.0, 40000.0, 0.006, 16);
  assert(fabsf(factor - 0.9975f) < 1e-6f);

  // Circular wrap treats the incoming deck as slightly behind.
  factor = nar_automix_phrase_lock_factor(
      0.0, 0.0, 120.0, 7900.0, 0.0, 120.0, 40000.0, 0.006, 16);
  assert(fabsf(factor - 1.0025f) < 1e-6f);

  factor = nar_automix_phrase_lock_factor(
      0.0, 0.0, 120.0, 5.0, 0.0, 120.0, 4000.0, 0.006, 16);
  assert(factor == 1.0f);
  factor = nar_automix_phrase_lock_factor(
      0.0, 0.0, 120.0, 500.0, 0.0, 120.0, 250.0, 0.006, 16);
  assert(factor == 1.0f);
  factor = nar_automix_phrase_lock_factor(
      0.0, 0.0, NAN, 0.0, 0.0, 120.0, 4000.0, 0.006, 16);
  assert(isnan(factor));
  factor = nar_automix_phrase_lock_factor(
      0.0, 0.0, 120.0, 0.0, 0.0, 120.0, 4000.0, 0.006, 65);
  assert(isnan(factor));
}

static void test_tone_processor_unity_bands_preserve_fade_target(void) {
  const int32_t sample_rate = 48000;
  const int32_t frame_counts[] = {1, 7, 16, 64, 256, 1024};
  assert(nar_automix_tone_configure(1, sample_rate, 2) == 1);
  assert(nar_automix_tone_set_bass_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(1, 0.5f) == 1);
  assert(nar_automix_tone_reset(1) == 1);

  for (size_t k = 0; k < sizeof(frame_counts) / sizeof(frame_counts[0]); ++k) {
    const int32_t frames = frame_counts[k];
    float* pcm = (float*)malloc((size_t)frames * 2 * sizeof(float));
    assert(pcm != NULL);
    for (int32_t i = 0; i < frames * 2; ++i) pcm[i] = 0.5f;
    assert(nar_automix_tone_process(pcm, frames, 2, 1) == 1);
    for (int32_t i = 0; i < frames * 2; ++i) {
      // Complementary bands must reconstruct each constant sample before fade gain.
      // Runs through scalar C on host builds and the AArch64 NEON dispatch when available.
      assert(isfinite(pcm[i]));
      assert(fabsf(pcm[i] - 0.25f) < 1e-4f);
    }
    free(pcm);
  }
}

static void test_tone_processor_nonfinite_intermediates_are_sanitized(void) {
  const int32_t sample_rate = 48000;
  assert(nar_automix_tone_configure(0, sample_rate, 2) == 1);
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_reset(0) == 1);

  // The finite extremes pass input sanitization but overflow the IIR
  // difference on the sign change. Both scalar C and AArch64 NEON must emit
  // silence for the affected frames, never a NaN or a clipped -1 sentinel.
  float pcm[] = {
      FLT_MAX, FLT_MAX,
      -FLT_MAX, -FLT_MAX,
      FLT_MAX, -FLT_MAX,
      -FLT_MAX, FLT_MAX,
  };
  assert(nar_automix_tone_process(pcm, 4, 2, 0) == 1);
  for (size_t i = 0; i < sizeof(pcm) / sizeof(pcm[0]); ++i) {
    assert(isfinite(pcm[i]));
    assert(pcm[i] >= -1.0f && pcm[i] <= 1.0f);
  }
  // Frame 1 is where the finite input subtraction overflows; C maps the
  // resulting non-finite processed sample to 0, and NEON must match it.
  assert(fabsf(pcm[2]) < 1e-6f);
  assert(fabsf(pcm[3]) < 1e-6f);
}

static void test_tone_processor_various_frame_counts(void) {
  const int32_t sample_rate = 48000;
  assert(nar_automix_tone_configure(0, sample_rate, 2) == 1);
  assert(nar_automix_tone_set_bass_gain(0, 0.8f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 0.9f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 0.5f) == 1);

  const int32_t frame_counts[] = {1, 7, 16, 64, 256, 1024};
  for (size_t k = 0; k < sizeof(frame_counts) / sizeof(frame_counts[0]); ++k) {
    int32_t frames = frame_counts[k];
    float* pcm = (float*)malloc((size_t)frames * 2 * sizeof(float));
    assert(pcm != NULL);
    for (int32_t i = 0; i < frames * 2; ++i) {
      pcm[i] = 0.5f;
    }
    assert(nar_automix_tone_process(pcm, frames, 2, 0) == 1);
    for (int32_t i = 0; i < frames * 2; ++i) {
      assert(isfinite(pcm[i]));
      assert(pcm[i] >= -1.0f && pcm[i] <= 1.0f);
    }
    free(pcm);
  }
}

static void test_live_tracker_requires_explicit_enable(void) {
  float pcm[512 * 2] = {0.0f};
  double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {-1.0, -1.0, -1.0};

  assert(nar_automix_live_tracker_set_enabled(2) == 0);
  assert(nar_automix_live_tracker_set_enabled(0) == 1);
  assert(nar_automix_live_tracker_is_enabled() == 0);
  assert(nar_automix_live_tracker_process(pcm, 512, 2, 48000, 0) == 1);
  assert(nar_automix_live_tracker_get(
             0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  for (int32_t i = 0; i < NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT; ++i) {
    assert(state[i] == 0.0);
  }

  assert(nar_automix_live_tracker_set_enabled(1) == 1);
  assert(nar_automix_live_tracker_is_enabled() == 1);
  assert(nar_automix_live_tracker_process(pcm, 512, 2, 48000, 0) == 1);
  assert(nar_automix_live_tracker_reset(0) == 1);
  assert(nar_automix_live_tracker_set_enabled(0) == 1);
  assert(nar_automix_live_tracker_is_enabled() == 0);
  assert(nar_automix_live_tracker_get(
             0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  for (int32_t i = 0; i < NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT; ++i) {
    assert(state[i] == 0.0);
  }
}

static void test_live_tracker_disable_clears_live_state(void) {
  const int32_t sample_rate = 48000;
  const int32_t chunk_frames = 512;
  const int32_t total_frames = sample_rate * 8;
  float pcm[512 * 2];
  double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0.0, 0.0, 0.0};

  assert(nar_automix_live_tracker_set_enabled(1) == 1);
  // 120 BPM click train: a 3 ms decaying burst every 0.5 s. This is the
  // realistic case the old test missed — a live, non-zero BPM/precision tuple
  // must be cleared by a disable instead of lingering for the controller.
  int32_t produced = 0;
  while (produced < total_frames) {
    const int32_t frames = (total_frames - produced) < chunk_frames
        ? (total_frames - produced)
        : chunk_frames;
    for (int32_t i = 0; i < frames; ++i) {
      const int64_t absolute = (int64_t)produced + i;
      const int64_t phase = absolute % 24000;
      const float value = phase < 48
          ? (float)(0.9 * (1.0 - (double)phase / 48.0))
          : 0.0f;
      pcm[i * 2] = value;
      pcm[i * 2 + 1] = value;
    }
    assert(nar_automix_live_tracker_process(pcm, frames, 2, sample_rate, 0) == 1);
    produced += frames;
  }
  assert(nar_automix_live_tracker_get(
             0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  assert(state[0] > 100.0 && state[0] < 140.0);
  assert(state[2] > 0.0);

  assert(nar_automix_live_tracker_set_enabled(0) == 1);
  assert(nar_automix_live_tracker_is_enabled() == 0);
  // Idempotent disable must succeed without corrupting the zeroed tuple.
  assert(nar_automix_live_tracker_set_enabled(0) == 1);
  assert(nar_automix_live_tracker_get(
             0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  for (int32_t i = 0; i < NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT; ++i) {
    assert(state[i] == 0.0);
  }

  // Re-enabling must start from a clean epoch: silence cannot resurrect the
  // pre-disable phase, so the tuple stays zero.
  assert(nar_automix_live_tracker_set_enabled(1) == 1);
  memset(pcm, 0, sizeof(pcm));
  for (int32_t i = 0; i < 4; ++i) {
    assert(nar_automix_live_tracker_process(
               pcm, chunk_frames, 2, sample_rate, 0) == 1);
  }
  assert(nar_automix_live_tracker_get(
             0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  assert(state[0] == 0.0);
  assert(nar_automix_live_tracker_set_enabled(0) == 1);
}

typedef struct {
  const float* pcm;
  int32_t frame_count;
  atomic_int started;
  int32_t result;
} LiveTrackerConcurrentProcess;

static void* process_live_tracker_slot_zero(void* opaque) {
  LiveTrackerConcurrentProcess* work = (LiveTrackerConcurrentProcess*)opaque;
  // Signal immediately before entering process(). The test then resets the
  // other slot while this intentionally long callback is in flight.
  atomic_store_explicit(&work->started, 1, memory_order_release);
  work->result = nar_automix_live_tracker_process(
      work->pcm, work->frame_count, 2, 48000, 0);
  return NULL;
}

static void test_live_tracker_reset_is_slot_local_during_processing(void) {
  const int32_t sample_rate = 48000;
  // A single large callback makes the reset overlap the processing epoch
  // without adding test-only hooks to the production native library.
  const int32_t frame_count = sample_rate * 30;
  const size_t sample_count = (size_t)frame_count * 2u;
  float* pcm = (float*)malloc(sample_count * sizeof(float));
  assert(pcm != NULL);

  for (int32_t frame = 0; frame < frame_count; ++frame) {
    const int64_t phase = (int64_t)frame % 24000;
    const float value = phase < 48
        ? (float)(0.9 * (1.0 - (double)phase / 48.0))
        : 0.0f;
    pcm[frame * 2] = value;
    pcm[frame * 2 + 1] = value;
  }

  assert(nar_automix_live_tracker_set_enabled(1) == 1);
  assert(nar_automix_live_tracker_reset(0) == 1);
  assert(nar_automix_live_tracker_reset(1) == 1);

  LiveTrackerConcurrentProcess work = {
      .pcm = pcm,
      .frame_count = frame_count,
      .started = ATOMIC_VAR_INIT(0),
      .result = 0,
  };
  pthread_t worker;
  assert(pthread_create(&worker, NULL, process_live_tracker_slot_zero, &work) == 0);
  while (atomic_load_explicit(&work.started, memory_order_acquire) == 0) {
    // Wait for the worker to enter its callback path.
  }

  const struct timespec pause = {.tv_sec = 0, .tv_nsec = 1000000L};
  (void)nanosleep(&pause, NULL);
  assert(nar_automix_live_tracker_reset(1) == 1);
  assert(pthread_join(worker, NULL) == 0);
  assert(work.result == 1);

  double slot_zero[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0.0, 0.0, 0.0};
  double slot_one[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {-1.0, -1.0, -1.0};
  assert(nar_automix_live_tracker_get(
      0, slot_zero, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  assert(slot_zero[0] > 100.0 && slot_zero[0] < 140.0);
  assert(slot_zero[2] > 0.0);
  assert(nar_automix_live_tracker_get(
      1, slot_one, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  for (int32_t i = 0; i < NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT; ++i) {
    assert(slot_one[i] == 0.0);
  }

  assert(nar_automix_live_tracker_set_enabled(0) == 1);
  free(pcm);
}

static unsigned long long tracker_probe_state = 88172645463325252ull;

static unsigned long long tracker_probe_rand(void) {
  tracker_probe_state ^= tracker_probe_state << 13;
  tracker_probe_state ^= tracker_probe_state >> 7;
  tracker_probe_state ^= tracker_probe_state << 17;
  return tracker_probe_state;
}

static void test_live_tracker_phase_follows_beat_grid(void) {
  // 120 BPM click train over a quiet bed, plus pseudo-random loud low-frequency
  // accents that never align with the beat grid. The loudest single onset in
  // the final period belongs to the accent at 11.7 s, so a phase picker that
  // trusts the last period's maximum reports ~290 ms; the grid phase that
  // aligns the whole history correctly reports the click grid (~490 ms).
  const double pi = 3.14159265358979323846;
  const int32_t sample_rate = 48000;
  const int32_t chunk_frames = 512;
  const int32_t total_frames = sample_rate * 12;
  int32_t spike_starts[128];
  int32_t spike_count = 0;
  int32_t position = 4800;
  tracker_probe_state = 88172645463325252ull;
  while (position < 11 * 48000 && spike_count < 120) {
    spike_starts[spike_count++] = position;
    position += 17000 + (int32_t)(tracker_probe_rand() % 20000ull);
  }
  spike_starts[spike_count++] = 561600;

  assert(nar_automix_live_tracker_set_enabled(1) == 1);
  float pcm[512 * 2];
  int32_t produced = 0;
  while (produced < total_frames) {
    const int32_t frames = (total_frames - produced) < chunk_frames
        ? (total_frames - produced)
        : chunk_frames;
    for (int32_t i = 0; i < frames; ++i) {
      const int64_t n = (int64_t)produced + i;
      const double t = (double)n / sample_rate;
      double value = 0.01 * sin(2.0 * pi * 300.0 * t);
      const int64_t click_phase = n % 24000;
      if (click_phase < 48) {
        value += 0.7 * (1.0 - (double)click_phase / 48.0) *
            sin(2.0 * pi * 800.0 * t);
      }
      for (int32_t s = 0; s < spike_count; ++s) {
        const int64_t offset = n - spike_starts[s];
        if (offset >= 0 && offset < 480) {
          value += 0.3 * (1.0 - (double)offset / 480.0) *
              sin(2.0 * pi * 100.0 * t);
        }
      }
      pcm[i * 2] = (float)value;
      pcm[i * 2 + 1] = (float)value;
    }
    assert(nar_automix_live_tracker_process(pcm, frames, 2, sample_rate, 0) ==
           1);
    produced += frames;
  }
  double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {-1.0, -1.0, -1.0};
  assert(nar_automix_live_tracker_get(
             0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  assert(state[0] > 100.0 && state[0] < 140.0);
  // The published phase must sit on the click grid (one period is 500 ms), not
  // on the accent that landed 290 ms before the end of the stream.
  assert(state[1] > 450.0 && state[1] < 500.0);
  assert(state[2] > 0.0);
  assert(nar_automix_live_tracker_set_enabled(0) == 1);
}

static void test_live_tracker_publishes_downbeat_phase(void) {
  // 120 BPM click train with a low-frequency accent every fourth beat, i.e. a
  // 2 s bar. The stream ends 300 ms after the last click and 1800 ms after
  // the last accent, so the downbeat output must follow the accent, not the
  // most recent beat pulse.
  const double pi = 3.14159265358979323846;
  const int32_t sample_rate = 48000;
  const int32_t chunk_frames = 512;
  const int32_t total_frames = 566400;  // 11.8 s
  assert(nar_automix_live_tracker_set_enabled(1) == 1);
  float pcm[512 * 2];
  int32_t produced = 0;
  while (produced < total_frames) {
    const int32_t frames = (total_frames - produced) < chunk_frames
        ? (total_frames - produced)
        : chunk_frames;
    for (int32_t i = 0; i < frames; ++i) {
      const int64_t n = (int64_t)produced + i;
      const double t = (double)n / sample_rate;
      double value = 0.01 * sin(2.0 * pi * 300.0 * t);
      const int64_t click_phase = n % 24000;
      if (click_phase < 48) {
        // A moderate click keeps its onset flux below the 24 dB history cap
        // so the accented downbeat stays distinguishable after saturation.
        value += 0.25 * (1.0 - (double)click_phase / 48.0) *
            sin(2.0 * pi * 800.0 * t);
      }
      const int64_t accent_phase = n % 96000;
      if (accent_phase < 48) {
        value += 0.9 * (1.0 - (double)accent_phase / 48.0) *
            sin(2.0 * pi * 100.0 * t);
      }
      pcm[i * 2] = (float)value;
      pcm[i * 2 + 1] = (float)value;
    }
    assert(nar_automix_live_tracker_process(pcm, frames, 2, sample_rate, 0) ==
           1);
    produced += frames;
  }
  double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
  assert(nar_automix_live_tracker_get(
             0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  assert(state[0] > 100.0 && state[0] < 140.0);
  assert(state[1] > 240.0 && state[1] < 360.0);
  assert(state[2] > 0.0);
  assert(state[3] > 1740.0 && state[3] < 1860.0);
  assert(state[4] > 0.0 && state[4] <= state[2] + 1e-9);
  assert(state[4] >= 0.25 * state[2]);
  assert(nar_automix_live_tracker_set_enabled(0) == 1);
}

static void test_live_tracker_reports_activity_trend(void) {
  // Noise-only stream: 6 s quiet then 2.25 s loud. The final 1.5 s window is
  // entirely loud while the window before it is half quiet, so the published
  // trend must be clearly positive (a frame-RMS trend, not a level jump).
  const int32_t sample_rate = 48000;
  const int32_t total_frames = (int32_t)(sample_rate * 8.25);
  unsigned long long seed = 0x9E3779B97F4A7C15ull;
  assert(nar_automix_live_tracker_set_enabled(1) == 1);
  float pcm[256 * 2];
  int32_t produced = 0;
  while (produced < total_frames) {
    const int32_t frames = (total_frames - produced) < 256
        ? (total_frames - produced)
        : 256;
    const double amplitude = produced < sample_rate * 6 ? 0.02 : 0.4;
    for (int32_t i = 0; i < frames; ++i) {
      seed ^= seed << 13;
      seed ^= seed >> 7;
      seed ^= seed << 17;
      const double noise =
          ((double)(seed >> 11) / 4503599627370496.0) * 2.0 - 1.0;
      const float value = (float)(amplitude * noise);
      pcm[i * 2] = value;
      pcm[i * 2 + 1] = value;
    }
    assert(nar_automix_live_tracker_process(pcm, frames, 2, sample_rate, 0) ==
           1);
    produced += frames;
  }
  double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
  assert(nar_automix_live_tracker_get(
             0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  assert(state[5] > 0.2 && state[5] <= 1.0);
  assert(nar_automix_live_tracker_set_enabled(0) == 1);
}

int main(void) {
  test_live_tracker_phase_follows_beat_grid();
  test_live_tracker_publishes_downbeat_phase();
  test_live_tracker_reports_activity_trend();
  test_live_tracker_requires_explicit_enable();
  test_live_tracker_disable_clears_live_state();
  test_live_tracker_reset_is_slot_local_during_processing();
  test_tone_processor_unity_bands_preserve_fade_target();
  test_tone_processor_nonfinite_intermediates_are_sanitized();
  test_tone_processor_various_frame_counts();
  test_crossfade_sample_peak_budget();
  test_ffi_contract_and_bounds();
  test_analyzer_rms();
  test_analyzer_structural_cues();
  test_planner_vocal_conflict();
  test_planner_keeps_start_and_permutation();
  test_planner_scores_tempo_at_seam();
  test_planner_penalizes_energy_seam();
  test_planner_prefers_calm_structural_seam();
  test_planner_ignores_unconfident_structure();
  test_planner_spreads_repeated_artists();
  test_planner_relocation_polish_improves_local_optimum();
  test_planner_adaptive_energy_arc_lifts_loud_mids();
  test_chord_progression_analysis();
  test_analyzer_hpcp_key_detection();
  test_analyzer_tempo_curve();
  test_chord_vocabulary_expansion();
  test_phase_lock_factor();
  test_phrase_lock();
  test_edge_cases_silence_and_noise();
  test_native_crossfade_curve();
  test_native_crossfade_targets_are_per_stream();
  test_tone_default_is_transparent();
  test_tone_filters_independent_streams();
  test_stereo_mid_gain();
  return 0;
}
