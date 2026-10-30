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
  // Local tempo confidence and phase are optional when a quarter is too short
  // or its onset grid is ambiguous.
  assert(isnan(output[28]) ||
         (output[28] >= 0.0 && output[28] <= 1.0));
  assert(isnan(output[29]) ||
         (output[29] >= 0.0 && output[29] <= 1.0));
  assert(isnan(output[30]) || output[30] >= 0.0);
  assert(isnan(output[31]) || output[31] >= 0.0);
  // Quarter RMS profile: always finite for a successful analysis and ordered
  // as four consecutive quarters of the same frame timeline.
  for (int index = 24; index <= 27; ++index) {
    assert(isfinite(output[index]));
    assert(output[index] <= 0.0 && output[index] >= -120.0);
  }
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

static void render_formant_vocal_pcm(float* pcm, int32_t count,
                                     int32_t sample_rate) {
  const double pi = 3.141592653589793;
  double amplitudes[25] = {0.0};
  double weights[25] = {0.0};
  for (int32_t harmonic = 1; harmonic <= 24; ++harmonic) {
    const double frequency = 130.0 * harmonic;
    const double formant =
        exp(-pow((frequency - 800.0) / 500.0, 2.0)) +
        0.7 * exp(-pow((frequency - 1800.0) / 700.0, 2.0));
    amplitudes[harmonic] = 0.06 * formant;
    weights[harmonic] = 2.0 * pi * frequency;
  }
  unsigned int seed = 0x51ED270Bu;
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    const double envelope = 0.55 + 0.45 * sin(2.0 * pi * 2.0 * t);
    double value = 0.0;
    for (int32_t harmonic = 1; harmonic <= 24; ++harmonic) {
      value += amplitudes[harmonic] *
          sin(weights[harmonic] * t) / sqrt((double)harmonic);
    }
    seed = seed * 1664525u + 1013904223u;
    const double noise = ((double)(seed >> 8) / 16777216.0) * 2.0 - 1.0;
    value += noise * 0.15;
    pcm[i] = (float)(value * envelope);
  }
}

static void test_analyzer_vocal_center_channel(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 6;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  render_formant_vocal_pcm(pcm, count, sample_rate);

  double mono[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  double centered[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  double wide[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  double clamped[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  double no_center[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  assert(nar_automix_analyze(pcm, count, sample_rate, mono,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(nar_automix_analyze_centered(pcm, count, sample_rate, 0.92, centered,
                                      NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(nar_automix_analyze_centered(pcm, count, sample_rate, 0.05, wide,
                                      NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(nar_automix_analyze_centered(pcm, count, sample_rate, 2.0, clamped,
                                      NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(nar_automix_analyze_centered(pcm, count, sample_rate, NAN, no_center,
                                      NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);

  assert_analysis_confidence_contract(mono);
  assert_analysis_confidence_contract(centered);
  assert_analysis_confidence_contract(wide);
  // The synth has a speech-band spectral shape but is not a real vocal.
  assert(mono[19] >= 0.45);
  // Mono input cannot use center-channel evidence and stays at the old cap.
  assert(mono[19] <= 0.65 + 1e-9);
  // A centered source should be more vocal-confident than a wide one.
  assert(centered[19] > wide[19] + 0.05);
  assert(centered[18] > wide[18] + 0.05);
  assert(centered[19] <= 0.75 + 1e-9);
  assert(fabs(clamped[19] - centered[19]) < 1e-12);
  assert(fabs(no_center[19] - mono[19]) < 1e-12);
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

static void test_planner_falls_back_to_head_when_tail_tempo_is_untrusted(void) {
  const int64_t ids[] = {1, 2, 3};
  const int32_t artists[] = {1, 2, 3};
  double features[3 * NAR_AUTOMIX_FEATURE_COUNT];
  int32_t keys[3 * NAR_AUTOMIX_KEY_FIELD_COUNT];
  for (int i = 0; i < 3 * NAR_AUTOMIX_FEATURE_COUNT; ++i) features[i] = NAN;
  for (int i = 0; i < 3; ++i) {
    double* row = features + i * NAR_AUTOMIX_FEATURE_COUNT;
    row[NAR_AUTOMIX_BPM_CONFIDENCE] = 0.95;
    row[NAR_AUTOMIX_KEY_CONFIDENCE] = 0.9;
    row[NAR_AUTOMIX_RMS_DB] = -12.0;
    keys[i * 2] = 8;
    keys[i * 2 + 1] = 1;
  }

  // The outgoing head is 100 BPM, but its 128 BPM tail estimate is unreliable.
  // The 100 BPM candidate must win; head confidence must not be applied to the
  // untrusted tail estimate.
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_BPM] = 100.0;
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_TAIL_BPM] = 128.0;
  features[0 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_TAIL_BPM_CONFIDENCE] = 0.1;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_BPM] = 128.0;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_BPM] = 100.0;

  int32_t order[3];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 3, 0, 0.06, 16,
                              0, 0, 0, order, metrics, 2) == 1);
  assert(order[0] == 0);
  assert(order[1] == 2);
  assert(order[2] == 1);
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
  features[0 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_TAIL_BPM_CONFIDENCE] = 0.95;
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

static void test_planner_uses_edge_local_intro_tempo(void) {
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

  // Track 0 exits at 128 BPM. Track 1's whole-window BPM is 160, but its
  // measured intro is 128; track 2 has a misleadingly matching whole-song BPM
  // of 128 while its intro tempo is 170. The edge analysis must pick track 1.
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_BPM] = 100.0;
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_TAIL_BPM] = 128.0;
  features[0 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_TAIL_BPM_CONFIDENCE] = 0.95;

  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_BPM] = 160.0;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_START_BPM] = 128.0;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_START_BPM_CONFIDENCE] = 0.95;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_BPM] = 128.0;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_START_BPM] = 170.0;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT +
           NAR_AUTOMIX_START_BPM_CONFIDENCE] = 0.95;

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

static void test_planner_prefers_continuing_momentum(void) {
  // Track 0 exits while still building (+12 dB/quarter). Track 1 keeps
  // building (+12), track 2 falls hard (-12) and has the smaller song id, so
  // without the momentum term the id tie-break would pick track 2. The term
  // must instead hand over into track 1.
  const int64_t ids[] = {1, 3, 2};
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
  features[0 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_OUTRO_SLOPE] = 12.0;
  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_INTRO_SLOPE] = 12.0;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_INTRO_SLOPE] = -12.0;

  int32_t order[3];
  double metrics[2];
  assert(nar_automix_plan_set(ids, artists, features, keys, 3, 0, 0.06, 16,
                              0, 0, 0, order, metrics, 2) == 1);
  assert(order[0] == 0);
  assert(order[1] == 1);
  assert(order[2] == 2);
}

static void test_planner_ignores_incomplete_momentum(void) {
  // Same fixture but the outgoing tail slope is missing: the momentum term
  // must stay neutral and the id tie-break picks the smaller song id again.
  const int64_t ids[] = {1, 3, 2};
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
  features[1 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_INTRO_SLOPE] = 12.0;
  features[2 * NAR_AUTOMIX_FEATURE_COUNT + NAR_AUTOMIX_INTRO_SLOPE] = -12.0;

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
  // The seam-aware candidate pool changes the frozen fixture's greedy start;
  // the relocation and reversal scans still have to reach a plan below this
  // bound (the pre-#2 fixture scored 0.2661114).
  assert(metrics[1] < 0.2725);
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

static void test_chord_hangover_bridges_one_gap_and_not_trailing_silence(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 8;
  float* pcm = (float*)calloc((size_t)count, sizeof(float));
  assert(pcm != NULL);
  const double pi = 3.14159265358979323846;
  // C-major triad, two silent seconds, then the same triad. The row centred on
  // the gap cannot be named, so the hangover must bridge exactly that row with
  // a decayed copy of the previous chord: a 0.00 hole in the harmonic timeline
  // is what made a preceding chord look current at the change point where
  // transition cues sample.
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    if (t >= 3.0 && t < 5.0) continue;
    pcm[i] = (float)(
        0.24 * sin(2.0 * pi * 261.6256 * t) +
        0.20 * sin(2.0 * pi * 329.6276 * t) +
        0.18 * sin(2.0 * pi * 391.9954 * t));
  }
  double chords[32] = {0};
  const int32_t rows = nar_automix_analyze_chords(
      pcm, count, sample_rate, chords, 32);
  assert(rows == 7);
  // Row 3 starts at 3000 ms and its 2 s window lies inside the gap.
  assert((int32_t)llround(chords[3 * 4]) == 3000);
  assert(chords[3 * 4 + 1] == 0.0);   // inherits C
  assert(chords[3 * 4 + 2] == 0.0);   // with its quality
  assert(chords[3 * 4 + 3] > 0.0 && chords[3 * 4 + 3] < 0.5);
  assert(chords[3 * 4 + 3] < chords[2 * 4 + 3]);

  // Trailing silence is not a change, so it must stay unknown instead of
  // inheriting the last chord indefinitely.
  for (int32_t i = sample_rate * 5; i < count; ++i) pcm[i] = 0.0f;
  const int32_t trailed = nar_automix_analyze_chords(
      pcm, count, sample_rate, chords, 32);
  assert(trailed == 7);
  assert(chords[5 * 4 + 1] == -1.0 && chords[5 * 4 + 3] == 0.0);
  assert(chords[6 * 4 + 1] == -1.0 && chords[6 * 4 + 3] == 0.0);
  free(pcm);
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

static void test_analyzer_energy_quarters(void) {
  // 8 s tone: the first half at 0.5 amplitude, the second at 0.05. The four
  // quarter medians must follow that step instead of reporting a flat profile.
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 8;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  const double pi = 3.14159265358979323846;
  for (int32_t i = 0; i < count; ++i) {
    const double amplitude = i < count / 2 ? 0.5 : 0.05;
    pcm[i] = (float)(amplitude * sin(2.0 * pi * 220.0 * (double)i / sample_rate));
  }
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(isfinite(output[24]) && isfinite(output[25]) &&
         isfinite(output[26]) && isfinite(output[27]));
  // 0.5 amplitude ≈ -9 dBFS; 0.05 ≈ -29 dBFS.
  assert(output[24] > -12.0 && output[24] < -6.0);
  assert(output[25] > -12.0 && output[25] < -6.0);
  assert(output[26] > -32.0 && output[26] < -26.0);
  assert(output[27] > -32.0 && output[27] < -26.0);
  // The loud half must dominate its quiet counterpart by a clear margin.
  assert(output[24] > output[26] + 14.0);
  assert(output[25] > output[27] + 14.0);
  free(pcm);
}

static void test_analyzer_tempo_curve(void) {
  // Short percussive clicks give the ODF a clean autocorrelation peak.
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 32;
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
  assert(output[28] >= 0.35 && output[28] <= 1.0);
  assert(output[29] >= 0.35 && output[29] <= 1.0);
  assert(isfinite(output[30]) && output[30] >= 0.0 &&
         output[30] < 60000.0 / output[21]);
  assert(isfinite(output[31]) && output[31] >= 0.0 &&
         output[31] < 60000.0 / output[22]);

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
  assert(output[28] >= 0.35 && output[28] <= 1.0);
  assert(output[29] >= 0.35 && output[29] <= 1.0);
  assert(isfinite(output[30]) && output[30] >= 0.0 &&
         output[30] < 60000.0 / output[21]);
  assert(isfinite(output[31]) && output[31] >= 0.0 &&
         output[31] < 60000.0 / output[22]);
  free(pcm);
}

static void render_click_train(float* pcm, int32_t count, int32_t sample_rate,
                               double bpm, double offset_ms) {
  const double pi = 3.14159265358979323846;
  const double period_samples = sample_rate * 60.0 / bpm;
  const double offset_samples = offset_ms * sample_rate / 1000.0;
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    double value = 0.05 * sin(2.0 * pi * 220.0 * t);
    double since = fmod((double)i - offset_samples, period_samples);
    if (since < 0.0) since += period_samples;
    if (since < 32.0) {
      value += 0.4 * (1.0 - since / 32.0) * sin(2.0 * pi * 900.0 * t);
    }
    pcm[i] = (float)value;
  }
}

// Accented click train used by the phrase-phase regression. Every
// `accent_every_beats` beat is loud; the interleaved beat is weak. A kick-like
// sine body plus a short broadband click gives the ODF a clear transient at
// each beat without requiring a real recording.
static void render_accented_click_train(
    float* pcm, int32_t count, int32_t sample_rate, double bpm,
    double offset_ms, int32_t accent_every_beats) {
  const double pi = 3.14159265358979323846;
  const double period_samples = sample_rate * 60.0 / bpm;
  const double offset_samples = offset_ms * sample_rate / 1000.0;
  for (int32_t i = 0; i < count; ++i) {
    pcm[i] = 0.0f;
    const double since = fmod((double)i - offset_samples, period_samples);
    const double distance = since < 0.0 ? since + period_samples : since;
    const double beat_index =
        floor(((double)i - offset_samples - distance) / period_samples + 0.5);
    const int32_t beat = (int32_t)llround(beat_index);
    const int64_t normalized_beat =
        ((int64_t)beat % (int64_t)accent_every_beats + accent_every_beats) %
        accent_every_beats;
    const double amplitude = normalized_beat == 0 ? 0.85 : 0.32;
    const double t = (double)i / sample_rate;
    const double len = sample_rate * 0.08;
    if (distance < len) {
      pcm[i] = (float)(amplitude *
          exp(-distance / (sample_rate * 0.02)) *
          sin(2.0 * pi * 62.0 * t));
    }
    if (distance < 24.0) {
      pcm[i] += (float)(0.5 * amplitude * (1.0 - distance / 24.0));
    }
  }
}

static double circular_phase_error_ms(double measured, double expected,
                                      double period) {
  if (!isfinite(measured) || !isfinite(period) || period <= 0.0) return INFINITY;
  double delta = fmod(fabs(measured - expected), period);
  if (delta > period * 0.5) delta = period - delta;
  return delta;
}

// Regression: the spectral-flux frame timestamp is the frame centre plus half
// a hop, not the frame start. Before the fix every published beat phase was
// 60-90 ms early (2.5+ hops) and the error grew at lower sample rates.
static void test_analyzer_beat_phase_timestamp(void) {
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  const int32_t rates[] = {16000, 22050, 24000, 44100, 48000};
  const double bpms[] = {120.0, 128.0};
  for (size_t r = 0; r < sizeof(rates) / sizeof(rates[0]); ++r) {
    const int32_t sample_rate = rates[r];
    const int32_t count = sample_rate * 32;
    float* pcm = (float*)malloc((size_t)count * sizeof(float));
    assert(pcm != NULL);
    for (size_t b = 0; b < sizeof(bpms) / sizeof(bpms[0]); ++b) {
      const double bpm = bpms[b];
      const double expected_ms = 137.0;
      render_click_train(pcm, count, sample_rate, bpm, expected_ms);
      assert(nar_automix_analyze(pcm, count, sample_rate, output,
                                 NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
      assert(fabs(output[0] - bpm) < 0.5);
      assert(isfinite(output[3]));
      const double period_ms = 60000.0 / output[0];
      const double error =
          circular_phase_error_ms(output[3], expected_ms, period_ms);
      // 12 ms is half an FFT hop at 22.05 kHz. The old frame-start timestamp
      // was off by 60-90 ms.
      assert(error < 12.0);
    }
    free(pcm);
  }
}

// Regression: the 16-beat phrase grid is evaluated on the fractional beat
// period. Rounding the period to whole FFT hops stretched a 120 BPM four-bar
// loop from 8.00 s to 8.17 s, which either hid a real phrase accent or
// invented a phase from window-edge truncation.
static void test_analyzer_phrase_phase_fractional_grid(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 48;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  const double bpms[] = {90.0, 120.0, 127.3, 128.0, 140.0};
  for (size_t i = 0; i < sizeof(bpms) / sizeof(bpms[0]); ++i) {
    const double bpm = bpms[i];
    const double expected_ms = 137.0;
    render_accented_click_train(pcm, count, sample_rate, bpm, expected_ms, 16);
    assert(nar_automix_analyze(pcm, count, sample_rate, output,
                               NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
    assert(isfinite(output[0]));
    assert(isfinite(output[11]));
    const double phrase_ms = 60000.0 / output[0] * 16.0;
    const double error =
        circular_phase_error_ms(output[11], expected_ms, phrase_ms);
    assert(error < 25.0);
  }

  // Every bar identical: all four bar positions carry the same accent, so the
  // phrase start is genuinely ambiguous and must stay unknown. The old grid
  // published a spurious phase for 140 BPM (1764.7 ms) purely from drift.
  for (size_t i = 0; i < sizeof(bpms) / sizeof(bpms[0]); ++i) {
    render_accented_click_train(pcm, count, sample_rate, bpms[i], 137.0, 4);
    assert(nar_automix_analyze(pcm, count, sample_rate, output,
                               NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
    assert(isnan(output[11]));
  }
  free(pcm);
}

static void test_analyzer_tempo_subframe(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 32;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  const double bpms[] = {120.0, 128.0};
  for (size_t i = 0; i < sizeof(bpms) / sizeof(bpms[0]); ++i) {
    render_click_train(pcm, count, sample_rate, bpms[i], 0.0);
    assert(nar_automix_analyze(pcm, count, sample_rate, output,
                               NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
    assert(fabs(output[0] - bpms[i]) < 0.5);
    assert(fabs(output[21] - bpms[i]) < 0.75);
    assert(fabs(output[22] - bpms[i]) < 0.75);
    assert_analysis_confidence_contract(output);
  }

  render_click_train(pcm, count, sample_rate, 120.0, 0.0);
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  const double phase_zero = output[3];
  render_click_train(pcm, count, sample_rate, 120.0, 100.0);
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  const double phase_shifted = output[3];
  assert(isfinite(phase_zero));
  assert(isfinite(phase_shifted));
  const double beat_ms = 60000.0 / output[0];
  double phase_delta = fabs(phase_zero - phase_shifted);
  phase_delta = fmod(phase_delta, beat_ms);
  if (phase_delta > beat_ms * 0.5) phase_delta = beat_ms - phase_delta;
  assert(fabs(phase_delta - 100.0) < 15.0);
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

  // Outgoing trim is ramped in over the first quarter of the fade instead of
  // stepping down at t=0. This mirrors AutomixGainEnvelope.kt; before the
  // fix the native path applied the full trim immediately, so enabling the
  // native fade would have produced an audible step the Kotlin path did not.
  assert(nar_automix_tone_compute_fade_gains(
             0.0f, 1.0f, 0.4f, 0.4f, &outgoing, &incoming) == 1);
  assert(fabsf(outgoing - 1.0f) < 1e-6f);
  assert(fabsf(incoming) < 1e-6f);
  assert(nar_automix_tone_compute_fade_gains(
             0.1f, 1.0f, 0.4f, 0.4f, &outgoing, &incoming) == 1);
  {
    // attack = 0.1 / 0.25 = 0.4 → trim_now = 1 - 0.6*0.4 = 0.76.
    const float theta = 0.1f * (3.14159265358979323846f * 0.5f);
    assert(fabsf(outgoing - 0.76f * cosf(theta)) < 1e-5f);
    assert(fabsf(incoming - 0.4f * sinf(theta)) < 1e-5f);
  }
  // By the end of the attack window the trim is fully applied and the pair
  // obeys the shared L1 headroom budget.
  assert(nar_automix_tone_compute_fade_gains(
             0.25f, 1.0f, 0.4f, 0.4f, &outgoing, &incoming) == 1);
  assert(outgoing + incoming <= 1.0f + 1e-6f);
  assert(outgoing > 0.0f && incoming > 0.0f);

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

// Mirrors the native 4x Lagrange estimator: history[0] is the current sample.
static double true_peak_4x(const float* samples, int32_t frames,
                           int32_t channels) {
  static const float kCoeffs[3][4] = {
      {0.6015625f, 0.6015625f, -0.2578125f, 0.0546875f},
      {0.3125f, 0.9375f, -0.3125f, 0.0625f},
      {0.1171875f, 1.0546875f, -0.2109375f, 0.0390625f},
  };
  double peak = 0.0;
  for (int32_t channel = 0; channel < channels; ++channel) {
    for (int32_t i = 0; i < frames; ++i) {
      const float h0 = samples[(size_t)i * (size_t)channels + (size_t)channel];
      const float h1 = i > 0
          ? samples[(size_t)(i - 1) * (size_t)channels + (size_t)channel]
          : h0;
      const float h2 = i > 1
          ? samples[(size_t)(i - 2) * (size_t)channels + (size_t)channel]
          : h1;
      const float h3 = i > 2
          ? samples[(size_t)(i - 3) * (size_t)channels + (size_t)channel]
          : h2;
      const double magnitude = fabs((double)h0);
      if (magnitude > peak) peak = magnitude;
      for (int set = 0; set < 3; ++set) {
        const double interpolated =
            (double)kCoeffs[set][0] * h0 + (double)kCoeffs[set][1] * h1 +
            (double)kCoeffs[set][2] * h2 + (double)kCoeffs[set][3] * h3;
        if (fabs(interpolated) > peak) peak = fabs(interpolated);
      }
    }
  }
  return peak;
}

static void test_true_peak_limiter_is_transparent_by_default(void) {
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_true_peak_limit(0, 0.0f) == 1);
  assert(nar_automix_tone_configure(0, 48000, 2) == 1);

  float pcm[] = {0.75f, -1.0f, 0.5f, -0.25f, 1.0f, -0.6f};
  const float original[] = {0.75f, -1.0f, 0.5f, -0.25f, 1.0f, -0.6f};
  assert(nar_automix_tone_process(pcm, 3, 2, 0) == 1);
  for (size_t i = 0; i < sizeof(pcm) / sizeof(pcm[0]); ++i) {
    assert(fabsf(pcm[i] - original[i]) < 1e-6f);
  }
}

static void test_true_peak_limiter_respects_ceiling(void) {
  const int32_t frames = 48000;
  float pcm[48000];
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, 48000, 1) == 1);
  assert(nar_automix_tone_set_true_peak_limit(0, 0.95f) == 1);
  for (int32_t i = 0; i < frames; ++i) pcm[i] = 1.0f;
  assert(nar_automix_tone_process(pcm, frames, 1, 0) == 1);
  for (int32_t i = 0; i < frames; ++i) {
    assert(pcm[i] <= 0.95f + 1e-5f);
  }
  // The zero-initialized history makes the first frames look like a step, so
  // the causal detector over-estimates briefly. After 10 release time
  // constants (500 ms) the gain has settled back to the ceiling.
  for (int32_t i = 24000; i < frames; ++i) {
    assert(pcm[i] >= 0.95f - 1e-3f);
  }
  assert(nar_automix_tone_set_true_peak_limit(0, 0.0f) == 1);
}

static void test_true_peak_limiter_disable_releases_smoothly(void) {
  const int32_t frames = 48000;
  float pcm[48000];
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, 48000, 1) == 1);
  assert(nar_automix_tone_set_true_peak_limit(0, 0.95f) == 1);
  for (int32_t i = 0; i < frames; ++i) pcm[i] = 1.0f;
  assert(nar_automix_tone_process(pcm, frames, 1, 0) == 1);
  const float before_disable = pcm[frames - 1];
  assert(before_disable >= 0.949f && before_disable <= 0.951f);

  // Disabling must not jump from the clamp to the dry signal in one sample;
  // that step is the end-of-AutoMix click. The ceiling ramps to 1.0 while the
  // release gain settles, so every adjacent sample stays continuous.
  assert(nar_automix_tone_set_true_peak_limit(0, 0.0f) == 1);
  for (int32_t i = 0; i < frames; ++i) pcm[i] = 1.0f;
  // Drive the release in small blocks so the test covers audio-thread buffer
  // boundaries, not just a single giant callback.
  for (int32_t offset = 0; offset < frames; offset += 64) {
    const int32_t count = (offset + 64 <= frames) ? 64 : frames - offset;
    assert(nar_automix_tone_process(pcm + offset, count, 1, 0) == 1);
  }
  const float first_step = fabsf(pcm[0] - before_disable);
  assert(first_step < 0.001f);
  for (int32_t i = 1; i < frames; ++i) {
    assert(fabsf(pcm[i] - pcm[i - 1]) < 0.005f);
  }
  for (int32_t i = frames - 100; i < frames; ++i) {
    assert(fabsf(pcm[i] - 1.0f) < 1e-6f);
  }
}

static void test_true_peak_limiter_catches_intersample_peaks(void) {
  const int32_t frames = 9600;
  float pcm[9600];
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, 48000, 1) == 1);
  // Fs/4 with a 45-degree phase: samples are +-0.7071 but the analog peak is
  // 1.0, so a sample-peak limiter alone would not engage.
  for (int32_t i = 0; i < frames; ++i) {
    pcm[i] = sinf(3.14159265358979323846f * 0.5f * (float)i +
                  3.14159265358979323846f * 0.25f);
  }
  assert(true_peak_4x(pcm, frames, 1) > 1.05);
  assert(nar_automix_tone_set_true_peak_limit(0, 0.80f) == 1);
  assert(nar_automix_tone_process(pcm, frames, 1, 0) == 1);
  for (int32_t i = 0; i < frames; ++i) {
    assert(fabsf(pcm[i]) <= 0.8001f);
  }
  // Skip the first 512 frames: the causal detector needs a few samples to
  // engage, so the onset transient is not part of the steady-state bound.
  assert(true_peak_4x(pcm + 512, frames - 512, 1) <= 0.805);
  assert(nar_automix_tone_set_true_peak_limit(0, 0.0f) == 1);
}

static void test_true_peak_limiter_is_per_stream(void) {
  const int32_t frames = 480;
  float limited[480];
  float reference[480];
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_bass_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, 48000, 1) == 1);
  assert(nar_automix_tone_configure(1, 48000, 1) == 1);
  assert(nar_automix_tone_set_true_peak_limit(0, 0.60f) == 1);
  assert(nar_automix_tone_set_true_peak_limit(1, 0.0f) == 1);
  for (int32_t i = 0; i < frames; ++i) {
    limited[i] = 1.0f;
    reference[i] = 1.0f;
  }
  assert(nar_automix_tone_process(limited, frames, 1, 0) == 1);
  assert(nar_automix_tone_process(reference, frames, 1, 1) == 1);
  for (int32_t i = 0; i < frames; ++i) {
    assert(limited[i] <= 0.6001f);
    assert(fabsf(reference[i] - 1.0f) < 1e-6f);
  }
  assert(nar_automix_tone_set_true_peak_limit(0, 0.0f) == 1);
}

static void test_true_peak_limiter_reset_preserves_target(void) {
  const int32_t frames = 480;
  float loud[480];
  float quiet[480];
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, 48000, 1) == 1);
  assert(nar_automix_tone_set_true_peak_limit(0, 0.50f) == 1);
  for (int32_t i = 0; i < frames; ++i) loud[i] = 1.0f;
  assert(nar_automix_tone_process(loud, frames, 1, 0) == 1);
  assert(loud[frames - 1] <= 0.5001f);

  assert(nar_automix_tone_reset(0) == 1);
  for (int32_t i = 0; i < frames; ++i) quiet[i] = 0.1f;
  assert(nar_automix_tone_process(quiet, frames, 1, 0) == 1);
  for (int32_t i = 0; i < frames; ++i) {
    assert(fabsf(quiet[i] - 0.1f) < 1e-6f);
  }

  // The atomic target survives reset, so a loud block is limited again.
  for (int32_t i = 0; i < frames; ++i) loud[i] = 1.0f;
  assert(nar_automix_tone_process(loud, frames, 1, 0) == 1);
  assert(loud[frames - 1] <= 0.5001f);
  assert(nar_automix_tone_set_true_peak_limit(0, 0.0f) == 1);
}

static void test_true_peak_limiter_block_boundaries_are_continuous(void) {
  const int32_t frames = 1024;
  float whole[1024];
  float chunked[1024];
  const int32_t chunk = 7;
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_bass_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, 48000, 1) == 1);
  assert(nar_automix_tone_configure(1, 48000, 1) == 1);
  assert(nar_automix_tone_set_true_peak_limit(0, 0.80f) == 1);
  assert(nar_automix_tone_set_true_peak_limit(1, 0.80f) == 1);
  for (int32_t i = 0; i < frames; ++i) {
    const float sample = 0.98f * sinf(
        2.0f * 3.14159265358979323846f * 12000.0f * (float)i / 48000.0f);
    whole[i] = sample;
    chunked[i] = sample;
  }
  assert(nar_automix_tone_process(whole, frames, 1, 0) == 1);
  for (int32_t offset = 0; offset < frames; offset += chunk) {
    const int32_t count = (offset + chunk <= frames) ? chunk : frames - offset;
    assert(nar_automix_tone_process(chunked + offset, count, 1, 1) == 1);
  }
  for (int32_t i = 0; i < frames; ++i) {
    assert(fabsf(whole[i] - chunked[i]) < 1e-6f);
  }
  assert(nar_automix_tone_set_true_peak_limit(0, 0.0f) == 1);
  assert(nar_automix_tone_set_true_peak_limit(1, 0.0f) == 1);
}

static void test_true_peak_limiter_rejects_invalid_input(void) {
  assert(nar_automix_tone_set_true_peak_limit(-1, 0.9f) == 0);
  assert(nar_automix_tone_set_true_peak_limit(2, 0.9f) == 0);

  float pcm[8];
  assert(nar_automix_tone_set_bass_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_mid_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_set_fade_gain(0, 1.0f) == 1);
  assert(nar_automix_tone_configure(0, 48000, 1) == 1);

  // NaN and negative ceilings disable the limiter instead of silently
  // clamping to full scale.
  assert(nar_automix_tone_set_true_peak_limit(0, NAN) == 1);
  for (int i = 0; i < 8; ++i) pcm[i] = 1.0f;
  assert(nar_automix_tone_process(pcm, 8, 1, 0) == 1);
  for (int i = 0; i < 8; ++i) assert(fabsf(pcm[i] - 1.0f) < 1e-6f);

  assert(nar_automix_tone_set_true_peak_limit(0, -0.5f) == 1);
  for (int i = 0; i < 8; ++i) pcm[i] = 1.0f;
  assert(nar_automix_tone_process(pcm, 8, 1, 0) == 1);
  for (int i = 0; i < 8; ++i) assert(fabsf(pcm[i] - 1.0f) < 1e-6f);

  // A ceiling above 1 clamps to 1. A 0.5 signal stays well below both the
  // clamp and the interpolator's step overshoot, so it must pass untouched.
  assert(nar_automix_tone_set_true_peak_limit(0, 2.0f) == 1);
  for (int i = 0; i < 8; ++i) pcm[i] = 0.5f;
  assert(nar_automix_tone_process(pcm, 8, 1, 0) == 1);
  for (int i = 0; i < 8; ++i) assert(fabsf(pcm[i] - 0.5f) < 1e-6f);
  assert(nar_automix_tone_set_true_peak_limit(0, 0.0f) == 1);
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

static void test_live_tracker_ignores_lfe_and_surround_channels(void) {
  // 5.1-ish interleaved layout: L, R, C, LFE, SL, SR. A loud click train in
  // the LFE/center/surround channels must not be mistaken for the musical
  // beat: the tracker only listens to the stereo L/R bed.
  const int32_t sample_rate = 48000;
  const int32_t channels = 6;
  const int32_t chunk_frames = 512;
  const int32_t total_frames = sample_rate * 8;
  float pcm[512 * 6];
  double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};

  assert(nar_automix_live_tracker_set_enabled(1) == 1);
  int32_t produced = 0;
  while (produced < total_frames) {
    const int32_t frames = (total_frames - produced) < chunk_frames
        ? (total_frames - produced)
        : chunk_frames;
    for (int32_t i = 0; i < frames; ++i) {
      const int64_t absolute = (int64_t)produced + i;
      const int64_t phase = absolute % 24000;
      const float click = phase < 48
          ? (float)(0.9 * (1.0 - (double)phase / 48.0))
          : 0.0f;
      const int32_t base = i * channels;
      pcm[base] = 0.0f;
      pcm[base + 1] = 0.0f;
      pcm[base + 2] = click;
      pcm[base + 3] = click;
      pcm[base + 4] = click;
      pcm[base + 5] = click;
    }
    assert(nar_automix_live_tracker_process(
               pcm, frames, channels, sample_rate, 0) == 1);
    produced += frames;
  }
  assert(nar_automix_live_tracker_get(
             0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  assert(state[0] < 1.0);
  assert(state[2] < 0.05);
  assert(nar_automix_live_tracker_set_enabled(0) == 1);
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

typedef struct {
  float* pcm;
  int32_t frames;
  int32_t last_click;
  int32_t last_accent;
  int32_t click_count;
} FractionalClickTrain;

static FractionalClickTrain render_fractional_click_train(
    double bpm, int32_t accent_every, double min_click_seconds,
    double end_offset_seconds, int32_t sample_rate) {
  const double pi = 3.14159265358979323846;
  const double period_samples = 60.0 * sample_rate / bpm;
  const int32_t beats = (int32_t)ceil(min_click_seconds * bpm / 60.0);
  const int32_t frames = (int32_t)llround(
      (double)beats * period_samples + end_offset_seconds * sample_rate);
  FractionalClickTrain train = {0};
  train.pcm = (float*)calloc((size_t)frames * 2u, sizeof(float));
  assert(train.pcm != NULL);
  train.frames = frames;
  train.last_accent = -1;
  double next_click = 0.0;
  int32_t burst_start = -10000;
  int32_t burst_is_accent = 0;
  int32_t click = 0;
  for (int32_t n = 0; n < frames; ++n) {
    if (n == (int32_t)llround(next_click)) {
      burst_start = n;
      burst_is_accent = accent_every > 0 && (click % accent_every) == 0;
      train.last_click = n;
      if (burst_is_accent) train.last_accent = n;
      ++click;
      next_click += period_samples;
    }
    const double t = (double)n / sample_rate;
    double value = 0.01 * sin(2.0 * pi * 300.0 * t);
    const int32_t offset = n - burst_start;
    if (offset >= 0 && offset < 48) {
      const double gain = burst_is_accent ? 0.9 : 0.25;
      const double frequency = burst_is_accent ? 100.0 : 800.0;
      value += gain * (1.0 - (double)offset / 48.0) *
          sin(2.0 * pi * frequency * t);
    }
    train.pcm[n * 2] = (float)value;
    train.pcm[n * 2 + 1] = (float)value;
  }
  train.click_count = click;
  return train;
}

static double click_train_elapsed_ms(
    const FractionalClickTrain* train, int32_t onset_sample,
    int32_t sample_rate) {
  return (double)(train->frames - 1 - onset_sample) * 1000.0 / sample_rate;
}

static void run_live_tracker_click_train(
    const FractionalClickTrain* train, int32_t sample_rate, double* state) {
  const int32_t chunk_frames = 512;
  assert(nar_automix_live_tracker_set_enabled(0) == 1);
  assert(nar_automix_live_tracker_set_enabled(1) == 1);
  int32_t produced = 0;
  while (produced < train->frames) {
    int32_t frames = train->frames - produced;
    if (frames > chunk_frames) frames = chunk_frames;
    assert(nar_automix_live_tracker_process(
               train->pcm + (size_t)produced * 2u, frames, 2, sample_rate,
               0) == 1);
    produced += frames;
  }
  assert(nar_automix_live_tracker_get(
             0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);
  assert(nar_automix_live_tracker_set_enabled(0) == 1);
}

static void test_live_tracker_fractional_phase_accuracy(void) {
  // Fractional-frame periods drift against an integer lag over the 6 s
  // history, so the published phase must be checked at non-integer tempos.
  const int32_t sample_rate = 48000;
  const double bpms[] = {97.5, 110.0, 123.0};
  const double click_seconds[] = {2.5, 7.0};
  for (size_t i = 0; i < sizeof(bpms) / sizeof(bpms[0]); ++i) {
    for (size_t j = 0; j < sizeof(click_seconds) / sizeof(click_seconds[0]);
         ++j) {
      FractionalClickTrain train = render_fractional_click_train(
          bpms[i], 0, click_seconds[j], 0.21, sample_rate);
      double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
      run_live_tracker_click_train(&train, sample_rate, state);
      const double expected =
          click_train_elapsed_ms(&train, train.last_click, sample_rate);
      assert(fabs(state[0] - bpms[i]) <= bpms[i] * 0.02);
      assert(state[2] > 0.2);
      assert(fabs(state[1] - expected) <= 18.0);
      free(train.pcm);
    }
  }
}

static void test_live_tracker_fractional_downbeat_accuracy(void) {
  const int32_t sample_rate = 48000;
  FractionalClickTrain train = render_fractional_click_train(
      123.0, 4, 7.0, 0.21, sample_rate);
  assert(train.last_accent >= 0);
  double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
  run_live_tracker_click_train(&train, sample_rate, state);
  const double expected =
      click_train_elapsed_ms(&train, train.last_accent, sample_rate);
  assert(fabs(state[0] - 123.0) <= 123.0 * 0.02);
  assert(state[2] > 0.2);
  assert(state[3] > 0.0);
  assert(state[4] > 0.25);
  assert(fabs(state[3] - expected) <= 20.0);
  free(train.pcm);
}

static void test_live_tracker_145bpm_accented_downbeat(void) {
  const int32_t sample_rate = 48000;
  const double target_bpm = 145.0;
  const double beat_period_ms = 60000.0 / target_bpm;
  const double bar_period_ms = beat_period_ms * 4.0;

  // Render a 6.0-second 145 BPM audio fixture with accented downbeats every 4 beats.
  // At 145 BPM, nominal beat period at 100 fps is ~41.379 frames (~413.79 ms).
  // At 6.0 s, the fixture's final beat is beat 3 of the bar, placing the true
  // reference downbeat 3 beats back (~1451 ms elapsed).
  FractionalClickTrain train = render_fractional_click_train(
      target_bpm, 4, 6.0, 0.21, sample_rate);
  assert(train.last_accent >= 0);
  double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
  run_live_tracker_click_train(&train, sample_rate, state);

  const double reported_bpm = state[0];
  const double expected_downbeat_ms =
      click_train_elapsed_ms(&train, train.last_accent, sample_rate);
  const double measured_downbeat_ms = state[3];

  // Circular phase error relative to the 4-beat bar period
  double phase_error = fabs(measured_downbeat_ms - expected_downbeat_ms);
  phase_error = fmod(phase_error, bar_period_ms);
  if (phase_error > bar_period_ms * 0.5) {
    phase_error = bar_period_ms - phase_error;
  }

  // Verify BPM independently within 2% error
  assert(fabs(reported_bpm - target_bpm) <= target_bpm * 0.02);
  assert(state[2] > 0.2);

  // Downbeat phase must match expected within 25 ms tolerance.
  // The unmodified 145 BPM code reports a downbeat 1 beat early (~402.7 ms error).
  assert(phase_error <= 25.0);
  assert(state[4] > 0.20);

  free(train.pcm);
}

static void test_live_tracker_resolves_half_tempo_lock(void) {
  // Sparse 145 BPM clicks make the two-beat autocorrelation lag score higher
  // than the one-beat lag at startup. With no prior estimate there is nothing
  // to fold the 72.4 BPM reading back up, so the tracker must resolve the
  // octave from the observed onset spacing instead of publishing half-tempo.
  const int32_t sample_rate = 48000;
  FractionalClickTrain train = render_fractional_click_train(
      145.0, 0, 7.0, 0.21, sample_rate);
  double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
  run_live_tracker_click_train(&train, sample_rate, state);
  assert(fabs(state[0] - 145.0) <= 145.0 * 0.02);
  assert(state[2] > 0.2);
  free(train.pcm);
}

static void test_live_tracker_resolves_third_and_double_tempo(void) {
  // A pulse train is equally periodic at 2x and 3x its beat, and the old
  // one-directional rescue only ever doubled a reading that was too slow, so a
  // 3:1 lock (180 BPM published as 60 at confidence 1.000) was unrecoverable.
  // The symmetric metrical hypothesis test must return the beat level in both
  // directions: 90/160 were published too slow and 135/174/180 too fast.
  const int32_t sample_rate = 48000;
  const double bpms[] = {90.0, 135.0, 160.0, 174.0, 180.0};
  for (size_t i = 0; i < sizeof(bpms) / sizeof(bpms[0]); ++i) {
    FractionalClickTrain train = render_fractional_click_train(
        bpms[i], 0, 7.0, 0.21, sample_rate);
    double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
    run_live_tracker_click_train(&train, sample_rate, state);
    assert(fabs(state[0] - bpms[i]) <= bpms[i] * 0.02);
    assert(state[2] > 0.2);
    free(train.pcm);
  }
}

static void test_live_tracker_reports_meter_and_rejects_flat_bars(void) {
  // Flat four-on-the-floor has no bar accent at all; the tracker must publish
  // no metre and no downbeat rather than invent one from frame-grid aliasing.
  const int32_t sample_rate = 48000;
  FractionalClickTrain flat = render_fractional_click_train(
      120.0, 0, 8.0, 0.21, sample_rate);
  double flat_state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
  run_live_tracker_click_train(&flat, sample_rate, flat_state);
  assert(flat_state[6] == 0.0);
  assert(flat_state[4] < 0.30);
  free(flat.pcm);

  // A three-beat accent pattern (waltz) must be identified as metre 3. The old
  // bar scan was hard-wired to four beats and could never represent it, so the
  // published downbeat drifted by one beat every bar.
  FractionalClickTrain waltz = render_fractional_click_train(
      120.0, 3, 8.0, 0.21, sample_rate);
  double waltz_state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
  run_live_tracker_click_train(&waltz, sample_rate, waltz_state);
  assert(fabs(waltz_state[0] - 120.0) <= 120.0 * 0.02);
  assert(waltz_state[6] == 3.0);
  assert(waltz_state[4] >= 0.30);
  free(waltz.pcm);
}

static void test_live_tracker_keeps_low_tempo(void) {
  // The same octave check must not promote genuine 70-75 BPM pulse trains:
  // their onsets are spaced at the full beat period, not half of it.
  const int32_t sample_rate = 48000;
  const double bpms[] = {70.0, 72.0, 75.0};
  for (size_t i = 0; i < sizeof(bpms) / sizeof(bpms[0]); ++i) {
    FractionalClickTrain train = render_fractional_click_train(
        bpms[i], 0, 7.0, 0.21, sample_rate);
    double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
    run_live_tracker_click_train(&train, sample_rate, state);
    assert(fabs(state[0] - bpms[i]) <= bpms[i] * 0.02);
    assert(state[2] > 0.2);
    free(train.pcm);
  }
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

static double phase_circular_distance_ms(double actual, double expected,
                                           double period_ms) {
  if (!isfinite(actual) || !isfinite(expected) ||
      !isfinite(period_ms) || period_ms <= 0.0) {
    return INFINITY;
  }
  double distance = fmod(fabs(actual - expected), period_ms);
  return fmin(distance, period_ms - distance);
}

static void test_live_tracker_phase_stays_coherent_during_tempo_change(void) {
  // Begin with a stable 150 BPM / 4-beat bar, then slow to 100 BPM exactly
  // on a downbeat. The six-second analysis window necessarily contains both
  // grids during the change, so phase accuracy is asserted on each stable
  // side of the transition instead of against a single impossible mixed grid.
  // During the mixed-history period, the published tuple must remain finite
  // and internally bounded while the tracker reacquires the slower pulse.
  const double pi = 3.14159265358979323846;
  const int32_t sample_rate = 48000;
  const int32_t chunk_frames = 512;
  const int64_t transition_frame = (int64_t)sample_rate * 8;  // 20 beats at 150 BPM.
  // Wait 9 s after the switch so both the 6 s history and the smoothed BPM
  // estimate have settled on the new pulse grid before measuring its phase.
  const int64_t total_frames = transition_frame + (int64_t)(sample_rate * 9.0);
  const int64_t fast_period_frames = sample_rate * 2 / 5;  // 150 BPM.
  const int64_t slow_period_frames = (int64_t)sample_rate * 3 / 5;  // 100 BPM.
  float pcm[512 * 2];
  double state[NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT] = {0};
  double max_fast_beat_error_ms = 0.0;
  double max_fast_downbeat_error_ms = 0.0;
  double max_slow_beat_error_ms = 0.0;
  double max_slow_downbeat_error_ms = 0.0;
  int32_t checked_fast_phases = 0;
  int32_t checked_fast_downbeat_phases = 0;
  int32_t checked_slow_phases = 0;
  int32_t checked_slow_downbeat_phases = 0;
  int32_t checked_transition_states = 0;
  int64_t produced = 0;

  assert(nar_automix_live_tracker_set_enabled(1) == 1);
  while (produced < total_frames) {
    const int32_t frames = (total_frames - produced) < chunk_frames
        ? (int32_t)(total_frames - produced)
        : chunk_frames;
    for (int32_t i = 0; i < frames; ++i) {
      const int64_t n = produced + i;
      const int after_transition = n >= transition_frame;
      const int64_t local_frame =
          after_transition ? n - transition_frame : n;
      const int64_t period_frames =
          after_transition ? slow_period_frames : fast_period_frames;
      const int64_t beat_index =
          after_transition
              ? 24 + local_frame / period_frames
              : local_frame / period_frames;
      const int64_t beat_phase = local_frame % period_frames;
      const double t = (double)n / sample_rate;
      double value = 0.01 * sin(2.0 * pi * 300.0 * t);
      if (beat_phase < 48) {
        value += 0.25 * (1.0 - (double)beat_phase / 48.0) *
            sin(2.0 * pi * 800.0 * t);
        if (beat_index % 4 == 0) {
          value += 0.9 * (1.0 - (double)beat_phase / 48.0) *
              sin(2.0 * pi * 100.0 * t);
        }
      }
      pcm[i * 2] = (float)value;
      pcm[i * 2 + 1] = (float)value;
    }

    assert(nar_automix_live_tracker_process(
               pcm, frames, 2, sample_rate, 0) == 1);
    produced += frames;
    assert(nar_automix_live_tracker_get(
               0, state, NAR_AUTOMIX_LIVE_TRACKER_STATE_COUNT) == 1);

    const int64_t last_sample = produced - 1;
    const int after_transition = last_sample >= transition_frame;
    const int64_t phase_origin = after_transition ? transition_frame : 0;
    const int64_t relative_sample = last_sample - phase_origin;
    const int64_t actual_period_frames =
        after_transition ? slow_period_frames : fast_period_frames;
    const double actual_beat_period_ms =
        (double)actual_period_frames * 1000.0 / sample_rate;
    const double actual_bar_period_ms = actual_beat_period_ms * 4.0;
    const int64_t last_beat_frame =
        phase_origin +
        (relative_sample / actual_period_frames) * actual_period_frames;
    const int64_t last_downbeat_frame =
        phase_origin +
        (relative_sample / (actual_period_frames * 4)) *
            (actual_period_frames * 4);
    const double expected_beat_age_ms =
        (double)(last_sample - last_beat_frame) * 1000.0 / sample_rate;
    const double expected_downbeat_age_ms =
        (double)(last_sample - last_downbeat_frame) * 1000.0 / sample_rate;

    // During the mixed-history period, the estimate is allowed to move
    // between tempos, but published phase values must remain finite and stay
    // inside the period implied by the same published BPM tuple.
    const int in_transition_window =
        last_sample >= transition_frame &&
        last_sample < transition_frame + sample_rate * 6;
    if (in_transition_window && state[0] >= 60.0 && state[0] <= 200.0 &&
        state[2] > 0.15) {
      const double estimated_period_ms = 60000.0 / state[0];
      assert(isfinite(state[1]) && state[1] >= 0.0 &&
             state[1] < estimated_period_ms);
      assert(isfinite(state[3]) && state[3] >= 0.0 &&
             state[3] < estimated_period_ms * 4.0);
      assert(isfinite(state[2]) && state[2] <= 1.0);
      checked_transition_states++;
    }

    // Measure phase accuracy only when the input has held a single tempo long
    // enough for the entire 6 s history window to contain that tempo.
    const int in_fast_steady_window =
        last_sample >= transition_frame - sample_rate &&
        last_sample < transition_frame;
    const int in_slow_steady_window =
        last_sample >= transition_frame + (int64_t)(sample_rate * 8.0);
    if (in_fast_steady_window &&
        fabs(state[0] - 150.0) <= 150.0 * 0.08 &&
        state[2] > 0.15) {
      const double beat_error = phase_circular_distance_ms(
          state[1], expected_beat_age_ms, actual_beat_period_ms);
      if (beat_error > max_fast_beat_error_ms) {
        max_fast_beat_error_ms = beat_error;
      }
      checked_fast_phases++;
      if (state[4] > 0.15) {
        const double downbeat_error = phase_circular_distance_ms(
            state[3], expected_downbeat_age_ms, actual_bar_period_ms);
        if (downbeat_error > max_fast_downbeat_error_ms) {
          max_fast_downbeat_error_ms = downbeat_error;
        }
        checked_fast_downbeat_phases++;
      }
    }
    if (in_slow_steady_window &&
        fabs(state[0] - 100.0) <= 100.0 * 0.02 &&
        state[2] > 0.15) {
      const double beat_error = phase_circular_distance_ms(
          state[1], expected_beat_age_ms, actual_beat_period_ms);
      if (beat_error > max_slow_beat_error_ms) {
        max_slow_beat_error_ms = beat_error;
      }
      checked_slow_phases++;
      if (state[4] > 0.15) {
        const double downbeat_error = phase_circular_distance_ms(
            state[3], expected_downbeat_age_ms, actual_bar_period_ms);
        if (downbeat_error > max_slow_downbeat_error_ms) {
          max_slow_downbeat_error_ms = downbeat_error;
        }
        checked_slow_downbeat_phases++;
      }
    }
  }

  assert(checked_fast_phases >= 40);
  assert(max_fast_beat_error_ms < 25.0);
  assert(checked_fast_downbeat_phases >= 20);
  assert(max_fast_downbeat_error_ms < 40.0);
  assert(checked_transition_states >= 100);
  assert(checked_slow_phases >= 40);
  assert(max_slow_beat_error_ms < 25.0);
  assert(checked_slow_downbeat_phases >= 20);
  assert(max_slow_downbeat_error_ms < 40.0);
  // After a full slow-tempo history window, the estimate must converge toward
  // the new pulse rather than retaining the previous fast tempo.
  assert(state[0] >= 90.0 && state[0] <= 110.0);
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

// Deterministic four-on-the-floor: 52 Hz kick on every beat and a short
// 9 kHz hat on every eighth. This is the pattern that used to force 2x, 1/2x
// and 2/3x metrical errors.
static void render_four_on_floor(float* pcm, int32_t count, int32_t sample_rate,
                                 double bpm) {
  const double pi = 3.14159265358979323846;
  const double beat = 60.0 / bpm;
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    const double phase = fmod(t, beat);
    double value = 0.0;
    if (phase < 0.10) {
      value += 0.8 * exp(-phase * 32.0) * sin(2.0 * pi * 52.0 * phase);
    }
    const double hat_phase = fmod(t, beat * 0.5);
    if (hat_phase < 0.012) {
      value += 0.10 * (1.0 - hat_phase / 0.012) *
          sin(2.0 * pi * 9000.0 * t);
    }
    pcm[i] = (float)value;
  }
}

static void render_four_on_floor_backbeat(float* pcm, int32_t count,
                                          int32_t sample_rate, double bpm) {
  // Standard house pattern: kick on every beat, snare (noise) on 2 and 4,
  // closed hat on the off-beat. This is the arrangement that used to make the
  // offline analyzer publish the bar-level pulse (60 BPM) instead of the beat.
  const double pi = 3.14159265358979323846;
  const double beat = 60.0 / bpm;
  unsigned int seed = 0x7F4A7C15u;
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    const double phase = fmod(t, beat);
    double value = 0.0;
    if (phase < 0.10) {
      value += 0.8 * exp(-phase * 32.0) * sin(2.0 * pi * 52.0 * phase);
    }
    const double hat_phase = fmod(t, beat * 0.5);
    if (hat_phase < 0.012) {
      value += 0.10 * (1.0 - hat_phase / 0.012) *
          sin(2.0 * pi * 9000.0 * t);
    }
    const int64_t beat_index = (int64_t)floor(t / beat);
    if ((beat_index % 4 == 1 || beat_index % 4 == 3) && phase < 0.18) {
      seed = seed * 1664525u + 1013904223u;
      const double noise = ((double)(seed >> 9) / 8388608.0) - 1.0;
      value += 0.35 * noise * exp(-phase * 18.0);
    }
    pcm[i] = (float)value;
  }
}

static void test_analyzer_backbeat_keeps_beat_level(void) {
  // Regression from the ffmpeg real-audio pass: a 120 BPM four-on-the-floor
  // with a snare backbeat was published as 60.00 BPM at confidence 0.87. The
  // grid arbitration must keep the beat and push the bar level to the
  // runner-up slot, otherwise tempo matching halves a standard house track.
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 40;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  render_four_on_floor_backbeat(pcm, count, sample_rate, 120.0);
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(fabs(output[0] / 120.0 - 1.0) < 0.02);
  assert(isfinite(output[2]));
  assert(fabs(output[2] / 60.0 - 1.0) < 0.04);
  free(pcm);
}

static void test_analyzer_sparse_intro_keeps_chorus_tempo(void) {
  // Regression from the ffmpeg real-audio pass: 32 s of off-beat hats and a
  // soft pad followed by 32 s of full 120 BPM four-on-the-floor published
  // 60.00 BPM for the whole window (and for the end quarter), even though the
  // first quarter already measured 120. The quarter-vote rescue must publish
  // the level all four local windows agree on.
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 64;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  const double pi = 3.14159265358979323846;
  const double beat = 0.5;  // 120 BPM
  unsigned int seed = 0x2545F491u;
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    const int chorus = t >= 32.0;
    double value = 0.05 * (sin(2.0 * pi * 261.6256 * t) +
                           sin(2.0 * pi * 329.6276 * t) +
                           sin(2.0 * pi * 391.9954 * t));
    const double hat_phase = fmod(t, beat * 0.5);
    if (hat_phase < 0.012) {
      value += (chorus ? 0.12 : 0.08) * (1.0 - hat_phase / 0.012) *
          sin(2.0 * pi * 9000.0 * t);
    }
    if (chorus) {
      const double phase = fmod(t, beat);
      if (phase < 0.10) {
        value += 0.7 * exp(-phase * 32.0) * sin(2.0 * pi * 52.0 * phase);
      }
      const int64_t beat_index = (int64_t)floor(t / beat);
      if ((beat_index % 4 == 1 || beat_index % 4 == 3) && phase < 0.18) {
        seed = seed * 1664525u + 1013904223u;
        const double noise = ((double)(seed >> 9) / 8388608.0) - 1.0;
        value += 0.28 * noise * exp(-phase * 18.0);
      }
    }
    pcm[i] = (float)value;
  }
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(fabs(output[0] / 120.0 - 1.0) < 0.02);
  assert(fabs(output[21] / 120.0 - 1.0) < 0.03);
  assert(fabs(output[22] / 120.0 - 1.0) < 0.03);
  free(pcm);
}

static void test_analyzer_metrical_level_sweep(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 40;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  const double bpms[] = {60.0, 64.0, 70.0, 80.0, 90.0, 110.0, 125.0,
                         128.0, 145.0, 160.0, 170.0, 174.0, 180.0,
                         190.0, 200.0};
  for (size_t i = 0; i < sizeof(bpms) / sizeof(bpms[0]); ++i) {
    render_four_on_floor(pcm, count, sample_rate, bpms[i]);
    assert(nar_automix_analyze(pcm, count, sample_rate, output,
                               NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
    assert(isfinite(output[0]));
    // The detector must publish the beat, not a half/double/2:3 multiple of
    // it. The runner-up is still published for downstream octave recovery.
    assert(fabs(output[0] / bpms[i] - 1.0) < 0.02);
    assert(output[1] >= 0.30);
  }
  free(pcm);
}

static void test_analyzer_beat_phase_survives_offbeat_hats(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 40;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  const double expected_ms = 137.0;
  const double bpms[] = {90.0, 100.0, 110.0, 120.0, 128.0, 140.0};
  for (size_t i = 0; i < sizeof(bpms) / sizeof(bpms[0]); ++i) {
    const double beat = 60.0 / bpms[i];
    const double pi = 3.14159265358979323846;
    for (int32_t n = 0; n < count; ++n) {
      const double t = (double)n / sample_rate;
      const double since = fmod(t - expected_ms / 1000.0, beat);
      const double phase = since < 0.0 ? since + beat : since;
      double value = 0.0;
      if (phase < 0.09) {
        value += 0.8 * exp(-phase * 35.0) * sin(2.0 * pi * 55.0 * phase);
      }
      const double hat_phase = fmod(t, beat * 0.5);
      if (hat_phase < 0.012) {
        value += 0.10 * (1.0 - hat_phase / 0.012) *
            sin(2.0 * pi * 9000.0 * t);
      }
      pcm[n] = (float)value;
    }
    assert(nar_automix_analyze(pcm, count, sample_rate, output,
                               NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
    assert(isfinite(output[3]));
    const double period_ms = 60000.0 / output[0];
    double error = fmod(fabs(output[3] - expected_ms), period_ms);
    if (error > period_ms * 0.5) error = period_ms - error;
    assert(error < 15.0);
  }
  free(pcm);
}

static void test_analyzer_key_rejects_noise_and_survives_detune(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 6;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  unsigned int seed = 0x9E3779B9u;
  for (int32_t i = 0; i < count; ++i) {
    seed = seed * 1664525u + 1013904223u;
    pcm[i] = (float)(((double)(seed >> 8) / 16777216.0) * 2.0 - 1.0);
  }
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  // Noise has no key. The old estimator reported one at confidence 0.754.
  assert(output[6] < 0.20);
  assert(output[4] == -1.0);

  const double equal_tones[3] = {0.2, 0.2, 0.2};
  const double detune = 1.02640;  // 2^(45/1200)
  const double c_major_sharp[3] = {261.6256 * detune, 329.6276 * detune,
                                   391.9954 * detune};
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    double value = 0.0;
    for (int tone = 0; tone < 3; ++tone) {
      value += equal_tones[tone] *
          sin(2.0 * 3.14159265358979323846 * c_major_sharp[tone] * t);
    }
    pcm[i] = (float)value;
  }
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(output[4] == 0.0);
  assert(output[5] == 0.0);
  free(pcm);
}

static void test_analyzer_phrase_phase_from_harmonic_change(void) {
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 48;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  const double bpms[] = {90.0, 120.0, 128.0, 140.0};
  const double expected_ms = 137.0;
  const double pi = 3.14159265358979323846;
  for (size_t b = 0; b < sizeof(bpms) / sizeof(bpms[0]); ++b) {
    const double beat = 60.0 / bpms[b];
    const double phrase = beat * 16.0;
    for (int32_t i = 0; i < count; ++i) {
      const double t = (double)i / sample_rate;
      double local = t - expected_ms / 1000.0;
      if (local < 0.0) local += phrase * 4.0;
      const int chord = ((int)floor(local / phrase)) % 2;
      const double root = chord ? 196.0 : 130.8128;
      const double third = chord ? 246.9417 : 164.8138;
      const double fifth = chord ? 293.6648 : 195.9977;
      // Constant RMS: every beat has the same kick, so loudness cannot tell
      // the phrase start. Only the chord change at the boundary can.
      const double beat_phase = fmod(local, beat);
      double value = 0.12 * (sin(2.0 * pi * root * t) +
                             sin(2.0 * pi * third * t) +
                             sin(2.0 * pi * fifth * t));
      if (beat_phase < 0.09) {
        value += 0.35 * exp(-beat_phase * 35.0) *
            sin(2.0 * pi * 55.0 * beat_phase);
      }
      pcm[i] = (float)value;
    }
    assert(nar_automix_analyze(pcm, count, sample_rate, output,
                               NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
    assert(isfinite(output[0]));
    assert(fabs(output[0] / bpms[b] - 1.0) < 0.02);
    assert(isfinite(output[11]));
    const double phrase_ms = 60000.0 / output[0] * 16.0;
    double error = fmod(fabs(output[11] - expected_ms), phrase_ms);
    if (error > phrase_ms * 0.5) error = phrase_ms - error;
    assert(error < 25.0);
  }
  free(pcm);
}

static void test_analyzer_metre_and_section_boundary(void) {
  // 60 s at 120 BPM with an accented first beat of every three, and a chord
  // change from Am to F exactly at 30 s. Two independent features must be
  // measured: the metre (3, not the four-beat default) and a single
  // track-level section boundary at the change point.
  const int32_t sample_rate = 22050;
  const int32_t count = sample_rate * 60;
  float* pcm = (float*)malloc((size_t)count * sizeof(float));
  assert(pcm != NULL);
  double output[NAR_AUTOMIX_ANALYSIS_VALUE_COUNT];
  const double pi = 3.14159265358979323846;
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    const int chorus = t >= 30.0;
    const double root = chorus ? 174.6141 : 220.0;
    const double third = chorus ? 220.0 : 261.6256;
    const double fifth = chorus ? 261.6256 : 329.6276;
    double value = 0.12 * (sin(2.0 * pi * root * t) +
                           sin(2.0 * pi * third * t) +
                           sin(2.0 * pi * fifth * t));
    const double beat = fmod(t, 0.5);
    if (beat < 0.09) {
      const int bar_position = ((int)floor(t / 0.5)) % 3;
      const double accent = bar_position == 0 ? 0.50 : 0.28;
      value += accent * exp(-beat * 35.0) * sin(2.0 * pi * 55.0 * beat);
    }
    if (chorus) value += 0.04 * sin(2.0 * pi * 6000.0 * t);
    pcm[i] = (float)value;
  }
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(fabs(output[0] / 120.0 - 1.0) < 0.02);
  assert(output[32] == 3.0);
  // This fixture accents only the bar (every third beat) and changes chord
  // once, so a four-bar phrase phase is genuinely ambiguous and must stay
  // unknown rather than invent one from noise.
  assert(!isfinite(output[11]));
  // The section boundary is measured on 2 s chroma blocks, so one block of
  // tolerance is the expected resolution.
  assert(isfinite(output[33]));
  assert(fabs(output[33] - 30000.0) <= 2500.0);
  assert(output[34] >= 0.5);

  // The same arrangement without the section change must not invent a second
  // boundary: a steady loop has no section change point.
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    double value = 0.12 * (sin(2.0 * pi * 220.0 * t) +
                           sin(2.0 * pi * 261.6256 * t) +
                           sin(2.0 * pi * 329.6276 * t));
    const double beat = fmod(t, 0.5);
    if (beat < 0.09) {
      const int bar_position = ((int)floor(t / 0.5)) % 3;
      const double accent = bar_position == 0 ? 0.50 : 0.28;
      value += accent * exp(-beat * 35.0) * sin(2.0 * pi * 55.0 * beat);
    }
    pcm[i] = (float)value;
  }
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(!isfinite(output[33]));

  // Metre must also drive the phrase grid: the same chords changing every
  // four 3-beat bars (12 beats) must produce a 12-beat phrase phase, not a
  // 16-beat one. A hard-wired 16-beat grid would report a phase that drifts
  // by one beat per bar.
  const double phrase_ms = 60000.0 / 120.0 * 12.0;
  const double expected_ms = 137.0;
  for (int32_t i = 0; i < count; ++i) {
    const double t = (double)i / sample_rate;
    double local = t - expected_ms / 1000.0;
    if (local < 0.0) local += phrase_ms / 1000.0 * 4.0;
    const int chord = ((int)floor(local / (phrase_ms / 1000.0))) % 2;
    const double root = chord ? 174.6141 : 220.0;
    const double third = chord ? 220.0 : 261.6256;
    const double fifth = chord ? 261.6256 : 329.6276;
    double value = 0.12 * (sin(2.0 * pi * root * t) +
                           sin(2.0 * pi * third * t) +
                           sin(2.0 * pi * fifth * t));
    const double beat = fmod(local, 0.5);
    if (beat < 0.09) {
      const int bar_position = ((int)floor(local / 0.5)) % 3;
      const double accent = bar_position == 0 ? 0.50 : 0.30;
      value += accent * exp(-beat * 35.0) * sin(2.0 * pi * 55.0 * beat);
    }
    pcm[i] = (float)value;
  }
  assert(nar_automix_analyze(pcm, count, sample_rate, output,
                             NAR_AUTOMIX_ANALYSIS_VALUE_COUNT) == 1);
  assert(output[32] == 3.0);
  assert(isfinite(output[11]));
  double phase_error = fmod(fabs(output[11] - expected_ms), phrase_ms);
  if (phase_error > phrase_ms * 0.5) phase_error = phrase_ms - phase_error;
  assert(phase_error < 25.0);
  free(pcm);
}

int main(void) {
  test_live_tracker_fractional_phase_accuracy();
  test_live_tracker_resolves_third_and_double_tempo();
  test_live_tracker_reports_meter_and_rejects_flat_bars();
  test_analyzer_metre_and_section_boundary();
  test_analyzer_backbeat_keeps_beat_level();
  test_analyzer_sparse_intro_keeps_chorus_tempo();
  test_live_tracker_fractional_downbeat_accuracy();
  test_live_tracker_145bpm_accented_downbeat();
  test_live_tracker_resolves_half_tempo_lock();
  test_live_tracker_keeps_low_tempo();
  test_live_tracker_phase_follows_beat_grid();
  test_live_tracker_phase_stays_coherent_during_tempo_change();
  test_live_tracker_publishes_downbeat_phase();
  test_live_tracker_reports_activity_trend();
  test_live_tracker_requires_explicit_enable();
  test_live_tracker_ignores_lfe_and_surround_channels();
  test_live_tracker_disable_clears_live_state();
  test_live_tracker_reset_is_slot_local_during_processing();
  test_tone_processor_unity_bands_preserve_fade_target();
  test_tone_processor_nonfinite_intermediates_are_sanitized();
  test_tone_processor_various_frame_counts();
  test_crossfade_sample_peak_budget();
  test_ffi_contract_and_bounds();
  test_analyzer_rms();
  test_analyzer_vocal_center_channel();
  test_analyzer_structural_cues();
  test_planner_vocal_conflict();
  test_planner_keeps_start_and_permutation();
  test_planner_scores_tempo_at_seam();
  test_planner_uses_edge_local_intro_tempo();
  test_planner_falls_back_to_head_when_tail_tempo_is_untrusted();
  test_planner_penalizes_energy_seam();
  test_planner_prefers_calm_structural_seam();
  test_planner_prefers_continuing_momentum();
  test_planner_ignores_incomplete_momentum();
  test_planner_ignores_unconfident_structure();
  test_planner_spreads_repeated_artists();
  test_planner_relocation_polish_improves_local_optimum();
  test_planner_adaptive_energy_arc_lifts_loud_mids();
  test_chord_progression_analysis();
  test_chord_hangover_bridges_one_gap_and_not_trailing_silence();
  test_analyzer_hpcp_key_detection();
  test_analyzer_tempo_curve();
  test_analyzer_tempo_subframe();
  test_analyzer_beat_phase_timestamp();
  test_analyzer_phrase_phase_fractional_grid();
  test_analyzer_energy_quarters();
  test_analyzer_metrical_level_sweep();
  test_analyzer_beat_phase_survives_offbeat_hats();
  test_analyzer_key_rejects_noise_and_survives_detune();
  test_analyzer_phrase_phase_from_harmonic_change();
  test_chord_vocabulary_expansion();
  test_phase_lock_factor();
  test_phrase_lock();
  test_edge_cases_silence_and_noise();
  test_native_crossfade_curve();
  test_native_crossfade_targets_are_per_stream();
  test_tone_default_is_transparent();
  test_tone_filters_independent_streams();
  test_true_peak_limiter_is_transparent_by_default();
  test_true_peak_limiter_respects_ceiling();
  test_true_peak_limiter_disable_releases_smoothly();
  test_true_peak_limiter_catches_intersample_peaks();
  test_true_peak_limiter_is_per_stream();
  test_true_peak_limiter_reset_preserves_target();
  test_true_peak_limiter_block_boundaries_are_continuous();
  test_true_peak_limiter_rejects_invalid_input();
  test_stereo_mid_gain();
  return 0;
}
