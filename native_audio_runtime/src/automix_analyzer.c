#include "automix_native.h"

#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define FFT_SIZE 2048
#define FFT_BINS (FFT_SIZE / 2)
#define HOP_SIZE 512
#define BPM_MIN 60.0
#define BPM_MAX 200.0
#define BPM_PRIOR_CENTER 115.0
#define BPM_PRIOR_LOG2_WIDTH 0.55
#define CHROMA_MIN_FREQ 55.0
#define CHROMA_MAX_FREQ 5000.0
#define LN10 2.30258509299404568402
#define PI 3.14159265358979323846

#if defined(__aarch64__)
extern float nar_automix_window_rms_neon(
    const float* pcm, const float* hann, float* fft_real, int32_t count);
#endif

typedef struct {
  double bpm;
  double confidence;
  int valid;
} TempoEstimate;

static int compare_float(const void* lhs, const void* rhs) {
  const float a = *(const float*)lhs;
  const float b = *(const float*)rhs;
  return (a > b) - (a < b);
}

static float median_float(const float* values, int32_t count) {
  if (values == NULL || count <= 0) return NAN;
  float* sorted = (float*)malloc((size_t)count * sizeof(float));
  if (sorted == NULL) return NAN;
  memcpy(sorted, values, (size_t)count * sizeof(float));
  qsort(sorted, (size_t)count, sizeof(float), compare_float);
  const int32_t middle = count / 2;
  const float median = (count & 1) != 0
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) * 0.5f;
  free(sorted);
  return median;
}

static double mean_float_range(
    const float* values, int32_t begin, int32_t end) {
  if (values == NULL || begin < 0 || end <= begin) return NAN;
  double sum = 0.0;
  for (int32_t i = begin; i < end; ++i) sum += values[i];
  return sum / (double)(end - begin);
}

static void radix2_fft(float* real, float* imaginary,
                       const float* twiddle_real,
                       const float* twiddle_imaginary,
                       const int32_t* bit_reverse) {
  for (int32_t i = 0; i < FFT_SIZE; ++i) {
    const int32_t j = bit_reverse[i];
    if (i < j) {
      const float tr = real[i];
      real[i] = real[j];
      real[j] = tr;
      const float ti = imaginary[i];
      imaginary[i] = imaginary[j];
      imaginary[j] = ti;
    }
  }

  for (int32_t length = 2; length <= FFT_SIZE; length <<= 1) {
    const int32_t half = length >> 1;
    const int32_t stride = FFT_SIZE / length;
    for (int32_t base = 0; base < FFT_SIZE; base += length) {
      for (int32_t k = 0; k < half; ++k) {
        const int32_t a = base + k;
        const int32_t b = a + half;
        const int32_t twiddle = k * stride;
        const float wr = twiddle_real[twiddle];
        const float wi = twiddle_imaginary[twiddle];
        const float xr = real[b] * wr - imaginary[b] * wi;
        const float xi = real[b] * wi + imaginary[b] * wr;
        real[b] = real[a] - xr;
        imaginary[b] = imaginary[a] - xi;
        real[a] += xr;
        imaginary[a] += xi;
      }
    }
  }
}

static int32_t reverse_bits(int32_t value, int32_t bit_count) {
  int32_t result = 0;
  for (int32_t bit = 0; bit < bit_count; ++bit) {
    result = (result << 1) | (value & 1);
    value >>= 1;
  }
  return result;
}

static double log2_double(double value) {
  return log(value) / log(2.0);
}

static double pearson_12(const double* a, const double* b) {
  double mean_a = 0.0;
  double mean_b = 0.0;
  for (int i = 0; i < 12; ++i) {
    mean_a += a[i];
    mean_b += b[i];
  }
  mean_a /= 12.0;
  mean_b /= 12.0;

  double numerator = 0.0;
  double deviation_a = 0.0;
  double deviation_b = 0.0;
  for (int i = 0; i < 12; ++i) {
    const double xa = a[i] - mean_a;
    const double xb = b[i] - mean_b;
    numerator += xa * xb;
    deviation_a += xa * xa;
    deviation_b += xb * xb;
  }
  const double denominator = sqrt(deviation_a * deviation_b);
  return denominator < 1e-12 ? 0.0 : numerator / denominator;
}

static const double kKsMajor[12] = {
    6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
    2.52, 5.19, 2.39, 3.66, 2.29, 2.88};
static const double kKsMinor[12] = {
    6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
    2.54, 4.75, 3.98, 2.69, 3.34, 3.17};

static int estimate_key(const float* chroma, int32_t* tonic, int32_t* is_minor,
                        double* confidence) {
  double total = 0.0;
  double normalized[12];
  for (int i = 0; i < 12; ++i) total += chroma[i];
  if (total < 1e-6) return 0;
  for (int i = 0; i < 12; ++i) normalized[i] = chroma[i] / total;

  int best_pc = -1;
  int best_is_minor = 0;
  double best = -INFINITY;
  double second = -INFINITY;
  for (int mode = 0; mode < 2; ++mode) {
    const double* profile = mode == 0 ? kKsMajor : kKsMinor;
    double rotated[12];
    for (int shift = 0; shift < 12; ++shift) {
      for (int i = 0; i < 12; ++i) {
        rotated[i] = profile[(i - shift + 12) % 12];
      }
      const double corr = pearson_12(normalized, rotated);
      if (corr > best) {
        second = best;
        best = corr;
        best_pc = shift;
        best_is_minor = mode == 1;
      } else if (corr > second) {
        second = corr;
      }
    }
  }

  const double margin = fmax(0.0, best - second);
  *tonic = best_pc;
  *is_minor = best_is_minor;
  *confidence = margin < 0.02 ? 0.0 : fmin(1.0, margin / 0.12);
  return 1;
}

static double lag_score(const double* scores, int32_t lag, int32_t max_lag) {
  return lag >= 1 && lag <= max_lag ? scores[lag] : 0.0;
}

static TempoEstimate estimate_tempo(const float* odf, int32_t count,
                                   int32_t working_rate, double fps) {
  TempoEstimate result = {NAN, 0.0, 0};
  if (working_rate <= 0 || count < (int32_t)round(fps)) return result;

  double mean = 0.0;
  for (int32_t i = 0; i < count; ++i) mean += odf[i];
  mean /= count;
  double* env = (double*)malloc((size_t)count * sizeof(double));
  if (env == NULL) return result;
  double energy0 = 0.0;
  for (int32_t i = 0; i < count; ++i) {
    env[i] = (double)odf[i] - mean;
    energy0 += env[i] * env[i];
  }
  if (energy0 < 1e-12) {
    free(env);
    return result;
  }

  int32_t lag_min = (int32_t)round(fps * 60.0 / BPM_MAX);
  if (lag_min < 1) lag_min = 1;
  int32_t lag_max = (int32_t)fmin((double)(count / 2),
                                  round(fps * 60.0 / BPM_MIN));
  if (lag_max <= lag_min + 1) {
    free(env);
    return result;
  }

  double* scores = (double*)calloc((size_t)lag_max + 1, sizeof(double));
  double* comb = (double*)calloc((size_t)lag_max + 1, sizeof(double));
  if (scores == NULL || comb == NULL) {
    free(env);
    free(scores);
    free(comb);
    return result;
  }
  for (int32_t lag = lag_min; lag <= lag_max; ++lag) {
    double acc = 0.0;
    const int32_t limit = count - lag;
    for (int32_t i = 0; i < limit; ++i) acc += env[i] * env[i + lag];
    scores[lag] = acc / limit;
  }

  int32_t best_lag = -1;
  double best_weighted = -DBL_MAX;
  double sum_score = 0.0;
  double min_score = DBL_MAX;
  double max_score = -DBL_MAX;
  for (int32_t lag = lag_min; lag <= lag_max; ++lag) {
    const double score = scores[lag] +
        0.5 * lag_score(scores, lag * 2, lag_max) +
        0.25 * lag_score(scores, lag * 3, lag_max) +
        0.125 * lag_score(scores, lag * 4, lag_max);
    comb[lag] = score;
    const double bpm = 60.0 * fps / lag;
    const double ratio = log2_double(bpm / BPM_PRIOR_CENTER) /
                         BPM_PRIOR_LOG2_WIDTH;
    const double weighted = score * exp(-0.5 * ratio * ratio);
    sum_score += score;
    if (score < min_score) min_score = score;
    if (score > max_score) max_score = score;
    if (weighted > best_weighted) {
      best_weighted = weighted;
      best_lag = lag;
    }
  }
  if (best_lag <= 0) {
    free(env);
    free(scores);
    free(comb);
    return result;
  }

  const double bpm = 60.0 * fps / best_lag;
  const double mean_score = sum_score / (lag_max - lag_min + 1);
  const double spread = fmax(max_score - min_score, 1e-12);
  const double periodicity = fmax(0.0, scores[best_lag] / energy0 * count);
  const double prominence = fmin(1.0, fmax(0.0,
      (comb[best_lag] - mean_score) / spread));
  const double confidence = fmin(1.0, fmax(0.0,
      0.55 * prominence + 0.45 * fmin(1.0, fmax(0.0, periodicity))));
  result.bpm = bpm;
  result.confidence = confidence;
  result.valid = 1;
  free(env);
  free(scores);
  free(comb);
  return result;
}

static double estimate_beat_phase_ms(const float* odf, int32_t count,
                                     int32_t working_rate, double bpm) {
  if (!isfinite(bpm) || bpm < BPM_MIN || bpm > BPM_MAX || working_rate <= 0) {
    return NAN;
  }
  const double fps = (double)working_rate / HOP_SIZE;
  const int32_t period = (int32_t)round(fps * 60.0 / bpm);
  if (period < 2 || count < period * 4) return NAN;

  double mean = 0.0;
  for (int32_t i = 0; i < count; ++i) mean += odf[i];
  mean /= count;
  double* scores = (double*)calloc((size_t)period, sizeof(double));
  double* smoothed = (double*)calloc((size_t)period, sizeof(double));
  if (scores == NULL || smoothed == NULL) {
    free(scores);
    free(smoothed);
    return NAN;
  }
  int32_t peak_count = 0;
  double peak_energy = 0.0;
  for (int32_t i = 1; i < count - 1; ++i) {
    const double value = odf[i];
    if (value > odf[i - 1] && value >= odf[i + 1] && value > mean) {
      const double weight = value - mean;
      scores[i % period] += weight;
      peak_energy += weight;
      ++peak_count;
    }
  }
  if (peak_count < 8 || peak_energy <= 1e-9) {
    free(scores);
    free(smoothed);
    return NAN;
  }

  for (int32_t phase = 0; phase < period; ++phase) {
    const int32_t previous = (phase - 1 + period) % period;
    const int32_t next = (phase + 1) % period;
    smoothed[phase] = scores[previous] * 0.25 + scores[phase] * 0.5 +
                      scores[next] * 0.25;
  }
  int32_t best_phase = 0;
  double best_score = -DBL_MAX;
  double second_score = -DBL_MAX;
  for (int32_t phase = 0; phase < period; ++phase) {
    const double score = smoothed[phase];
    if (score > best_score) {
      second_score = best_score;
      best_score = score;
      best_phase = phase;
    } else if (score > second_score) {
      second_score = score;
    }
  }
  const double average = peak_energy / period;
  double phase = NAN;
  if (best_score > 0.0 && best_score >= average * 1.03 &&
      !(second_score > 0.0 && best_score / second_score < 1.005)) {
    phase = best_phase * (double)HOP_SIZE * 1000.0 / working_rate;
  }
  free(scores);
  free(smoothed);
  return phase;
}

static double estimate_onset_rate(const float* odf, int32_t count, double fps) {
  if (count < 4 || fps <= 0.0) return 0.0;
  double mean = 0.0;
  for (int32_t i = 0; i < count; ++i) mean += odf[i];
  mean /= count;
  double variance = 0.0;
  for (int32_t i = 0; i < count; ++i) {
    const double difference = (double)odf[i] - mean;
    variance += difference * difference;
  }
  const double threshold = mean + 0.4 * sqrt(fmax(variance / count, 1e-24));
  int32_t peaks = 0;
  for (int32_t i = 1; i < count - 1; ++i) {
    if (odf[i] > odf[i - 1] && odf[i] >= odf[i + 1] && odf[i] > threshold) {
      ++peaks;
    }
  }
  return (double)peaks * fps / count;
}

int32_t nar_automix_analyze(const float* mono, int32_t sample_count,
                            int32_t sample_rate, double* output,
                            int32_t output_count) {
  if (mono == NULL || output == NULL ||
      output_count < NAR_AUTOMIX_ANALYSIS_VALUE_COUNT ||
      sample_rate <= 0 || sample_count < sample_rate) {
    return 0;
  }
  for (int i = 0; i < NAR_AUTOMIX_ANALYSIS_VALUE_COUNT; ++i) output[i] = NAN;
  output[1] = 0.0;
  output[4] = -1.0;
  output[5] = 0.0;
  output[6] = 0.0;
  output[10] = 0.0;

  const int32_t frame_count = (sample_count - FFT_SIZE) / HOP_SIZE + 1;
  if (frame_count < 8) return 0;

  float* hann = (float*)malloc(FFT_SIZE * sizeof(float));
  float* real = (float*)malloc(FFT_SIZE * sizeof(float));
  float* imaginary = (float*)calloc(FFT_SIZE, sizeof(float));
  float* previous_log_magnitude = (float*)calloc(FFT_BINS, sizeof(float));
  float* odf = (float*)calloc((size_t)frame_count, sizeof(float));
  // rms_values packs only non-silent frames for a robust median. The
  // frame-aligned timeline preserves silent windows and is used for cue timing.
  float* rms_values = (float*)malloc((size_t)frame_count * sizeof(float));
  float* rms_frame_values = (float*)malloc((size_t)frame_count * sizeof(float));
  float* centroid_values = (float*)malloc((size_t)frame_count * sizeof(float));
  float* twiddle_real = (float*)malloc(FFT_BINS * sizeof(float));
  float* twiddle_imaginary = (float*)malloc(FFT_BINS * sizeof(float));
  int32_t* bit_reverse = (int32_t*)malloc(FFT_SIZE * sizeof(int32_t));
  if (hann == NULL || real == NULL || imaginary == NULL ||
      previous_log_magnitude == NULL || odf == NULL || rms_values == NULL ||
      rms_frame_values == NULL || centroid_values == NULL || twiddle_real == NULL ||
      twiddle_imaginary == NULL || bit_reverse == NULL) {
    free(hann); free(real); free(imaginary); free(previous_log_magnitude);
    free(odf); free(rms_values); free(rms_frame_values); free(centroid_values); free(twiddle_real);
    free(twiddle_imaginary); free(bit_reverse);
    return 0;
  }

  for (int32_t i = 0; i < FFT_SIZE; ++i) {
    hann[i] = (float)(0.5 - 0.5 * cos(2.0 * PI * i / FFT_SIZE));
    bit_reverse[i] = reverse_bits(i, 11);
  }
  for (int32_t i = 0; i < FFT_BINS; ++i) {
    const double angle = -2.0 * PI * i / FFT_SIZE;
    twiddle_real[i] = (float)cos(angle);
    twiddle_imaginary[i] = (float)sin(angle);
  }

  int32_t rms_count = 0;
  int32_t centroid_count = 0;
  float chroma[12] = {0};
  const double working_rate = sample_rate;
  for (int32_t frame = 0; frame < frame_count; ++frame) {
    const float* input = mono + (size_t)frame * HOP_SIZE;
    double square_sum = 0.0;
#if defined(__aarch64__)
    square_sum = nar_automix_window_rms_neon(input, hann, real, FFT_SIZE);
#else
    for (int32_t i = 0; i < FFT_SIZE; ++i) {
      const float sample = input[i];
      real[i] = sample * hann[i];
      square_sum += (double)sample * sample;
    }
#endif
    memset(imaginary, 0, FFT_SIZE * sizeof(float));
    const double rms = sqrt(square_sum / FFT_SIZE);
    // Store every frame on the same time axis. -120 dBFS is the explicit
    // silence floor; the packed array below excludes these frames for median.
    const float rms_db = (float)(20.0 * log(fmax(rms, 1e-6)) / LN10);
    rms_frame_values[frame] = rms_db;
    if (rms > 1e-6) {
      rms_values[rms_count++] = rms_db;
    }

    radix2_fft(real, imaginary, twiddle_real, twiddle_imaginary, bit_reverse);
    float flux = 0.0f;
    double weight_sum = 0.0;
    double frequency_sum = 0.0;
    for (int32_t bin = 0; bin < FFT_BINS; ++bin) {
      const float magnitude = sqrtf(real[bin] * real[bin] +
                                    imaginary[bin] * imaginary[bin]);
      const float log_magnitude = logf(magnitude + 1.0f);
      const float difference = log_magnitude - previous_log_magnitude[bin];
      if (difference > 0.0f) flux += difference;
      previous_log_magnitude[bin] = log_magnitude;

      const double frequency = bin * working_rate / FFT_SIZE;
      if (frequency >= CHROMA_MIN_FREQ && frequency <= CHROMA_MAX_FREQ) {
        weight_sum += magnitude;
        frequency_sum += magnitude * frequency;
        if (bin > 0 && magnitude >= 1e-6f) {
          const double pitch = 12.0 * log2_double(frequency / 440.0) + 69.0;
          const int lower = (int)floor(pitch);
          const int pitch_class = ((lower % 12) + 12) % 12;
          const double fraction = fmin(1.0, fmax(0.0, pitch - lower));
          chroma[pitch_class] += (float)(magnitude * (1.0 - fraction));
          chroma[(pitch_class + 1) % 12] += (float)(magnitude * fraction);
        }
      }
    }
    odf[frame] = flux;
    if (weight_sum > 1e-9) {
      centroid_values[centroid_count++] = (float)(frequency_sum / weight_sum);
    }
  }

  const double fps = working_rate / HOP_SIZE;
  const TempoEstimate tempo = estimate_tempo(odf, frame_count, sample_rate, fps);
  if (tempo.valid) {
    output[0] = tempo.bpm;
    output[1] = tempo.confidence;
    output[2] = tempo.bpm < 90.0 ? tempo.bpm * 2.0
        : tempo.bpm > 140.0 ? tempo.bpm / 2.0 : NAN;
    if (tempo.confidence >= 0.20) {
      output[3] = estimate_beat_phase_ms(odf, frame_count, sample_rate,
                                        tempo.bpm);
    }
  }
  int32_t tonic = -1;
  int32_t is_minor = 0;
  double key_confidence = 0.0;
  if (estimate_key(chroma, &tonic, &is_minor, &key_confidence)) {
    output[4] = tonic;
    output[5] = is_minor;
    output[6] = key_confidence;
  }
  const float rms_median = median_float(rms_values, rms_count);
  const float centroid_median = median_float(centroid_values, centroid_count);
  output[7] = isfinite(rms_median) ? rms_median : NAN;
  output[8] = isfinite(centroid_median) ? centroid_median : NAN;
  output[9] = estimate_onset_rate(odf, frame_count, fps);
  output[10] = (double)sample_count / working_rate;

  // 1. Downbeat (Bar 1) phase estimation (4-beat downbeat offset in ms).
  if (tempo.valid && tempo.confidence >= 0.20 && isfinite(output[3])) {
    const double beat_ms = 60000.0 / tempo.bpm;
    const double bar_ms = beat_ms * 4.0;
    // Downbeat is estimated from the strongest 4-beat periodic onset pulse.
    const double beat_offset = output[3];
    double best_bar_offset = beat_offset;
    double max_bar_energy = -1.0;
    for (int b = 0; b < 4; ++b) {
      const double cand_offset = beat_offset + b * beat_ms;
      double bar_energy = 0.0;
      for (int i = 0; i < frame_count; ++i) {
        const double t_ms = i * (double)HOP_SIZE * 1000.0 / working_rate;
        const double phase = fmod(t_ms - cand_offset, bar_ms);
        if (fabs(phase) < beat_ms * 0.25 || fabs(phase - bar_ms) < beat_ms * 0.25) {
          bar_energy += odf[i];
        }
      }
      if (bar_energy > max_bar_energy) {
        max_bar_energy = bar_energy;
        best_bar_offset = cand_offset;
      }
    }
    output[11] = fmod(best_bar_offset, bar_ms);
  } else {
    output[11] = NAN;
  }

  // 2. Conservative structural cues. A global maximum onset or minimum RMS
  // is not a structural cue: both occur in ordinary music and silence. Only
  // publish a candidate when a sustained energy change is corroborated by the
  // onset envelope (drop) or by a high-to-low energy transition (breakdown).
  output[12] = NAN; // Drop cue
  output[13] = NAN; // Breakdown cue
  if (frame_count > 16 && isfinite(rms_median) && rms_median > -80.0f) {
    float max_flux = 0.0f;
    for (int32_t i = 4; i < frame_count - 4; ++i) {
      if (isfinite(odf[i]) && odf[i] > max_flux) max_flux = odf[i];
    }

    const int32_t before_frames =
        (int32_t)fmax(4.0, round(fps * 0.75));
    const int32_t after_frames =
        (int32_t)fmax(4.0, round(fps * 0.50));
    double best_drop_score = 0.0;
    int32_t best_drop_idx = -1;
    double best_breakdown_score = 0.0;
    int32_t best_breakdown_idx = -1;

    if (max_flux > 1e-8f &&
        frame_count > before_frames + after_frames + 8) {
      for (int32_t i = before_frames;
           i < frame_count - after_frames - 4; ++i) {
        const double before = mean_float_range(
            rms_frame_values, i - before_frames, i);
        const double after = mean_float_range(
            rms_frame_values, i, i + after_frames);
        if (!isfinite(before) || !isfinite(after)) continue;

        float nearby_flux = 0.0f;
        for (int32_t j = i; j < i + after_frames; ++j) {
          if (odf[j] > nearby_flux) nearby_flux = odf[j];
        }

        // RMS values are dBFS: differences are additive (not ratios). A drop
        // needs a quieter lead-in, a sustained rise, and a nearby onset.
        if (before <= (double)rms_median - 3.0 &&
            after >= (double)rms_median - 3.0 &&
            after - before >= 4.0 &&
            nearby_flux >= max_flux * 0.20) {
          const double score = (after - before) +
              0.25 * (double)nearby_flux / max_flux;
          if (score > best_drop_score) {
            best_drop_score = score;
            best_drop_idx = i;
          }
        }

        // Breakdown: sustained energy falls from above the track's typical
        // level to clearly below it; short transient-only dips do not qualify.
        if (before >= (double)rms_median + 2.0 &&
            after <= (double)rms_median - 3.0 &&
            before - after >= 4.0) {
          const double score = before - after;
          if (score > best_breakdown_score) {
            best_breakdown_score = score;
            best_breakdown_idx = i;
          }
        }
      }
    }

    if (best_drop_idx >= 0) {
      output[12] =
          best_drop_idx * (double)HOP_SIZE * 1000.0 / working_rate;
    }
    if (best_breakdown_idx >= 0) {
      output[13] =
          best_breakdown_idx * (double)HOP_SIZE * 1000.0 / working_rate;
    }
  }

  free(hann); free(real); free(imaginary); free(previous_log_magnitude);
  free(odf); free(rms_values); free(rms_frame_values); free(centroid_values); free(twiddle_real);
  free(twiddle_imaginary); free(bit_reverse);
  return 1;
}
