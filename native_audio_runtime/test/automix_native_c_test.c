#include "automix_native.h"

#include <assert.h>
#include <math.h>
#include <stdlib.h>

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
  free(pcm);
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

int main(void) {
  test_analyzer_rms();
  test_planner_keeps_start_and_permutation();
  return 0;
}
