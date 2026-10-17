#include "automix_native.h"
#include "automix_phase_lock.h"
#include "automix_tone_processor.h"

#include <assert.h>
#include <math.h>
#include <stdlib.h>

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
             0.5f, 1.0f, 0.8f, 0.5f, &outgoing, &incoming) == 1);
  assert(fabsf(outgoing - 0.8f * sqrtf(0.5f)) < 1e-6f);
  assert(fabsf(incoming - 0.5f * sqrtf(0.5f)) < 1e-6f);

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

  // Undersized buffer must return 0; 20 is one value short of the ABI.
  assert(nar_automix_analyze(pcm, count, sample_rate, output, 20) == 0);
  // Null inputs must return 0
  assert(nar_automix_analyze(NULL, count, sample_rate, output, 21) == 0);
  assert(nar_automix_analyze(pcm, count, 0, output, 21) == 0);
  assert(nar_automix_analyze(pcm, 100, sample_rate, output, 21) == 0);

  // Exact-sized buffer returns 1
  assert(nar_automix_analyze(pcm, count, sample_rate, output, 21) == 1);
  assert(isfinite(output[20]));
  assert(output[20] >= 0.0 && output[20] <= 1.0);

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

int main(void) {
  test_crossfade_sample_peak_budget();
  test_ffi_contract_and_bounds();
  test_analyzer_rms();
  test_analyzer_structural_cues();
  test_planner_vocal_conflict();
  test_planner_keeps_start_and_permutation();
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
