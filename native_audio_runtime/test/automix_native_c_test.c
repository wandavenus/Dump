#include "automix_native.h"
#include "automix_tone_processor.h"

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
  assert(nar_automix_tone_set_high_gain(0, 0.0f) == 1);
  assert(nar_automix_tone_set_bass_gain(1, 1.0f) == 1);
  assert(nar_automix_tone_set_high_gain(1, 1.0f) == 1);
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

  assert(nar_automix_tone_set_bass_gain(0, NAN) == 1);
  assert(nar_automix_tone_set_high_gain(0, INFINITY) == 1);
  assert(nar_automix_tone_set_bass_gain(-1, 0.0f) == 0);
  assert(nar_automix_tone_configure(2, sample_rate, 2) == 0);
  free(filtered);
  free(dry);
}

int main(void) {
  test_analyzer_rms();
  test_planner_keeps_start_and_permutation();
  test_tone_default_is_transparent();
  test_tone_filters_independent_streams();
  return 0;
}
