#include "automix_native.h"
#ifdef AUTOMIX_DEBUG_PHRASE
#include <stdio.h>
#endif

#include <float.h>
#ifdef AUTOMIX_DEBUG_METRICAL
#include <stdio.h>
#endif
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define FFT_SIZE 2048
#define FFT_BINS (FFT_SIZE / 2)
#define HOP_SIZE 512
#define BPM_MIN 60.0
#define BPM_MAX 200.0
#define CHROMA_MIN_FREQ 55.0
#define CHROMA_MAX_FREQ 5000.0
// Onset bands for the beat/bar phase grid. A broadband log-flux onset
// function rates an unaccented off-beat hi-hat as comparable to a kick because
// the hat's increase is spread over thousands of bins while the kick's is
// concentrated in a handful. Splitting the flux by band and weighting low and
// mid far above high keeps the beat where the listener hears it, without a
// second transform or any extra STFT cost.
#define ODF_LOW_MIN_FREQ 30.0
#define ODF_LOW_MAX_FREQ 150.0
#define ODF_MID_MAX_FREQ 1500.0
#define ODF_HIGH_MAX_FREQ 8000.0
#define ODF_PHASE_LOW_WEIGHT 1.0
#define ODF_PHASE_MID_WEIGHT 0.55
#define ODF_PHASE_HIGH_WEIGHT 0.15
#define METRICAL_PRIOR_CENTER 120.0
#define METRICAL_PRIOR_LOG2_WIDTH 0.90
// Harmonic pitch class profile tuning: fold each spectral peak's harmonics
// (weighted 1/h) onto the nearest pitch classes with a raised-cosine window,
// so detuned material stays on the correct class instead of bleeding across
// the halfway point between classes. Peaks must reach this fraction of the
// frame's strongest magnitude to contribute.
#define HPCP_HARMONICS 2
#define HPCP_TOLERANCE_SEMITONES 0.6
#define HPCP_PEAK_FLOOR 0.05
// Timestamp assigned to one spectral-flux frame. The STFT frame is windowed at
// [frame * HOP_SIZE, frame * HOP_SIZE + FFT_SIZE), but positive log-spectral
// difference reports energy that is *entering* the window: a transient raises
// the flux while it travels from the window end toward its centre, and the
// backward difference spans one hop. Timestamping the frame at its centre plus
// half a hop (1280 samples, ~58 ms at 22.05 kHz) removes the ~2.5-hop lead the
// raw frame start gave every beat phase and phrase phase.
// Synthetic impulse regressions at 16/22.05/24/44.1/48 kHz confirm the residual
// stays inside one hop. RMS-derived structural cues keep the frame-start
// timestamp: their "after" window begins there, so no flux lead applies.
#define ODF_TIMESTAMP_OFFSET_SAMPLES ((FFT_SIZE + HOP_SIZE) / 2)
// The shortest fades are 1.5 s and the longest 12 s, so a 15 s edge window
// always contains the material the seam decisions actually hear. Edge stats
// are measured on the same frames as the rest of the analyzer; LUFS uses the
// raw samples with the ITU-R BS.1770 K-weighting filters.
#define AUTOMIX_EDGE_SECONDS 15.0
#define LN10 2.30258509299404568402
#define PI 3.14159265358979323846

#if defined(__aarch64__)
extern float nar_automix_window_rms_neon(
    const float* pcm, const float* hann, float* fft_real, int32_t count);
#endif

typedef struct {
  double bpm;
  // Runner-up metrical interpretation (half/double/other simple ratio). NAN
  // when the winning level is unambiguous or no second candidate exists.
  double alternate_bpm;
  double confidence;
  int valid;
} TempoEstimate;

typedef struct {
  double period_frames;
  double bpm;
  double score;
  double comb;
  double coverage;
  double fill;
  double contrast;
  double phase;
} MetricalCandidate;

static double clamp01_double(double value) {
  return fmin(1.0, fmax(0.0, value));
}

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

// Cepstral peak prominence: a periodicity cue that is less fooled by a single
// strong partial than raw spectral concentration. The real cepstrum is the
// inverse FFT of the log magnitude spectrum; a peak in the voice-pitch
// quefrency range above the local trend indicates regularly spaced harmonics.
static double cepstral_peak_prominence(
    const float* magnitudes, float* cepstrum_real, float* cepstrum_imaginary,
    const float* twiddle_real, const float* twiddle_imaginary,
    const int32_t* bit_reverse, int32_t sample_rate) {
  if (magnitudes == NULL || cepstrum_real == NULL ||
      cepstrum_imaginary == NULL || twiddle_real == NULL ||
      twiddle_imaginary == NULL || bit_reverse == NULL || sample_rate <= 0) {
    return NAN;
  }
  for (int32_t i = 0; i < FFT_SIZE; ++i) {
    cepstrum_real[i] = 0.0f;
    cepstrum_imaginary[i] = 0.0f;
  }
  cepstrum_real[0] = logf(magnitudes[0] + 1e-9f);
  for (int32_t bin = 1; bin < FFT_BINS; ++bin) {
    const float value = logf(magnitudes[bin] + 1e-9f);
    cepstrum_real[bin] = value;
    cepstrum_real[FFT_SIZE - bin] = value;
  }
  // The analyzer fills bins [0, FFT_BINS); FFT_BINS itself is the Nyquist
  // slot. Mirror the highest available bin instead of leaving a notch.
  cepstrum_real[FFT_BINS] = logf(magnitudes[FFT_BINS - 1] + 1e-9f);
  radix2_fft(cepstrum_real, cepstrum_imaginary, twiddle_real,
             twiddle_imaginary, bit_reverse);

  const int32_t q_min =
      (int32_t)fmax(2.0, floor((double)sample_rate / 400.0));
  const int32_t q_max = (int32_t)fmin(
      (double)(FFT_SIZE / 2 - 1), ceil((double)sample_rate / 60.0));
  if (q_max <= q_min + 4) return NAN;

  const double scale = 1.0 / FFT_SIZE;
  double sum_x = 0.0;
  double sum_y = 0.0;
  double sum_xx = 0.0;
  double sum_xy = 0.0;
  double peak_value = -DBL_MAX;
  int32_t peak_index = q_min;
  int32_t count = 0;
  for (int32_t q = q_min; q <= q_max; ++q) {
    const double value = (double)cepstrum_real[q] * scale;
    if (value > peak_value) {
      peak_value = value;
      peak_index = q;
    }
    sum_x += q;
    sum_y += value;
    sum_xx += (double)q * q;
    sum_xy += (double)q * value;
    ++count;
  }
  const double denominator = count * sum_xx - sum_x * sum_x;
  if (count < 8 || fabs(denominator) < 1e-12) return NAN;
  const double slope = (count * sum_xy - sum_x * sum_y) / denominator;
  const double intercept = (sum_y - slope * sum_x) / count;

  double residual_sum = 0.0;
  for (int32_t q = q_min; q <= q_max; ++q) {
    const double value = (double)cepstrum_real[q] * scale;
    const double residual = value - (intercept + slope * q);
    residual_sum += residual * residual;
  }
  const double residual_sd = sqrt(residual_sum / count);
  const double baseline = intercept + slope * peak_index;
  return (peak_value - baseline) / fmax(residual_sd, 1e-9);
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

// Circular fractional chroma rotation. A recording tuned a few tens of cents
// sharp or flat produces spectral peaks between pitch classes; rotating the
// chromagram before profile matching recovers the intended key instead of
// landing on a neighbouring class.
static void rotate_chroma_12(const double* input, double shift,
                             double* output) {
  for (int i = 0; i < 12; ++i) {
    double source = (double)i - shift;
    while (source < 0.0) source += 12.0;
    while (source >= 12.0) source -= 12.0;
    const int lower = (int)floor(source) % 12;
    const double fraction = source - floor(source);
    const int upper = (lower + 1) % 12;
    output[i] = input[lower] * (1.0 - fraction) +
                input[upper] * fraction;
  }
}

static double chroma_entropy(const double* normalized) {
  double entropy = 0.0;
  for (int i = 0; i < 12; ++i) {
    const double value = normalized[i];
    if (value > 1e-9) entropy -= value * log(value);
  }
  return entropy / log(12.0);
}

static int estimate_key(const double* chroma, int32_t* tonic, int32_t* is_minor,
                        double* confidence) {
  double total = 0.0;
  double normalized[12];
  for (int i = 0; i < 12; ++i) total += chroma[i];
  if (total < 1e-6) return 0;
  for (int i = 0; i < 12; ++i) normalized[i] = chroma[i] / total;

  // A key from percussion or white noise is not "uncertain", it is
  // meaningless. Require both spectral spread (entropy) and at least a triad's
  // worth of distinct pitch classes before publishing any key at all.
  const double entropy = chroma_entropy(normalized);
  double max_share = 0.0;
  for (int i = 0; i < 12; ++i) {
    if (normalized[i] > max_share) max_share = normalized[i];
  }
  const double class_floor = fmax(0.02, 0.12 * max_share);
  int32_t rich_classes = 0;
  for (int i = 0; i < 12; ++i) {
    if (normalized[i] >= class_floor) ++rich_classes;
  }
  if (entropy > 0.95 || rich_classes < 3) {
    *tonic = -1;
    *is_minor = 0;
    *confidence = 0.0;
    return 1;
  }

  int best_pc = -1;
  int best_is_minor = 0;
  int best_tuning_step = 0;
  double best = -INFINITY;
  // Tuning search: +-50 cents in 5-cent steps. HPCP already tolerates a
  // half-semitone before folding, so the residual rotation needed here is small
  // and a coarse grid cannot invent a different key.
  double tuned[12];
  for (int step = -10; step <= 10; ++step) {
    rotate_chroma_12(normalized, (double)step * 0.05, tuned);
    for (int mode = 0; mode < 2; ++mode) {
      const double* profile = mode == 0 ? kKsMajor : kKsMinor;
      double rotated[12];
      for (int shift = 0; shift < 12; ++shift) {
        for (int i = 0; i < 12; ++i) {
          rotated[i] = profile[(i - shift + 12) % 12];
        }
        const double corr = pearson_12(tuned, rotated);
        if (corr > best) {
          best = corr;
          best_pc = shift;
          best_is_minor = mode == 1;
          best_tuning_step = step;
        }
      }
    }
  }

  // Measure the margin at the winning tuning. Comparing across tuning steps
  // would report a near-tie for every track because a rotated profile can
  // approximate a different key almost as well.
  rotate_chroma_12(normalized, (double)best_tuning_step * 0.05, tuned);
  double second = -INFINITY;
  const int relative_pc = best_is_minor ? (best_pc + 3) % 12
                                        : (best_pc + 9) % 12;
  const int relative_is_minor = !best_is_minor;
  double relative_corr = -INFINITY;
  for (int mode = 0; mode < 2; ++mode) {
    const double* profile = mode == 0 ? kKsMajor : kKsMinor;
    double rotated[12];
    for (int shift = 0; shift < 12; ++shift) {
      if (shift == best_pc && (mode == 1) == (best_is_minor == 1)) continue;
      for (int i = 0; i < 12; ++i) {
        rotated[i] = profile[(i - shift + 12) % 12];
      }
      const double corr = pearson_12(tuned, rotated);
      if (corr > second) second = corr;
      if (shift == relative_pc && (mode == 1) == (relative_is_minor == 1)) {
        relative_corr = corr;
      }
    }
  }
  if (!isfinite(second)) second = 0.0;
  if (!isfinite(relative_corr)) relative_corr = 0.0;
  const double margin = fmax(0.0, best - second);
  // Relative major/minor is a genuine ambiguity: the same pitch content fits
  // both profiles and only the progression's emphasis would decide. A 1.00
  // confidence here made A-minor loops look like a two-step move and could
  // trigger the outgoing pitch shift on the wrong tonic.
  const double relative_ratio = clamp01_double((best - relative_corr) / 0.25);
  const double relative_factor = 0.55 + 0.45 * relative_ratio;
  // Confidence is now absolute evidence * margin * tonal quality, not a raw
  // 24-way argmax margin. A flat chroma can no longer score 0.754: it fails
  // the entropy gate above, and a near-tie between relative major and minor
  // lowers the margin term instead of reporting certainty.
  const double absolute = clamp01_double((best - 0.55) / 0.30);
  const double margin_term = clamp01_double(margin / 0.08);
  const double flatness_gate = clamp01_double((0.95 - entropy) / 0.10);
  *tonic = best_pc;
  *is_minor = best_is_minor;
  *confidence = clamp01_double(absolute * (0.55 + 0.45 * margin_term) *
                               flatness_gate * relative_factor);
  return 1;
}

static double lag_score(const double* scores, int32_t lag, int32_t max_lag) {
  return lag >= 1 && lag <= max_lag ? scores[lag] : 0.0;
}

// Shared chroma front end for key detection and the chord classifier. Every
// local spectral peak (log-magnitude refined for precise frequency) folds its
// first HPCP_HARMONICS harmonics onto pitch classes. The raised-cosine window
// spans +/- HPCP_TOLERANCE_SEMITONES, so a globally detuned recording keeps
// its energy on the intended class while the harmonic fold reinforces the
// fundamental class that the observed harmonics already imply.
static void hpcp_add_frame(const float* magnitude, int32_t bin_count,
                           double sample_rate, int32_t fft_size,
                           double* hpcp) {
  double frame_max = 0.0;
  for (int32_t bin = 1; bin + 1 < bin_count; ++bin) {
    if ((double)magnitude[bin] > frame_max) frame_max = magnitude[bin];
  }
  if (frame_max <= 1e-9) return;
  const double floor_magnitude = frame_max * HPCP_PEAK_FLOOR;

  for (int32_t bin = 2; bin + 1 < bin_count; ++bin) {
    const double center = magnitude[bin];
    if (center < floor_magnitude ||
        center < magnitude[bin - 1] || center < magnitude[bin + 1]) {
      continue;
    }
    // Parabolic peak refinement on log magnitudes estimates the true peak
    // position within the bin.
    const double left = log((double)magnitude[bin - 1] + 1e-12);
    const double middle = log(center + 1e-12);
    const double right = log((double)magnitude[bin + 1] + 1e-12);
    const double denominator = left - 2.0 * middle + right;
    double offset = denominator < -1e-12
        ? 0.5 * (left - right) / denominator : 0.0;
    if (!isfinite(offset) || offset < -1.0) offset = -1.0;
    if (offset > 1.0) offset = 1.0;
    const double frequency = ((double)bin + offset) * sample_rate / fft_size;
    if (frequency < CHROMA_MIN_FREQ) continue;

    for (int32_t harmonic = 1; harmonic <= HPCP_HARMONICS; ++harmonic) {
      const double harmonic_frequency = frequency * harmonic;
      if (harmonic_frequency > CHROMA_MAX_FREQ) break;
      if (harmonic_frequency < CHROMA_MIN_FREQ) continue;
      const double pitch =
          12.0 * log2_double(harmonic_frequency / 440.0) + 69.0;
      const double nearest = round(pitch);
      const double deviation = pitch - nearest;
      if (fabs(deviation) > HPCP_TOLERANCE_SEMITONES) continue;
      const double window = cos(
          (PI / 2.0) * deviation / HPCP_TOLERANCE_SEMITONES);
      const int pitch_class = ((int32_t)nearest % 12 + 12) % 12;
      hpcp[pitch_class] += center * window * window / (double)harmonic;
    }
  }
}

static double folded_tempo_error(double a, double b) {
  if (!isfinite(a) || !isfinite(b) || a <= 0.0 || b <= 0.0) return 1.0;
  double error = fabs(log2_double(a / b));
  error -= floor(error);
  if (error > 0.5) error = 1.0 - error;
  return error;
}

static double refine_lag_peak(const double* scores, int32_t lag_min,
                              int32_t lag_max, int32_t lag) {
  if (scores == NULL || lag <= lag_min || lag >= lag_max) return 0.0;
  const double left = scores[lag - 1];
  const double center = scores[lag];
  const double right = scores[lag + 1];
  if (!isfinite(left) || !isfinite(center) || !isfinite(right) ||
      center < left || center < right) {
    return 0.0;
  }
  const double denominator = left - 2.0 * center + right;
  if (!isfinite(denominator) || denominator >= -1e-18) return 0.0;
  double offset = 0.5 * (left - right) / denominator;
  if (!isfinite(offset)) return 0.0;
  if (offset < -0.5) offset = -0.5;
  if (offset > 0.5) offset = 0.5;
  return offset;
}

// Integer-lag autocorrelation gets the tempo close, but its peak is quantized
// to the FFT hop and is slightly biased by the window/pulse envelope. Refine
// it by maximizing phase coherence of the onset peaks over a narrow period
// search: when the period is right, every beat contributes to the same
// complex phase, so the resultant vector is long. This is a classical
// beat-tracking cue, not a learned model, and it gives the downstream phase
// estimator a period that stays aligned across a 48 s window.
static double onset_phase_coherence(const int32_t* indices,
                                     const double* weights, int32_t count,
                                     double period) {
  if (indices == NULL || weights == NULL || count <= 0 ||
      !isfinite(period) || period <= 0.0) {
    return 0.0;
  }
  double real = 0.0;
  double imaginary = 0.0;
  double total = 0.0;
  for (int32_t k = 0; k < count; ++k) {
    const double angle = 2.0 * PI * (double)indices[k] / period;
    real += weights[k] * cos(angle);
    imaginary += weights[k] * sin(angle);
    total += weights[k];
  }
  return total > 1e-12 ? hypot(real, imaginary) / total : 0.0;
}

// Collect the onset peaks used by every metrical hypothesis. Weighting by
// excess over the mean keeps loud backbeats and kicks dominant over quiet
// subdivisions, which is the evidence that separates a beat from its half-beat.
static int32_t collect_onset_peaks(const float* env, int32_t count, double mean,
                                   double* indices, double* weights,
                                   int32_t capacity) {
  int32_t used = 0;
  if (env == NULL || indices == NULL || weights == NULL || capacity <= 0) {
    return 0;
  }
  for (int32_t i = 1; i < count - 1 && used < capacity; ++i) {
    const double value = (double)env[i];
    if (value > (double)env[i - 1] && value >= (double)env[i + 1] &&
        value > mean) {
      const double weight = value - mean;
      if (weight > 0.0 && isfinite(weight)) {
        indices[used] = (double)i;
        weights[used] = weight;
        ++used;
      }
    }
  }
  return used;
}

// Fraction of onset energy that lands on the candidate grid. This is what
// distinguishes the true beat from a multiple of it: a grid at 2P or 3P still
// has a strong pulse at every line, but it leaves half or two-thirds of the
// real onsets between lines.
static double onset_grid_coverage(const double* indices, const double* weights,
                                  int32_t count, double period, double phase,
                                  double tolerance) {
  if (indices == NULL || weights == NULL || count <= 0 ||
      !isfinite(period) || period <= 1.0 || !isfinite(phase)) {
    return 0.0;
  }
  double covered = 0.0;
  double total = 0.0;
  for (int32_t k = 0; k < count; ++k) {
    total += weights[k];
    double distance = fmod(indices[k] - phase, period);
    if (distance < 0.0) distance += period;
    if (distance > period * 0.5) distance = period - distance;
    if (distance <= tolerance) covered += weights[k];
  }
  return total > 1e-12 ? covered / total : 0.0;
}

static double band_peak_at(const float* env, int32_t count, int32_t center) {
  double peak = 0.0;
  for (int32_t delta = -2; delta <= 2; ++delta) {
    const int32_t index = center + delta;
    if (index >= 0 && index < count && (double)env[index] > peak) {
      peak = (double)env[index];
    }
  }
  return peak;
}

// Grid fill and on/off contrast. Fill punishes sub-multiples: a grid at P/2
// places every other line on a weak subdivision, so those lines fall below the
// accent floor. Contrast punishes multiples: a grid at 2P has as much energy
// halfway between its lines as on them.
static void grid_fill_contrast(const float* env, int32_t count, double period,
                               double phase, double* fill,
                               double* contrast) {
  *fill = 0.0;
  *contrast = 0.0;
  if (env == NULL || count <= 0 || !isfinite(period) || period <= 1.0 ||
      !isfinite(phase)) {
    return;
  }
  double max_env = 0.0;
  for (int32_t i = 0; i < count; ++i) {
    if ((double)env[i] > max_env) max_env = (double)env[i];
  }
  if (max_env <= 1e-9) return;
  // A beat line must carry a clear accent, not merely some onset. The floor is
  // relative to the strongest onset in the window, so a quiet 8th-note hat no
  // longer counts as a filled beat slot while a backbeat does.
  const double floor = 0.45 * max_env;
  int32_t slots = 0;
  int32_t filled = 0;
  double on_sum = 0.0;
  double off_sum = 0.0;
  for (double time = phase; time < (double)count; time += period) {
    const double on_peak = band_peak_at(env, count, (int32_t)llround(time));
    const double off_peak = band_peak_at(
        env, count, (int32_t)llround(time + period * 0.5));
    if (on_peak >= floor) ++filled;
    ++slots;
    on_sum += on_peak;
    off_sum += off_peak;
  }
  if (slots <= 0) return;
  *fill = (double)filled / (double)slots;
  const double denominator = on_sum + off_sum;
  if (denominator > 1e-9) {
    *contrast = clamp01_double((on_sum - off_sum) / denominator);
  }
}

static double refine_tempo_phase_coherence(const float* odf, int32_t count,
                                           double fps, double initial_bpm);

// Evaluate one metrical-level hypothesis. The score is a weighted mean of
// independent evidence: autocorrelation comb strength, onset coverage, grid
// fill, beat-vs-offbeat accent contrast, and phase coherence. The tempo prior
// remains only as a weak tie-break (15%); it is no longer the decision maker.
static MetricalCandidate evaluate_metrical_candidate(
    int32_t lag, const double* comb, int32_t lag_min, int32_t lag_max,
    double comb_max, const float* env, int32_t count, double fps,
    const double* indices, const double* weights, int32_t onset_count) {
  MetricalCandidate candidate;
  memset(&candidate, 0, sizeof(candidate));
  if (lag < lag_min || lag > lag_max || comb == NULL) return candidate;
  double period = (double)lag;
  if (lag > lag_min && lag < lag_max) {
    const double offset = refine_lag_peak(comb, lag_min, lag_max, lag);
    if (isfinite(offset)) period += offset;
  }
  // Integer autocorrelation lags quantise a fractional beat period. A 125 BPM
  // beat is 20.64 frames; an unfixed lag of 21 drifts a full beat every ~48 s,
  // which destroys the very coverage/fill evidence this hypothesis is scored
  // on. Refine each candidate against onset phase coherence (bounded to one
  // frame, so it cannot jump to another metrical level).
  if (onset_count >= 8) {
    const double refined_bpm = refine_tempo_phase_coherence(
        env, count, fps, 60.0 * fps / period);
    if (isfinite(refined_bpm) && refined_bpm > 0.0) {
      const double refined_period = 60.0 * fps / refined_bpm;
      if (isfinite(refined_period) && refined_period > 1.0 &&
          fabs(refined_period - period) <= 1.01) {
        period = refined_period;
      }
    }
  }
  if (!isfinite(period) || period < 2.0) return candidate;

  // Best grid phase from the *strong* onset subset. Folding every onset at the
  // beat period cancels when an off-beat hat carries comparable flux, which
  // leaves the phase (and therefore coverage and fill) arbitrary. Anchoring on
  // accents and then scoring the full onset set against that grid removes the
  // cancellation without discarding the subdivision as evidence.
  double max_weight = 0.0;
  for (int32_t k = 0; k < onset_count; ++k) {
    if (weights[k] > max_weight) max_weight = weights[k];
  }
  const double strong_floor = 0.5 * max_weight;
  double real = 0.0;
  double imaginary = 0.0;
  double total = 0.0;
  double strong_total = 0.0;
  for (int32_t k = 0; k < onset_count; ++k) {
    const double angle = 2.0 * PI * indices[k] / period;
    if (weights[k] >= strong_floor) {
      real += weights[k] * cos(angle);
      imaginary += weights[k] * sin(angle);
      strong_total += weights[k];
    }
    total += weights[k];
  }
  if (total <= 1e-12) return candidate;
  if (strong_total <= 1e-12) {
    // Too few accents to anchor on: fall back to the full onset set.
    for (int32_t k = 0; k < onset_count; ++k) {
      const double angle = 2.0 * PI * indices[k] / period;
      real += weights[k] * cos(angle);
      imaginary += weights[k] * sin(angle);
      strong_total += weights[k];
    }
  }
  const double phase_strength = strong_total > 1e-12
      ? hypot(real, imaginary) / strong_total : 0.0;
  double phase = atan2(imaginary, real) * period / (2.0 * PI);
  phase = fmod(phase, period);
  if (phase < 0.0) phase += period;

  const double tolerance = fmax(1.0, period * 0.12);
  const double coverage = onset_grid_coverage(
      indices, weights, onset_count, period, phase, tolerance);
  double fill = 0.0;
  double contrast = 0.0;
  grid_fill_contrast(env, count, period, phase, &fill, &contrast);
  const double comb_normalized = comb_max > 1e-9
      ? clamp01_double(comb[lag] / comb_max) : 0.0;

  candidate.period_frames = period;
  candidate.bpm = 60.0 * fps / period;
  candidate.comb = comb_normalized;
  candidate.coverage = coverage;
  candidate.fill = fill;
  candidate.contrast = contrast;
  candidate.phase = clamp01_double(phase_strength);
  // Coverage is the discriminator: it is the share of measured onset energy a
  // grid actually explains, so a bar-level grid that catches only the backbeat
  // (every second kick) can no longer win on a strong 2-beat autocorrelation
  // peak and perfect fill. Fill and contrast stay as guards against grids
  // whose lines are mostly empty or whose "off-beat" is as loud as the beat,
  // and the autocorrelation comb is now only a tie-break between levels that
  // explain the onsets equally well.
  candidate.score =
      0.10 * candidate.comb +
      0.45 * candidate.coverage +
      0.25 * candidate.fill +
      0.08 * candidate.contrast +
      0.12 * candidate.phase;
  // A weak, wide prior only breaks ties between interpretations that the
  // musical evidence genuinely cannot separate (e.g. a bare click train).
  const double prior_ratio =
      log2_double(candidate.bpm / METRICAL_PRIOR_CENTER) /
      METRICAL_PRIOR_LOG2_WIDTH;
  candidate.score *= 0.85 + 0.15 * exp(-0.5 * prior_ratio * prior_ratio);
  return candidate;
}

static void add_metrical_lag(int32_t lag, int32_t lag_min, int32_t lag_max,
                             int32_t* lags, int32_t* count,
                             int32_t capacity) {
  if (lags == NULL || count == NULL || lag < lag_min || lag > lag_max) return;
  for (int32_t i = 0; i < *count; ++i) {
    if (abs(lags[i] - lag) <= 1) return;
  }
  if (*count >= capacity) return;
  lags[(*count)++] = lag;
}

static double refine_tempo_phase_coherence(const float* odf, int32_t count,
                                           double fps, double initial_bpm) {
  if (odf == NULL || count < 8 || !isfinite(fps) || fps <= 0.0 ||
      !isfinite(initial_bpm) || initial_bpm <= 0.0) {
    return initial_bpm;
  }
  const double center_period = fps * 60.0 / initial_bpm;
  if (!isfinite(center_period) || center_period < 2.0) return initial_bpm;

  double mean = 0.0;
  for (int32_t i = 0; i < count; ++i) mean += odf[i];
  mean /= count;
  int32_t peak_count = 0;
  for (int32_t i = 1; i < count - 1; ++i) {
    if (odf[i] > odf[i - 1] && odf[i] >= odf[i + 1] && odf[i] > mean) {
      ++peak_count;
    }
  }
  if (peak_count < 8) return initial_bpm;

  int32_t* indices = (int32_t*)malloc((size_t)peak_count * sizeof(int32_t));
  double* weights = (double*)malloc((size_t)peak_count * sizeof(double));
  if (indices == NULL || weights == NULL) {
    free(indices);
    free(weights);
    return initial_bpm;
  }
  int32_t used = 0;
  for (int32_t i = 1; i < count - 1 && used < peak_count; ++i) {
    const double value = odf[i];
    if (value > odf[i - 1] && value >= odf[i + 1] && value > mean) {
      indices[used] = i;
      weights[used] = value - mean;
      ++used;
    }
  }

  const double initial_coherence = onset_phase_coherence(
      indices, weights, used, center_period);
  const double search = 1.0;
  const double step = 0.01;
  const double begin = fmax(2.0, center_period - search);
  const double end = center_period + search;
  double best_period = center_period;
  double best_coherence = -1.0;
  for (double period = begin; period <= end + 1e-9; period += step) {
    const double coherence = onset_phase_coherence(
        indices, weights, used, period);
    if (coherence > best_coherence) {
      best_coherence = coherence;
      best_period = period;
    }
  }
  free(indices);
  free(weights);
  if (!isfinite(best_period) || best_coherence < 0.12 ||
      best_coherence <= initial_coherence + 1e-4) {
    return initial_bpm;
  }
  return 60.0 * fps / best_period;
}

static TempoEstimate estimate_tempo_window(const float* odf, int32_t count,
                                           int32_t working_rate, double fps) {
  TempoEstimate result = {NAN, NAN, 0.0, 0};
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

  double sum_score = 0.0;
  double min_score = DBL_MAX;
  double max_score = -DBL_MAX;
  int32_t comb_best_lag = -1;
  double comb_best = -DBL_MAX;
  for (int32_t lag = lag_min; lag <= lag_max; ++lag) {
    const double score = scores[lag] +
        0.5 * lag_score(scores, lag * 2, lag_max) +
        0.25 * lag_score(scores, lag * 3, lag_max) +
        0.125 * lag_score(scores, lag * 4, lag_max);
    comb[lag] = score;
    sum_score += score;
    if (score < min_score) min_score = score;
    if (score > max_score) max_score = score;
    if (score > comb_best) {
      comb_best = score;
      comb_best_lag = lag;
    }
  }
  (void)sum_score;
  (void)min_score;
  if (comb_best_lag <= 0) {
    free(env);
    free(scores);
    free(comb);
    return result;
  }

  // Metrical-level hypotheses. Every integer multiple of the true beat period
  // correlates equally, so autocorrelation alone cannot choose between P, P/2
  // and 2P: the old code resolved that with a fixed 115 BPM Gaussian and the
  // result was 2x at 60-87, 1/2x at 180-200 and 2/3x at 170-190. Enumerate the
  // plausible levels, then arbitrate with onset evidence.
  int32_t candidate_lags[40];
  int32_t candidate_lag_count = 0;
  for (int32_t lag = lag_min + 1; lag < lag_max; ++lag) {
    if (comb[lag] < comb[lag - 1] || comb[lag] < comb[lag + 1]) continue;
    if (comb[lag] < 0.45 * comb_best) continue;
    add_metrical_lag(lag, lag_min, lag_max, candidate_lags,
                     &candidate_lag_count, 40);
  }
  add_metrical_lag(comb_best_lag, lag_min, lag_max, candidate_lags,
                   &candidate_lag_count, 40);
  add_metrical_lag(comb_best_lag / 2, lag_min, lag_max, candidate_lags,
                   &candidate_lag_count, 40);
  add_metrical_lag(comb_best_lag * 2, lag_min, lag_max, candidate_lags,
                   &candidate_lag_count, 40);
  add_metrical_lag((comb_best_lag * 2) / 3, lag_min, lag_max, candidate_lags,
                   &candidate_lag_count, 40);
  add_metrical_lag((comb_best_lag * 3) / 2, lag_min, lag_max, candidate_lags,
                   &candidate_lag_count, 40);
  if (candidate_lag_count <= 0) {
    free(env);
    free(scores);
    free(comb);
    return result;
  }

  double env_mean = 0.0;
  for (int32_t i = 0; i < count; ++i) env_mean += odf[i];
  env_mean /= count;
  const int32_t onset_capacity = count;
  double* onset_indices =
      (double*)malloc((size_t)onset_capacity * sizeof(double));
  double* onset_weights =
      (double*)malloc((size_t)onset_capacity * sizeof(double));
  if (onset_indices == NULL || onset_weights == NULL) {
    free(env);
    free(scores);
    free(comb);
    free(onset_indices);
    free(onset_weights);
    return result;
  }
  const int32_t onset_count = collect_onset_peaks(
      odf, count, env_mean, onset_indices, onset_weights, onset_capacity);
  if (onset_count < 8) {
    free(env);
    free(scores);
    free(comb);
    free(onset_indices);
    free(onset_weights);
    return result;
  }

  MetricalCandidate candidates[40];
  MetricalCandidate best;
  MetricalCandidate second;
  memset(&best, 0, sizeof(best));
  memset(&second, 0, sizeof(second));
  second.score = -DBL_MAX;
  for (int32_t i = 0; i < candidate_lag_count; ++i) {
    candidates[i] = evaluate_metrical_candidate(
        candidate_lags[i], comb, lag_min, lag_max, comb_best, odf, count,
        fps, onset_indices, onset_weights, onset_count);
    if (!isfinite(candidates[i].score) || candidates[i].period_frames <= 0.0) {
      continue;
    }
    if (candidates[i].score > best.score) {
      second = best;
      best = candidates[i];
    } else if (candidates[i].score > second.score) {
      second = candidates[i];
    }
#ifdef AUTOMIX_DEBUG_METRICAL
    fprintf(stderr, "cand lag=%d bpm=%.2f score=%.3f comb=%.3f cov=%.3f fill=%.3f con=%.3f phase=%.3f\n",
            candidate_lags[i], candidates[i].bpm, candidates[i].score,
            candidates[i].comb, candidates[i].coverage, candidates[i].fill,
            candidates[i].contrast, candidates[i].phase);
#endif
  }
  if (best.period_frames <= 0.0) {
    free(env);
    free(scores);
    free(comb);
    free(onset_indices);
    free(onset_weights);
    return result;
  }

  // Publish the runner-up interpretation for the downstream octave-recovery
  // path. Prefer a genuine half/double, but fall back to any distinct level.
  double alternate_bpm = NAN;
  double alternate_score = -DBL_MAX;
  for (int32_t i = 0; i < candidate_lag_count; ++i) {
    const double ratio = candidates[i].period_frames / best.period_frames;
    if (!isfinite(ratio) || fabs(log2_double(ratio)) <= 0.05) continue;
    const int is_octave = ratio > 0.45 && ratio < 0.55;
    const int is_double = ratio > 1.8 && ratio < 2.2;
    if (!is_octave && !is_double) continue;
    if (candidates[i].score > alternate_score) {
      alternate_score = candidates[i].score;
      alternate_bpm = candidates[i].bpm;
    }
  }
  if (!isfinite(alternate_bpm)) {
    for (int32_t i = 0; i < candidate_lag_count; ++i) {
      const double ratio = candidates[i].period_frames / best.period_frames;
      if (!isfinite(ratio) || fabs(log2_double(ratio)) <= 0.05) continue;
      if (candidates[i].score > alternate_score) {
        alternate_score = candidates[i].score;
        alternate_bpm = candidates[i].bpm;
      }
    }
  }

  // Autocorrelation is sampled at integer lags, but the beat period is rarely
  // an integer number of FFT hops. The candidate already carries a parabolic
  // sub-frame period; the phase-coherence refinement then only trims within
  // one frame and cannot jump to another metrical level.
  double refined_lag = best.period_frames;
  double bpm = 60.0 * fps / refined_lag;
  const double coherent_bpm = refine_tempo_phase_coherence(
      odf, count, fps, bpm);
  if (isfinite(coherent_bpm) && coherent_bpm > 0.0) {
    const double coherent_lag = 60.0 * fps / coherent_bpm;
    if (fabs(coherent_lag - refined_lag) <= 1.01) {
      bpm = coherent_bpm;
      refined_lag = coherent_lag;
    }
  }
  if (bpm < BPM_MIN) bpm = BPM_MIN;
  if (bpm > BPM_MAX) bpm = BPM_MAX;

  int32_t best_lag = (int32_t)llround(refined_lag);
  if (best_lag < lag_min) best_lag = lag_min;
  if (best_lag > lag_max) best_lag = lag_max;
  // A fractional beat period (e.g. 125 BPM = 21.5 frames) rounds to an integer
  // lag that can sit on the shoulder of the comb peak. Read the evidence from
  // the best integer sample within one frame instead, otherwise a correct
  // tempo can publish confidence 0.00 just because of rounding.
  double comb_evidence = comb[best_lag];
  double score_evidence = scores[best_lag];
  for (int32_t delta = -1; delta <= 1; ++delta) {
    const int32_t index = best_lag + delta;
    if (index < lag_min || index > lag_max) continue;
    if (comb[index] > comb_evidence) comb_evidence = comb[index];
    if (scores[index] > score_evidence) score_evidence = scores[index];
  }
  const double mean_score = sum_score / (lag_max - lag_min + 1);
  const double spread = fmax(max_score - min_score, 1e-12);
  const double periodicity = fmax(0.0, score_evidence / energy0 * count);
  const double prominence = fmin(1.0, fmax(0.0,
      (comb_evidence - mean_score) / spread));
  const double metrical_margin = best.score > 1e-9
      ? clamp01_double((best.score - second.score) / best.score / 0.06)
      : 0.0;
  const double base_confidence = fmin(1.0, fmax(0.0,
      0.55 * prominence + 0.45 * fmin(1.0, fmax(0.0, periodicity))));
  result.bpm = bpm;
  result.alternate_bpm = alternate_bpm;
  result.confidence = clamp01_double(
      base_confidence * (0.65 + 0.35 * metrical_margin));
  result.valid = 1;
  free(env);
  free(scores);
  free(comb);
  free(onset_indices);
  free(onset_weights);
  return result;
}

static double beat_period_ms(double bpm) { return 60000.0 / bpm; }

// Whole-window autocorrelation mixes density regimes: a quiet intro carrying
// only off-beat hats and a full chorus can make the bar-level pulse win the
// global vote even when every local quarter agrees on the beat. The quarter
// estimates already exist for the tempo curve, so use them as an independent
// vote: when three or more quarters agree within 4% on a level that differs
// from the whole-window estimate, publish the local consensus. This is
// symmetric (it can slow a wrongly-fast whole-window result too) and never
// fires on uniform material, where the quarters already agree with the whole.
static TempoEstimate estimate_tempo(const float* odf, int32_t count,
                                    int32_t working_rate, double fps) {
  TempoEstimate whole =
      estimate_tempo_window(odf, count, working_rate, fps);
  if (!whole.valid || odf == NULL || count <= 0 || working_rate <= 0 ||
      !isfinite(fps) || fps <= 0.0) {
    return whole;
  }
  // A quarter must contain at least four seconds for its own estimate to be
  // independent of the whole window; shorter files keep the direct result.
  const int32_t min_quarter = (int32_t)round(4.0 * fps);
  const int32_t quarter = count / 4;
  if (min_quarter <= 0 || quarter < min_quarter) return whole;
  double bpms[4];
  double confidences[4];
  int32_t votes = 0;
  for (int32_t index = 0; index < 4; ++index) {
    const TempoEstimate local = estimate_tempo_window(
        odf + (size_t)index * (size_t)quarter, quarter, working_rate, fps);
    if (!local.valid || !isfinite(local.bpm) || local.confidence < 0.35) {
      continue;
    }
    bpms[votes] = local.bpm;
    confidences[votes] = local.confidence;
    ++votes;
  }
  if (votes < 3) return whole;
  for (int32_t i = 1; i < votes; ++i) {
    const double value = bpms[i];
    const double confidence = confidences[i];
    int32_t j = i - 1;
    while (j >= 0 && bpms[j] > value) {
      bpms[j + 1] = bpms[j];
      confidences[j + 1] = confidences[j];
      --j;
    }
    bpms[j + 1] = value;
    confidences[j + 1] = confidence;
  }
  const double median = bpms[votes / 2];
  if (!isfinite(median) || median <= 0.0) return whole;
  for (int32_t i = 0; i < votes; ++i) {
    if (fabs(bpms[i] - median) / median > 0.04) return whole;
  }
  const double ratio = median / whole.bpm;
  if (!isfinite(ratio) || (ratio > 0.75 && ratio < 1.25)) return whole;
  TempoEstimate consensus = whole;
  consensus.bpm = median;
  consensus.alternate_bpm = whole.bpm;
  consensus.confidence = fmin(whole.confidence, confidences[votes / 2]);
  return consensus;
}

static double estimate_beat_phase_ms(const float* odf, int32_t count,
                                     int32_t working_rate, double bpm) {
  if (!isfinite(bpm) || bpm < BPM_MIN || bpm > BPM_MAX || working_rate <= 0) {
    return NAN;
  }
  const double fps = (double)working_rate / HOP_SIZE;
  const double beat_frames = fps * 60.0 / bpm;
  if (!isfinite(beat_frames) || beat_frames < 2.0 ||
      (double)count < beat_frames * 4.0) {
    return NAN;
  }
  const int32_t bins = (int32_t)ceil(beat_frames);
  if (bins < 2) return NAN;

  double mean = 0.0;
  for (int32_t i = 0; i < count; ++i) mean += odf[i];
  mean /= count;
  double* scores = (double*)calloc((size_t)bins, sizeof(double));
  double* smoothed = (double*)calloc((size_t)bins, sizeof(double));
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
      // The beat period is fractional, so fold peaks modulo the real period
      // and scatter each into the two nearest bins. The old integer-period
      // histogram smeared a 127.3 BPM grid by more than a frame over 32 s and
      // often collapsed the phase to NaN.
      const double phase_frames = fmod((double)i, beat_frames);
      const double bin_position = phase_frames / beat_frames * (double)bins;
      int32_t bin = (int32_t)floor(bin_position);
      if (bin < 0) bin = 0;
      bin %= bins;
      const double fraction = bin_position - floor(bin_position);
      scores[bin] += weight * (1.0 - fraction);
      scores[(bin + 1) % bins] += weight * fraction;
      peak_energy += weight;
      ++peak_count;
    }
  }
  if (peak_count < 8 || peak_energy <= 1e-9) {
    free(scores);
    free(smoothed);
    return NAN;
  }

  for (int32_t phase = 0; phase < bins; ++phase) {
    const int32_t previous = (phase - 1 + bins) % bins;
    const int32_t next = (phase + 1) % bins;
    smoothed[phase] = scores[previous] * 0.25 + scores[phase] * 0.5 +
                      scores[next] * 0.25;
  }
  int32_t best_phase = 0;
  double best_score = -DBL_MAX;
  double second_score = -DBL_MAX;
  for (int32_t phase = 0; phase < bins; ++phase) {
    const double score = smoothed[phase];
    if (score > best_score) {
      second_score = best_score;
      best_score = score;
      best_phase = phase;
    } else if (score > second_score) {
      second_score = score;
    }
  }
  const double average = peak_energy / bins;
  double phase = NAN;
  if (best_score > 0.0 && best_score >= average * 1.03 &&
      !(second_score > 0.0 && best_score / second_score < 1.005)) {
    // Refine the winning bin to a fraction of a bin before converting back to
    // frames. This removes the 23 ms hop quantization from the published
    // phase while keeping the value folded into one beat period.
    double refined_bin = (double)best_phase;
    const double left = smoothed[(best_phase - 1 + bins) % bins];
    const double right = smoothed[(best_phase + 1) % bins];
    const double denominator = left - 2.0 * best_score + right;
    if (isfinite(denominator) && denominator < -1e-18) {
      double offset = 0.5 * (left - right) / denominator;
      if (offset < -0.5) offset = -0.5;
      if (offset > 0.5) offset = 0.5;
      if (isfinite(offset)) refined_bin += offset;
    }
    double phase_frames = refined_bin * beat_frames / (double)bins;
    phase_frames = fmod(phase_frames, beat_frames);
    if (phase_frames < 0.0) phase_frames += beat_frames;
    const double period_ms = beat_period_ms(bpm);
    phase = fmod(phase_frames * (double)HOP_SIZE * 1000.0 / working_rate +
                     (double)ODF_TIMESTAMP_OFFSET_SAMPLES * 1000.0 /
                         working_rate,
                 period_ms);
    if (phase < 0.0) phase += period_ms;
  }
  free(scores);
  free(smoothed);
  return phase;
}

typedef struct {
  double b0;
  double b1;
  double b2;
  double a1;
  double a2;
} NarBiquad;

// ITU-R BS.1770 K-weighting: a high shelf followed by the RLB high-pass. The
// coefficients are re-derived for the actual sample rate instead of being
// copied from a 48 kHz table, so the analyzer's 22.05/24 kHz decimation does
// not shift the perceptual weighting.
static void design_kweighting(NarBiquad* shelf, NarBiquad* high_pass,
                              int32_t sample_rate) {
  if (shelf == NULL || high_pass == NULL || sample_rate <= 0) return;

  const double shelf_f0 = 1681.974450955533;
  const double shelf_gain_db = 3.999843853973347;
  const double shelf_q = 0.7071752369554196;
  const double shelf_k = tan(PI * shelf_f0 / (double)sample_rate);
  const double vh = pow(10.0, shelf_gain_db / 20.0);
  const double vb = pow(vh, 0.4996667741545416);
  const double shelf_a0 = 1.0 + shelf_k / shelf_q + shelf_k * shelf_k;
  shelf->b0 = (vh + vb * shelf_k / shelf_q + shelf_k * shelf_k) / shelf_a0;
  shelf->b1 = 2.0 * (shelf_k * shelf_k - vh) / shelf_a0;
  shelf->b2 = (vh - vb * shelf_k / shelf_q + shelf_k * shelf_k) / shelf_a0;
  shelf->a1 = 2.0 * (shelf_k * shelf_k - 1.0) / shelf_a0;
  shelf->a2 = (1.0 - shelf_k / shelf_q + shelf_k * shelf_k) / shelf_a0;

  const double high_pass_f0 = 38.13547087602444;
  const double high_pass_q = 0.5003270373238773;
  const double high_pass_k =
      tan(PI * high_pass_f0 / (double)sample_rate);
  const double high_pass_a0 =
      1.0 + high_pass_k / high_pass_q + high_pass_k * high_pass_k;
  high_pass->b0 = 1.0;
  high_pass->b1 = -2.0;
  high_pass->b2 = 1.0;
  high_pass->a1 = 2.0 * (high_pass_k * high_pass_k - 1.0) / high_pass_a0;
  high_pass->a2 =
      (1.0 - high_pass_k / high_pass_q + high_pass_k * high_pass_k) /
      high_pass_a0;
}

static double biquad_process(const NarBiquad* filter, double input,
                             double* z1, double* z2) {
  const double output = filter->b0 * input + *z1;
  *z1 = filter->b1 * input - filter->a1 * output + *z2;
  *z2 = filter->b2 * input - filter->a2 * output;
  return output;
}

// Mono short-term loudness over a bounded edge. BS.1770 defines 400 ms blocks
// with 100 ms hops and a -70 LUFS absolute gate; the optional -10 LU relative
// gate is applied after the first pass. Mono uses a channel weight of 1.0,
// matching the analyzer's single-channel feature pipeline. Returns NAN when
// there is not enough material or no block survives gating.
static double estimate_edge_lufs(const float* samples, int32_t count,
                                 int32_t sample_rate) {
  if (samples == NULL || count <= 0 || sample_rate <= 0) return NAN;
  const int32_t block = (int32_t)llround(0.400 * sample_rate);
  const int32_t hop = (int32_t)llround(0.100 * sample_rate);
  if (block < 1 || hop < 1 || count < block) return NAN;

  NarBiquad shelf = {0.0, 0.0, 0.0, 0.0, 0.0};
  NarBiquad high_pass = {0.0, 0.0, 0.0, 0.0, 0.0};
  design_kweighting(&shelf, &high_pass, sample_rate);

  double* ring = (double*)calloc((size_t)block, sizeof(double));
  if (ring == NULL) return NAN;
  double blocks[512];
  int32_t block_count = 0;
  double running = 0.0;
  double shelf_z1 = 0.0, shelf_z2 = 0.0;
  double high_pass_z1 = 0.0, high_pass_z2 = 0.0;
  int32_t ring_position = 0;
  int32_t seen = 0;
  for (int32_t i = 0; i < count; ++i) {
    const double input = isfinite(samples[i]) ? (double)samples[i] : 0.0;
    const double weighted = biquad_process(
        &high_pass,
        biquad_process(&shelf, input, &shelf_z1, &shelf_z2),
        &high_pass_z1, &high_pass_z2);
    const double square = weighted * weighted;
    const double old = ring[ring_position];
    ring[ring_position] = square;
    running += square - old;
    ring_position++;
    if (ring_position == block) ring_position = 0;
    ++seen;
    if (seen >= block && ((seen - block) % hop) == 0 &&
        block_count < (int32_t)(sizeof(blocks) / sizeof(blocks[0]))) {
      blocks[block_count++] = running / (double)block;
    }
  }
  free(ring);
  if (block_count == 0) return NAN;

  double sum = 0.0;
  int32_t kept = 0;
  for (int32_t i = 0; i < block_count; ++i) {
    const double loudness =
        -0.691 + 10.0 * log10(fmax(blocks[i], 1e-20));
    if (loudness > -70.0) {
      sum += blocks[i];
      ++kept;
    }
  }
  if (kept == 0 || sum <= 0.0) return NAN;
  const double absolute_mean = sum / (double)kept;
  const double relative_gate =
      -0.691 + 10.0 * log10(absolute_mean) - 10.0;
  double gated_sum = 0.0;
  int32_t gated = 0;
  for (int32_t i = 0; i < block_count; ++i) {
    const double loudness =
        -0.691 + 10.0 * log10(fmax(blocks[i], 1e-20));
    if (loudness > -70.0 && loudness > relative_gate) {
      gated_sum += blocks[i];
      ++gated;
    }
  }
  if (gated == 0 || gated_sum <= 0.0) {
    return -0.691 + 10.0 * log10(absolute_mean);
  }
  return -0.691 + 10.0 * log10(gated_sum / (double)gated);
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

// Confident phrase grid: [phase_ms] is the start of an [meter]-beat bar that
// begins a four-bar phrase. The grid is evaluated in fractional milliseconds,
// never on a rounded integer frame period: at 120 BPM a 22-frame rounding
// stretches a 16-beat phrase from 8.00 s to 8.17 s, which drifts more than an
// eighth note across a four-bar loop and either hides a real accent or invents
// a phase from window-edge truncation (regression: 120 BPM four-bar loop
// published a spurious 6.2 s phase).
typedef struct {
  double phase_ms;
  int32_t meter;
  int32_t meter_confident;
  int32_t valid;
} NarPhraseEstimate;

#define AUTOMIX_MAX_BEATS 512

// Track-level section novelty is measured on 2 s chroma blocks: a section
// boundary is a change point at that scale, not the per-frame chord change
// used for bar evidence. 128 blocks cover a 256 s window, well past the
// bounded 120 s analysis window this analyzer is called with.
#define AUTOMIX_MAX_SECTION_BLOCKS 128
#define AUTOMIX_SECTION_BLOCK_SECONDS 2.0

// Score of the strongest 2 s-block chroma change relative to the rest of the
// window. A section boundary is only published when one change point clearly
// dominates the surrounding log of small changes: a steady arrangement has no
// boundary, a verse→chorus transition has exactly one.
static double estimate_section_boundary_ms(const float* novelty,
                                           int32_t count,
                                           double block_ms,
                                           double* confidence) {
  *confidence = 0.0;
  if (novelty == NULL || count < 8 || !isfinite(block_ms) ||
      block_ms <= 0.0) {
    return NAN;
  }
  const int32_t usable = count < AUTOMIX_MAX_SECTION_BLOCKS
      ? count
      : AUTOMIX_MAX_SECTION_BLOCKS;

  // De-trend every candidate against its own neighbourhood. A chord change
  // every bar or two produces a chroma spike at a *regular* period; against
  // the global median those spikes raised both the baseline and the scale and
  // masked the one-off arrangement change (a real 32 s verse→chorus boundary
  // scored 0.658 while the recurring chord spikes scored 0.34–0.56). The
  // local median over ±16 s, excluding the candidate and its neighbours, is
  // the chord-change rate, so only a change *faster* than that rate survives.
  const int32_t radius = 8;
  float residual[AUTOMIX_MAX_SECTION_BLOCKS] = {0.0f};
  float residual_sorted[AUTOMIX_MAX_SECTION_BLOCKS];
  int32_t residual_count = 0;
  for (int32_t i = 2; i < usable - 2; ++i) {
    float local[2 * 8 + 1];
    int32_t local_count = 0;
    for (int32_t j = i - radius; j <= i + radius; ++j) {
      if (j < 0 || j >= usable) continue;
      if (j >= i - 1 && j <= i + 1) continue;
      local[local_count++] = novelty[j];
    }
    if (local_count < 4) continue;
    for (int32_t j = 1; j < local_count; ++j) {
      const float value = local[j];
      int32_t k = j - 1;
      while (k >= 0 && local[k] > value) {
        local[k + 1] = local[k];
        --k;
      }
      local[k + 1] = value;
    }
    const double baseline = (double)local[local_count / 2];
    const double delta = (double)novelty[i] - baseline;
    residual[i] = delta > 0.0 ? (float)delta : 0.0f;
    residual_sorted[residual_count++] = residual[i];
  }
  if (residual_count < 4) return NAN;
  for (int32_t i = 1; i < residual_count; ++i) {
    const float value = residual_sorted[i];
    int32_t j = i - 1;
    while (j >= 0 && residual_sorted[j] > value) {
      residual_sorted[j + 1] = residual_sorted[j];
      --j;
    }
    residual_sorted[j + 1] = value;
  }
  const double median = (double)residual_sorted[residual_count / 2];
  double deviation_sum = 0.0;
  for (int32_t i = 0; i < residual_count; ++i) {
    deviation_sum += fabs((double)residual_sorted[i] - median);
  }
  const double scale = fmax(1e-4, deviation_sum / (double)residual_count);

  // Do not accept a boundary in the first or last two blocks: a window edge
  // truncates the block mean, so an "edge change" is an analysis artefact.
  int32_t best_index = -1;
  double best = -1.0;
  for (int32_t i = 2; i < usable - 2; ++i) {
    // A section change still has to be a visible chroma change, not a bare
    // outlier in a nearly static window.
    if (novelty[i] < 0.15f) continue;
    const double value = (double)residual[i];
    if (value > best) {
      best = value;
      best_index = i;
    }
  }
  if (best_index < 0 || best < 0.06) return NAN;
  double second = 0.0;
  for (int32_t i = 2; i < usable - 2; ++i) {
    if (i >= best_index - 2 && i <= best_index + 2) continue;
    const double value = (double)residual[i];
    if (value > second) second = value;
  }
  const double z = (best - median) / scale;
  const double separation = best > 1e-9 ? fmin(1.0, (best - second) / best) : 0.0;
  if (z < 3.0 || separation < 0.20) return NAN;
  *confidence = fmin(1.0, fmax(0.0,
      fmin(1.0, (z - 2.5) / 3.0) * fmin(1.0, separation / 0.35)));
  // Entry i compares block i with block i + 1, so it sits at the *end* of
  // block i. The cue marks the first frame of the new section, i.e. one block
  // later than the entry index.
  return (double)(best_index + 1) * block_ms;
}

static NarPhraseEstimate estimate_phrase_grid(const float* rms_frames,
                                              const float* chroma_novelty,
                                              int32_t frame_count,
                                              double working_rate, double fps,
                                              double beat_ms,
                                              double beat_phase_ms) {
  NarPhraseEstimate result = {NAN, 4, 0, 0};
  const double window_ms =
      (double)frame_count * HOP_SIZE * 1000.0 / working_rate;
  const double offset_ms =
      (double)ODF_TIMESTAMP_OFFSET_SAMPLES * 1000.0 / working_rate;
  int32_t beat_count = (int32_t)floor(window_ms / beat_ms);
  if (beat_count > AUTOMIX_MAX_BEATS) beat_count = AUTOMIX_MAX_BEATS;
  if (beat_count < 8) return result;

  // One evidence value per beat, on the fractional beat grid. Using the whole
  // window (not a modulo phrase) lets metre be decided independently of the
  // phrase phase: a 4/4 loop with an accent every fourth beat must not be able
  // to masquerade as a 3/4 loop whose accents happen to fall every four beats.
  double beat_power[AUTOMIX_MAX_BEATS] = {0.0};
  double beat_novelty[AUTOMIX_MAX_BEATS] = {0.0};
  double power_max = 0.0;
  double novelty_max = 0.0;
  const double half_beat_ms = beat_ms * 0.5;
  for (int32_t beat = 0; beat < beat_count; ++beat) {
    double time_ms = fmod(beat_phase_ms + (double)beat * beat_ms, beat_ms);
    if (time_ms < 0.0) time_ms += beat_ms;
    time_ms += (double)beat * beat_ms;
    if (time_ms >= window_ms) break;
    // Score the whole beat interval by its mean frame power, not by one
    // spectral-flux frame. A transient's flux is spread across about four
    // frames and its single-frame height depends on where the onset falls
    // inside the Hann window; integrating flux still let identical bars differ
    // by >80 % from frame alignment alone (measured at 128 BPM). Mean power in
    // [t - beat/2, t + beat/2] is the energy the listener actually hears on
    // that beat and is alignment-insensitive.
    int32_t lo = (int32_t)llround(
        (time_ms - half_beat_ms - offset_ms) * fps / 1000.0);
    int32_t hi = (int32_t)llround(
        (time_ms + half_beat_ms - offset_ms) * fps / 1000.0);
    if (lo < 0) lo = 0;
    if (hi >= frame_count) hi = frame_count - 1;
    if (lo > hi) break;
    double power = 0.0;
    double novelty = 0.0;
    for (int32_t index = lo; index <= hi; ++index) {
      power += pow(10.0, (double)rms_frames[index] / 10.0);
      novelty += (double)chroma_novelty[index];
    }
    beat_power[beat] = power / (double)(hi - lo + 1);
    beat_novelty[beat] = novelty / (double)(hi - lo + 1);
    if (beat_power[beat] > power_max) power_max = beat_power[beat];
    if (beat_novelty[beat] > novelty_max) novelty_max = beat_novelty[beat];
  }

  // Metre is a hypothesis, not a constant: 4/4 dominates the target library,
  // but 3/4 and 6/8 material exists and a hard-wired four-beat bar makes the
  // published downbeat drift by one beat per bar on those tracks. Score each
  // metre by how strongly the beat accents line up with one bar position; the
  // winner needs a clear margin, otherwise 4/4 (the prior) is retained.
  // A compound 6/8 track at a dotted-quarter pulse has two beats per bar, so
  // 2 is a hypothesis too. It is not publishable on a backbeat alone (4/4 with
  // a snare on 2 and 4 looks identical at the pulse level); the accent margin
  // gate below keeps 4/4 as the prior unless one position clearly dominates.
  static const int32_t kMeters[] = {4, 3, 6, 2};
  int32_t meter = 4;
  double meter_score = 0.0;
  for (size_t meter_index = 0;
       meter_index < sizeof(kMeters) / sizeof(kMeters[0]); ++meter_index) {
    const int32_t candidate_meter = kMeters[meter_index];
    if (beat_count < candidate_meter * 4) continue;
    double position_sum[6] = {0.0};
    int32_t position_count[6] = {0};
    for (int32_t beat = 0; beat < beat_count; ++beat) {
      const int32_t position = beat % candidate_meter;
      const double power =
          power_max > 1e-12 ? beat_power[beat] / power_max : 0.0;
      const double novelty =
          novelty_max > 1e-12 ? beat_novelty[beat] / novelty_max : 0.0;
      position_sum[position] += power + 0.5 * novelty;
      position_count[position]++;
    }
    double best = -1.0;
    double second = -1.0;
    for (int32_t position = 0; position < candidate_meter; ++position) {
      if (position_count[position] <= 0) continue;
      const double value = position_sum[position] / position_count[position];
      if (value > best) {
        second = best;
        best = value;
      } else if (value > second) {
        second = value;
      }
    }
    if (second < 0.0) second = 0.0;
    // Contrast is measured against the actual bar length. An accent every
    // fourth beat therefore maximises the 4-beat contrast and only partially
    // fills 3- or 6-beat positions, so the right metre wins on evidence.
    const double prior = candidate_meter == 4 ? 1.0 : 0.88;
    const double score = (best - second) * prior;
    if (score > meter_score + 1e-6) {
      meter_score = score;
      meter = candidate_meter;
    }
  }
  // A bar accent needs at least a fourth of the strongest beat interval and a
  // stable position across at least four bars; a flat loop keeps 4/4 as the
  // default but publishes no metre confidence. A two-beat bar needs more
  // evidence than that: 4/4 with a strong kick on 1 and 3 produces a two-beat
  // accent period, and a false 2 would halve every phrase grid (measured on a
  // real 4/4 track that scored just over the generic gate).
  const double meter_gate = meter == 2 ? 0.20 : 0.12;
  if (meter_score >= meter_gate) {
    result.meter = meter;
    result.meter_confident = 1;
  }

  // A flat four-on-the-floor mix has no accent contrast (a kick on every
  // beat), but it often changes chord on the bar line. Even when metre 4 is
  // confident, the phrase path rejects bar-period novelty (it demands
  // phrase-period repetition), so a clear bar novelty peak is published as a
  // bar downbeat. If a genuine phrase phase is found below, it overrides
  // this. The phase is modulo the bar, which is all downstream grids consume.
  if ((meter == 4 || (meter == 2 && !result.meter_confident)) &&
      beat_count >= 32 && novelty_max > 1e-12) {
    double bar_novelty[4] = {0.0, 0.0, 0.0, 0.0};
    int32_t bar_counts[4] = {0, 0, 0, 0};
    for (int32_t beat = 0; beat < beat_count; ++beat) {
      const int32_t position = beat % 4;
      bar_novelty[position] += beat_novelty[beat] / novelty_max;
      bar_counts[position]++;
    }
    int32_t best_position = -1;
    double best = -1.0;
    double second = -1.0;
    for (int32_t position = 0; position < 4; ++position) {
      if (bar_counts[position] <= 0) continue;
      const double value = bar_novelty[position] / bar_counts[position];
      if (value > best) {
        second = best;
        best = value;
        best_position = position;
      } else if (value > second) {
        second = value;
      }
    }
    if (second < 0.0) second = 0.0;
    const double contrast = best > 1e-9 ? (best - second) / best : 0.0;
    if (best_position >= 0 && best >= 0.35 && contrast >= 0.30) {
      const double bar_ms = beat_ms * 4.0;
      double phase = fmod(beat_phase_ms + (double)best_position * beat_ms,
                          bar_ms);
      if (phase < 0.0) phase += bar_ms;
      result.phase_ms = phase;
      result.valid = 1;
    }
  }

  const int32_t phrase_beats = meter * 4;
  if (beat_count < phrase_beats * 3) return result;
  double phase_power[24] = {0.0};
  double phase_novelty[24] = {0.0};
  int32_t phase_counts[24] = {0};
  for (int32_t beat = 0; beat < beat_count; ++beat) {
    const int32_t position = beat % phrase_beats;
    phase_power[position] += beat_power[beat];
    phase_novelty[position] += beat_novelty[beat];
    phase_counts[position]++;
  }
  for (int32_t position = 0; position < phrase_beats; ++position) {
    if (phase_counts[position] <= 0) continue;
    phase_power[position] /= phase_counts[position];
    phase_novelty[position] /= phase_counts[position];
  }
  // Only accept novelty as bar evidence when it repeats at the phrase period,
  // not at the bar period. A loop whose harmony changes on every bar is as
  // ambiguous as a flat loop and must keep the phrase unknown.
  int32_t best_novelty_beat = -1;
  double best_novelty_score = -1.0;
  for (int32_t position = 0; position < phrase_beats; ++position) {
    if (phase_counts[position] < 3) continue;
    if (phase_novelty[position] > best_novelty_score) {
      best_novelty_score = phase_novelty[position];
      best_novelty_beat = position;
    }
  }
  double other_bar_novelty_max = 0.0;
  if (best_novelty_beat >= 0) {
    for (int32_t delta = meter; delta < phrase_beats; delta += meter) {
      const int32_t other = (best_novelty_beat + delta) % phrase_beats;
      if (phase_counts[other] < 3) continue;
      if (phase_novelty[other] > other_bar_novelty_max) {
        other_bar_novelty_max = phase_novelty[other];
      }
    }
  }
  const double novelty_contrast = best_novelty_score > 1e-9
      ? (best_novelty_score - other_bar_novelty_max) / best_novelty_score
      : 0.0;
  const double novelty_weight = novelty_contrast >= 0.25 ? 1.25 : 0.0;
  double combined[24] = {0.0};
  for (int32_t position = 0; position < phrase_beats; ++position) {
    if (phase_counts[position] < 3) continue;
    const double power_term =
        power_max > 1e-12 ? phase_power[position] / power_max : 0.0;
    const double novelty_term =
        novelty_max > 1e-12 ? phase_novelty[position] / novelty_max : 0.0;
    combined[position] = power_term + novelty_weight * novelty_term;
  }

  int32_t best_phase_beat = -1;
  double best_score = -1.0;
  double second_score = -1.0;
  for (int32_t position = 0; position < phrase_beats; ++position) {
    if (phase_counts[position] < 3) continue;
    const double score = combined[position];
    if (score > best_score) {
      second_score = best_score;
      best_score = score;
      best_phase_beat = position;
    } else if (score > second_score) {
      second_score = score;
    }
  }

  // If repeated bars have no distinct phrase accent, phrase phase is
  // genuinely ambiguous. A win over the runner-up is not enough on its own:
  // when every bar carries the same accent the bar positions are musically
  // equivalent and frame-alignment noise alone can make one look >10 %
  // stronger (regression: a four-bar loop published a spurious 5.8 s phase).
  // A phrase start is only credible when it also beats the *other bar
  // positions* by a clear margin, i.e. when the accent itself has
  // phrase-period, not bar-period, repetition.
  int32_t bar_conflict = 0;
  if (best_phase_beat >= 0) {
    for (int32_t delta = meter; delta < phrase_beats; delta += meter) {
      const int32_t other = (best_phase_beat + delta) % phrase_beats;
      if (phase_counts[other] < 3) continue;
      if (combined[other] >= best_score * 0.90) bar_conflict = 1;
    }
  }
  const int32_t significant =
      best_phase_beat >= 0 && best_score > 1e-8 && !bar_conflict &&
      (second_score <= 1e-8 || best_score >= second_score * 1.12);
#ifdef AUTOMIX_DEBUG_PHRASE
  fprintf(stderr,
          "meter=%d meter_score=%.3f best=%d score=%.3f second=%.3f "
          "conflict=%d sig=%d\n",
          meter, meter_score, best_phase_beat, best_score, second_score,
          bar_conflict, significant);
#endif
  if (!significant) return result;
  const double phrase_ms = beat_ms * (double)phrase_beats;
  double phase = fmod(beat_phase_ms + (double)best_phase_beat * beat_ms,
                      phrase_ms);
  if (phase < 0.0) phase += phrase_ms;
  result.phase_ms = phase;
  result.meter = meter;
  result.meter_confident = 1;
  result.valid = 1;
  return result;
}

static int32_t analyze_impl(const float* mono, double center_ratio,
                            int32_t sample_count, int32_t sample_rate,
                            double* output, int32_t output_count) {
  if (mono == NULL || output == NULL ||
      output_count < NAR_AUTOMIX_ANALYSIS_VALUE_COUNT ||
      sample_rate <= 0 || sample_count < sample_rate) {
    return 0;
  }
  const double center_channel_ratio = isfinite(center_ratio)
      ? fmin(1.0, fmax(0.0, center_ratio)) : NAN;
  for (int i = 0; i < NAR_AUTOMIX_ANALYSIS_VALUE_COUNT; ++i) output[i] = NAN;
  output[1] = 0.0;
  output[4] = -1.0;
  output[5] = 0.0;
  output[6] = 0.0;
  output[10] = 0.0;
  // Confidence fields always obey their finite [0,1] contract, including
  // silence/invalid-content frames where no section analysis is possible.
  output[11] = NAN;
  output[12] = NAN;
  output[13] = NAN;
  output[14] = 0.0;
  output[15] = 0.0;
  output[16] = (double)NAR_AUTOMIX_STRUCTURE_UNKNOWN;
  output[17] = 0.0;
  output[18] = 0.0;
  output[19] = 0.0;
  output[20] = 0.0;

  const int32_t frame_count = (sample_count - FFT_SIZE) / HOP_SIZE + 1;
  if (frame_count < 8) return 0;

  float* hann = (float*)malloc(FFT_SIZE * sizeof(float));
  float* real = (float*)malloc(FFT_SIZE * sizeof(float));
  float* imaginary = (float*)calloc(FFT_SIZE, sizeof(float));
  float* previous_log_magnitude = (float*)calloc(FFT_BINS, sizeof(float));
  float* odf = (float*)calloc((size_t)frame_count, sizeof(float));
  // Frequency-weighted onset envelope for beat/bar phase. The full-band ODF
  // remains the tempo and onset-rate input; this one keeps hats from
  // competing with kicks for the beat phase.
  float* phase_odf = (float*)calloc((size_t)frame_count, sizeof(float));
  // Beat-band ODF (30-1500 Hz): kick and snare body only. Tempo candidates are
  // scored on this envelope so that a loud hi-hat subdivision cannot make the
  // faster level win just by explaining more total flux; phase still uses the
  // wider phase_odf above. Measured on three real tracks, the full-band
  // envelope published 175.5 / 200 BPM where a local tracker measured
  // 119.4 / 109.5, while this band published 117 / 101.
  float* beat_odf = (float*)calloc((size_t)frame_count, sizeof(float));
  // Chroma novelty per frame. Bar lines are marked by harmonic and textural
  // change far more reliably than by loudness on flat four-on-the-floor, so
  // the phrase grid scores change evidence alongside the energy accent.
  float* chroma_novelty = (float*)calloc((size_t)frame_count, sizeof(float));
  double previous_chroma[12] = {0.0};
  int has_previous_chroma = 0;
  // Track-level section novelty on 2 s chroma blocks (see
  // estimate_section_boundary_ms). Only the block means are kept, so the extra
  // memory is a few hundred bytes regardless of window length.
  float* section_novelty =
      (float*)calloc(AUTOMIX_MAX_SECTION_BLOCKS, sizeof(float));
  // Section blocks follow the working sample rate, which equals the input
  // sample rate here; the frame loop below re-derives it for the STFT.
  const double section_fps = (double)sample_rate / HOP_SIZE;
  int32_t section_block_frames = (int32_t)llround(
      section_fps * AUTOMIX_SECTION_BLOCK_SECONDS);
  if (section_block_frames < 1) section_block_frames = 1;
  double section_block_sum[12] = {0.0};
  double section_previous_block[12] = {0.0};
  int32_t section_block_frames_seen = 0;
  int32_t section_block_count = 0;
  int has_previous_section_block = 0;
  // rms_values packs only non-silent frames for a robust median. The
  // frame-aligned timeline preserves silent windows and is used for cue timing.
  float* rms_values = (float*)malloc((size_t)frame_count * sizeof(float));
  float* rms_frame_values = (float*)malloc((size_t)frame_count * sizeof(float));
  float* centroid_values = (float*)malloc((size_t)frame_count * sizeof(float));
  float* vocal_band_ratio_values =
      (float*)malloc((size_t)frame_count * sizeof(float));
  float* vocal_band_concentration_values =
      (float*)malloc((size_t)frame_count * sizeof(float));
  float* vocal_band_flatness_values =
      (float*)malloc((size_t)frame_count * sizeof(float));
  float* cpp_values = (float*)malloc((size_t)frame_count * sizeof(float));
  float* cepstrum_real = (float*)malloc(FFT_SIZE * sizeof(float));
  float* cepstrum_imaginary = (float*)malloc(FFT_SIZE * sizeof(float));
  float* twiddle_real = (float*)malloc(FFT_BINS * sizeof(float));
  float* twiddle_imaginary = (float*)malloc(FFT_BINS * sizeof(float));
  float* frame_magnitudes = (float*)malloc(FFT_BINS * sizeof(float));
  int32_t* bit_reverse = (int32_t*)malloc(FFT_SIZE * sizeof(int32_t));
  if (hann == NULL || real == NULL || imaginary == NULL ||
      previous_log_magnitude == NULL || odf == NULL || phase_odf == NULL ||
      beat_odf == NULL ||
      chroma_novelty == NULL || section_novelty == NULL || rms_values == NULL ||
      rms_frame_values == NULL || centroid_values == NULL ||
      vocal_band_ratio_values == NULL ||
      vocal_band_concentration_values == NULL ||
      vocal_band_flatness_values == NULL || cpp_values == NULL ||
      cepstrum_real == NULL || cepstrum_imaginary == NULL ||
      twiddle_real == NULL || twiddle_imaginary == NULL ||
      frame_magnitudes == NULL || bit_reverse == NULL) {
    free(hann); free(real); free(imaginary); free(previous_log_magnitude);
    free(odf); free(phase_odf); free(beat_odf); free(chroma_novelty);
    free(section_novelty); free(rms_values);
    free(rms_frame_values); free(centroid_values);
    free(vocal_band_ratio_values); free(vocal_band_concentration_values);
    free(vocal_band_flatness_values); free(cpp_values); free(cepstrum_real);
    free(cepstrum_imaginary); free(twiddle_real); free(twiddle_imaginary);
    free(frame_magnitudes); free(bit_reverse);
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
  int32_t vocal_band_ratio_count = 0;
  int32_t vocal_band_concentration_count = 0;
  int32_t vocal_band_flatness_count = 0;
  int32_t cpp_count = 0;
  double hpcp[12] = {0.0};
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
    double low_flux = 0.0;
    double mid_flux = 0.0;
    double high_flux = 0.0;
    double weight_sum = 0.0;
    double frequency_sum = 0.0;
    double total_spectral_magnitude = 0.0;
    double vocal_band_magnitude = 0.0;
    double vocal_band_peak_magnitude = 0.0;
    double vocal_band_power_sum = 0.0;
    double vocal_band_log_power_sum = 0.0;
    int32_t vocal_band_bin_count = 0;
    for (int32_t bin = 0; bin < FFT_BINS; ++bin) {
      const float magnitude = sqrtf(real[bin] * real[bin] +
                                    imaginary[bin] * imaginary[bin]);
      const float log_magnitude = logf(magnitude + 1.0f);
      frame_magnitudes[bin] = magnitude;
      total_spectral_magnitude += magnitude;
      const double frequency = bin * working_rate / FFT_SIZE;
      if (frequency >= 300.0 && frequency <= 3500.0) {
        vocal_band_magnitude += magnitude;
        if (magnitude > vocal_band_peak_magnitude) {
          vocal_band_peak_magnitude = magnitude;
        }
        const double power = (double)magnitude * magnitude;
        vocal_band_power_sum += power;
        vocal_band_log_power_sum += log(fmax(power, 1e-20));
        vocal_band_bin_count++;
      }
      const float difference = log_magnitude - previous_log_magnitude[bin];
      if (difference > 0.0f) {
        flux += difference;
        if (frequency >= ODF_LOW_MIN_FREQ &&
            frequency < ODF_LOW_MAX_FREQ) {
          low_flux += difference;
        } else if (frequency < ODF_MID_MAX_FREQ) {
          mid_flux += difference;
        } else if (frequency < ODF_HIGH_MAX_FREQ) {
          high_flux += difference;
        }
      }
      previous_log_magnitude[bin] = log_magnitude;

      if (frequency >= CHROMA_MIN_FREQ && frequency <= CHROMA_MAX_FREQ) {
        weight_sum += magnitude;
        frequency_sum += magnitude * frequency;
      }
    }
    double frame_chroma[12] = {0.0};
    hpcp_add_frame(frame_magnitudes, FFT_BINS, working_rate, FFT_SIZE,
                   frame_chroma);
    double frame_chroma_total = 0.0;
    for (int note = 0; note < 12; ++note) {
      hpcp[note] += frame_chroma[note];
      frame_chroma_total += frame_chroma[note];
    }
    if (frame_chroma_total > 1e-12) {
      double novelty = 0.0;
      for (int note = 0; note < 12; ++note) {
        const double share = frame_chroma[note] / frame_chroma_total;
        if (has_previous_chroma && share > previous_chroma[note]) {
          novelty += share - previous_chroma[note];
        }
        previous_chroma[note] = share;
        section_block_sum[note] += share;
      }
      has_previous_chroma = 1;
      // Half the L1 increase: a chroma redistributing from one class to
      // another then reads as one unit of change, not two.
      chroma_novelty[frame] = (float)(0.5 * novelty);
    }
    // Section-scale novelty: compare this 2 s block's mean chroma with the
    // previous block's. Blocks advance on the frame clock rather than on
    // chroma availability so a silent bar cannot shift the time axis.
    ++section_block_frames_seen;
    if (section_block_frames_seen >= section_block_frames) {
      double block_mean[12];
      for (int note = 0; note < 12; ++note) {
        block_mean[note] = section_block_sum[note] /
            (double)section_block_frames_seen;
        section_block_sum[note] = 0.0;
      }
      if (has_previous_section_block &&
          section_block_count < AUTOMIX_MAX_SECTION_BLOCKS) {
        double distance = 0.0;
        for (int note = 0; note < 12; ++note) {
          distance += fabs(block_mean[note] - section_previous_block[note]);
        }
        section_novelty[section_block_count++] = (float)(0.5 * distance);
      }
      for (int note = 0; note < 12; ++note) {
        section_previous_block[note] = block_mean[note];
      }
      has_previous_section_block = 1;
      section_block_frames_seen = 0;
    }
    // The cepstrum needs a second FFT; every other frame is enough for a
    // stable median and keeps the extra offline cost bounded.
    if (rms > 1e-6 && (frame & 1) == 0) {
      const double cpp = cepstral_peak_prominence(
          frame_magnitudes, cepstrum_real, cepstrum_imaginary, twiddle_real,
          twiddle_imaginary, bit_reverse, sample_rate);
      if (isfinite(cpp)) cpp_values[cpp_count++] = (float)cpp;
    }
    odf[frame] = flux;
    phase_odf[frame] = (float)(ODF_PHASE_LOW_WEIGHT * low_flux +
        ODF_PHASE_MID_WEIGHT * mid_flux +
        ODF_PHASE_HIGH_WEIGHT * high_flux);
    beat_odf[frame] = (float)(low_flux + ODF_PHASE_MID_WEIGHT * mid_flux);
    if (weight_sum > 1e-9) {
      centroid_values[centroid_count++] = (float)(frequency_sum / weight_sum);
      if (total_spectral_magnitude > 1e-9 && rms > 1e-6 &&
          vocal_band_magnitude > 1e-9) {
        vocal_band_ratio_values[vocal_band_ratio_count++] =
            (float)(vocal_band_magnitude / total_spectral_magnitude);
        vocal_band_concentration_values[vocal_band_concentration_count++] =
            (float)(vocal_band_peak_magnitude / vocal_band_magnitude);
        if (vocal_band_bin_count > 0 && vocal_band_power_sum > 1e-18) {
          const double arithmetic_power =
              vocal_band_power_sum / vocal_band_bin_count;
          const double geometric_power =
              exp(vocal_band_log_power_sum / vocal_band_bin_count);
          vocal_band_flatness_values[vocal_band_flatness_count++] =
              (float)fmin(1.0, fmax(0.0,
                  geometric_power / arithmetic_power));
        }
      }
    }
  }

  const double fps = working_rate / HOP_SIZE;
  // Tempo and metre are decided on the band-weighted envelope: the low band
  // carries the kick and the beat, the high band carries the subdivision. The
  // full-band ODF is kept for onset rate and structural cues.
  TempoEstimate tempo =
      estimate_tempo(beat_odf, frame_count, sample_rate, fps);
  // Material without a low/mid pulse (bright acoustic, hiss-only intros) can
  // leave the beat band too sparse for a tempo. Fall back to the wide envelope
  // rather than publishing no tempo at all.
  if (!tempo.valid || tempo.confidence < 0.20) {
    const TempoEstimate wide =
        estimate_tempo(phase_odf, frame_count, sample_rate, fps);
    if (wide.valid) tempo = wide;
  }
  if (tempo.valid) {
    output[0] = tempo.bpm;
    output[1] = tempo.confidence;
    output[20] = fmin(1.0, fmax(0.0, tempo.confidence));
    // Publish the runner-up metrical hypothesis instead of the old fixed
    // <90 / >140 octave guess. That is the only value downstream octave
    // recovery can actually use, and it is now measured.
    output[2] = isfinite(tempo.alternate_bpm) ? tempo.alternate_bpm : NAN;
    if (tempo.confidence >= 0.20) {
      output[3] = estimate_beat_phase_ms(phase_odf, frame_count, sample_rate,
                                        tempo.bpm);
    }
  }
  // 1. Tempo curve: quarter-window estimates describe how the pulse evolves
  // across the file. The head/tail quarters publish their local estimate when
  // it is confident enough; stability reports the mean octave-folded agreement
  // with the whole-window estimate so drifting or half-time-flipping tracks
  // score lower and consumers can avoid aggressive varispeed on them. Each
  // quarter needs at least 1.5 s of frames for the local autocorrelation to be
  // meaningful.
  const int32_t curve_min_frames = 4 * (int32_t)round(1.5 * fps);
  if (tempo.valid && frame_count >= curve_min_frames) {
    const int32_t quarter = frame_count / 4;
    double error_sum = 0.0;
    int32_t error_count = 0;
    for (int32_t index = 0; index < 4; ++index) {
      const float* quarter_phase_odf =
          phase_odf + (size_t)index * (size_t)quarter;
      const float* quarter_beat_odf =
          beat_odf + (size_t)index * (size_t)quarter;
      const TempoEstimate local = estimate_tempo(
          quarter_beat_odf, quarter, sample_rate, fps);
      if (!local.valid || local.confidence < 0.35) continue;
      error_sum += folded_tempo_error(local.bpm, tempo.bpm);
      error_count++;

      // Keep the locally measured beat phase paired with each edge BPM.
      // The phase is folded to that local tempo's beat period and expressed
      // relative to this PCM window, so a caller can safely use it after
      // seeking to an outgoing tail or incoming intro.
      if (index == 0 || index == 3) {
        const double quarter_start_ms =
            (double)index * quarter * HOP_SIZE * 1000.0 / working_rate;
        const double phase = estimate_beat_phase_ms(
            quarter_phase_odf, quarter, sample_rate, local.bpm);
        const double beat_period_ms = 60000.0 / local.bpm;
        if (index == 0) {
          output[21] = local.bpm;
          output[28] = local.confidence;
          if (isfinite(phase) && beat_period_ms > 0.0) {
            output[30] = fmod(quarter_start_ms + phase, beat_period_ms);
          }
        } else {
          output[22] = local.bpm;
          output[29] = local.confidence;
          if (isfinite(phase) && beat_period_ms > 0.0) {
            output[31] = fmod(quarter_start_ms + phase, beat_period_ms);
          }
        }
      }
    }
    if (error_count > 0) {
      const double mean_error = error_sum / error_count;
      output[23] = fmin(1.0, fmax(0.0, 1.0 - mean_error / 0.05));
    }
  }
  int32_t tonic = -1;
  int32_t is_minor = 0;
  double key_confidence = 0.0;
  if (estimate_key(hpcp, &tonic, &is_minor, &key_confidence)) {
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

  // 1. Quarter energy profile: median RMS of each quarter on the same frame
  // timeline as the structural cues. The planner derives intro/outro slopes
  // from adjacent quarters to tell a building head from a cooling tail; the
  // per-frame array keeps silent frames on the timeline (floored at -120 dBFS)
  // so a mostly-silent quarter cannot masquerade as missing data.
  const int32_t quarter_frames = frame_count / 4;
  if (quarter_frames > 0) {
    for (int32_t index = 0; index < 4; ++index) {
      const int32_t begin = index * quarter_frames;
      const int32_t end = index == 3 ? frame_count : begin + quarter_frames;
      const float quarter_median =
          median_float(rms_frame_values + begin, end - begin);
      output[24 + index] = isfinite(quarter_median) ? quarter_median : NAN;
    }
  }

  // 1. Phrase-start phase and metre.
  // A bar downbeat alone cannot identify a phrase boundary. Evaluate every
  // beat position of each plausible metre as a phrase start and publish a
  // phase only when one position has a clear repeated accent; otherwise leave
  // it unknown so playback falls back to beat-level locking. Metre is
  // published separately so a 3/4 or 6/8 track is not forced onto a four-beat
  // bar that drifts by one beat every bar.
  output[11] = NAN;
  output[32] = NAN;
  // Confidence is the margin between metrical levels, so 0.45 was unnecessarily
  // strict for a bar/metre hypothesis that is scored on its own evidence. The
  // Dart grid publishes at 0.35, and a waltz measured 0.44 after the beat-band
  // tempo change while its metre evidence was unchanged.
  if (tempo.valid && tempo.confidence >= 0.35 && isfinite(output[3])) {
    const double beat_ms = beat_period_ms(tempo.bpm);
    if (beat_ms >= 30.0) {
      const NarPhraseEstimate phrase = estimate_phrase_grid(
          rms_frame_values, chroma_novelty, frame_count, working_rate, fps,
          beat_ms, output[3]);
      if (phrase.meter_confident) output[32] = (double)phrase.meter;
      if (phrase.valid) output[11] = phrase.phase_ms;
    }
  }

  // 1b. Track-level section boundary from the 2 s chroma change curve. This is
  // the "structure is track-level" signal: one real change point (verse to
  // chorus, breakdown entry) instead of a per-window loudness label.
  output[33] = NAN;
  output[34] = 0.0;
  if (section_block_count >= 8) {
    double section_confidence = 0.0;
    const double section_ms = estimate_section_boundary_ms(
        section_novelty, section_block_count,
        AUTOMIX_SECTION_BLOCK_SECONDS * 1000.0, &section_confidence);
    if (isfinite(section_ms) && section_confidence > 0.0) {
      output[33] = section_ms;
      output[34] = section_confidence;
    }
  }

  // 1c. Seam-edge statistics over the last/first 15 s. The window-level RMS
  // median describes up to two minutes of material; it cannot tell a quiet
  // outro from a loud one when both windows have similar medians. These slots
  // are measured only on the material the fade actually overlaps.
  const int32_t edge_frames = (int32_t)fmin(
      (double)frame_count,
      fmax(1.0, round(AUTOMIX_EDGE_SECONDS * fps)));
  if (edge_frames > 0) {
    const int32_t tail_frame_start = frame_count - edge_frames;
    const float head_edge_rms =
        median_float(rms_frame_values, edge_frames);
    const float tail_edge_rms =
        median_float(rms_frame_values + tail_frame_start, edge_frames);
    output[35] = isfinite(head_edge_rms) ? head_edge_rms : NAN;
    output[36] = isfinite(tail_edge_rms) ? tail_edge_rms : NAN;
    output[39] = estimate_onset_rate(odf, edge_frames, fps);
    output[40] = estimate_onset_rate(
        odf + tail_frame_start, edge_frames, fps);
  }
  const int32_t edge_samples = (int32_t)fmin(
      (double)sample_count,
      fmax(1.0, round(AUTOMIX_EDGE_SECONDS * (double)working_rate)));
  if (edge_samples > 0) {
    output[37] = estimate_edge_lufs(mono, edge_samples, sample_rate);
    output[38] = estimate_edge_lufs(
        mono + sample_count - edge_samples, edge_samples, sample_rate);
  }

  // 2. Conservative structural cues.
  output[12] = NAN; // Drop cue
  output[13] = NAN; // Breakdown cue
  output[14] = 0.0; // Drop confidence
  output[15] = 0.0; // Breakdown confidence
  output[16] = (double)NAR_AUTOMIX_STRUCTURE_UNKNOWN;
  output[17] = 0.0; // Region confidence

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

    double raw_drop_ms = NAN;
    double raw_breakdown_ms = NAN;
    if (best_drop_idx >= 0) {
      raw_drop_ms = best_drop_idx * (double)HOP_SIZE * 1000.0 / working_rate;
      const double conf = fmin(1.0, fmax(0.2, best_drop_score / 12.0));
      output[14] = conf;
      if (tempo.valid && tempo.confidence >= 0.35 && isfinite(output[3])) {
        const double beat_ms = 60000.0 / tempo.bpm;
        const double beat_offset = output[3];
        const double phrase_offset = output[11];
        double snapped = raw_drop_ms;
        if (isfinite(phrase_offset)) {
          const double phrase_ms = beat_ms * 16.0;
          const double p_step = round((raw_drop_ms - phrase_offset) / phrase_ms);
          const double p_snap = phrase_offset + p_step * phrase_ms;
          if (fabs(p_snap - raw_drop_ms) <= fmin(600.0, beat_ms * 0.8)) {
            snapped = p_snap;
          }
        } else {
          const double b_step = round((raw_drop_ms - beat_offset) / beat_ms);
          const double b_snap = beat_offset + b_step * beat_ms;
          if (fabs(b_snap - raw_drop_ms) <= fmin(400.0, beat_ms * 0.4)) {
            snapped = b_snap;
          }
        }
        output[12] = fmax(0.0, snapped);
      } else {
        output[12] = raw_drop_ms;
      }
    }

    if (best_breakdown_idx >= 0) {
      raw_breakdown_ms =
          best_breakdown_idx * (double)HOP_SIZE * 1000.0 / working_rate;
      const double conf = fmin(1.0, fmax(0.2, best_breakdown_score / 12.0));
      output[15] = conf;
      if (tempo.valid && tempo.confidence >= 0.35 && isfinite(output[3])) {
        const double beat_ms = 60000.0 / tempo.bpm;
        const double beat_offset = output[3];
        const double phrase_offset = output[11];
        double snapped = raw_breakdown_ms;
        if (isfinite(phrase_offset)) {
          const double phrase_ms = beat_ms * 16.0;
          const double p_step = round((raw_breakdown_ms - phrase_offset) / phrase_ms);
          const double p_snap = phrase_offset + p_step * phrase_ms;
          if (fabs(p_snap - raw_breakdown_ms) <= fmin(600.0, beat_ms * 0.8)) {
            snapped = p_snap;
          }
        } else {
          const double b_step = round((raw_breakdown_ms - beat_offset) / beat_ms);
          const double b_snap = beat_offset + b_step * beat_ms;
          if (fabs(b_snap - raw_breakdown_ms) <= fmin(400.0, beat_ms * 0.4)) {
            snapped = b_snap;
          }
        }
        output[13] = fmax(0.0, snapped);
      } else {
        output[13] = raw_breakdown_ms;
      }
    }

    int region = NAR_AUTOMIX_STRUCTURE_UNKNOWN;
    double reg_conf = 0.5;
    if (rms_median < -45.0f || (output[9] < 0.5 && rms_median < -30.0f)) {
      region = NAR_AUTOMIX_STRUCTURE_LOW_ACTIVITY;
      reg_conf = 0.85;
    } else if (best_drop_idx >= 0) {
      region = NAR_AUTOMIX_STRUCTURE_DROP;
      reg_conf = output[14];
    } else if (best_breakdown_idx >= 0) {
      region = NAR_AUTOMIX_STRUCTURE_BREAKDOWN;
      reg_conf = output[15];
    } else if (rms_median > -20.0f) {
      region = NAR_AUTOMIX_STRUCTURE_STABLE_HIGH;
      reg_conf = 0.75;
    } else {
      region = NAR_AUTOMIX_STRUCTURE_LOW_ACTIVITY;
      reg_conf = 0.5;
    }
    output[16] = (double)region;
    output[17] = reg_conf;

    // Vocal-likelihood proxy from a broad speech-band magnitude ratio,
    // centroid stability, cepstral periodicity, and (when the source is
    // stereo) center-channel dominance. These cues cannot isolate a singer
    // from instruments, so confidence stays capped and ambiguous windows
    // remain below the planner's confidence gate.
    double vocal_like = 0.0;
    double vocal_conf = 0.0;
    const float vocal_band_ratio =
        median_float(vocal_band_ratio_values, vocal_band_ratio_count);
    const float vocal_band_concentration = median_float(
        vocal_band_concentration_values, vocal_band_concentration_count);
    const float vocal_band_flatness = median_float(
        vocal_band_flatness_values, vocal_band_flatness_count);
    const float cpp_median = median_float(cpp_values, cpp_count);
    const double cpp_score = isfinite(cpp_median)
        ? fmin(1.0, fmax(0.0, ((double)cpp_median - 3.0) / 4.0))
        : 0.0;
    const double center_channel_score = isfinite(center_channel_ratio)
        ? fmin(1.0, fmax(0.0, (center_channel_ratio - 0.45) / 0.35))
        : NAN;
    // A concentrated single tone and diffuse broadband noise are both poor
    // evidence for a vocal source; prefer structured, non-flat speech-band
    // spectra while acknowledging that instruments can still mimic speech.
    const double vocal_richness = isfinite(vocal_band_concentration)
        ? fmin(1.0, fmax(0.0, (0.55 - vocal_band_concentration) / 0.40))
        : 0.0;
    double centroid_mad = 0.0;
    for (int32_t i = 0; i < centroid_count; ++i) {
      centroid_mad += fabs((double)centroid_values[i] - centroid_median);
    }
    if (centroid_count > 0) centroid_mad /= centroid_count;
    const double centroid_stability =
        fmin(1.0, fmax(0.0, 1.0 - centroid_mad / 1400.0));
    if (isfinite(vocal_band_ratio) && isfinite(centroid_median) &&
        vocal_band_concentration_count >= 16 &&
        vocal_band_ratio >= 0.20f && vocal_richness >= 0.25 &&
        isfinite(vocal_band_flatness) && vocal_band_flatness <= 0.45f &&
        centroid_median >= 800.0f && centroid_median <= 3200.0f &&
        rms_median > -40.0f &&
        // Gate this cue to rhythmic music-like material; broadband noise and
        // isolated speech/music fragments should not drive DJ vocal avoidance.
        output[1] >= 0.20 && output[9] <= 8.0) {
      const double band_score =
          fmin(1.0, fmax(0.0, (vocal_band_ratio - 0.20) / 0.55));
      const double center_score =
          fmin(1.0, fmax(0.0, 1.0 - fabs(centroid_median - 1800.0) / 1800.0));
      const double center_channel_term = isfinite(center_channel_score)
          ? 0.12 * center_channel_score : 0.0;
      const double confidence_cap = isfinite(center_channel_score)
          ? 0.65 + 0.10 * center_channel_score : 0.65;
      vocal_like = fmin(1.0, fmax(0.0,
          0.35 * band_score + 0.20 * center_score +
          0.20 * centroid_stability + 0.25 * vocal_richness +
          0.10 * cpp_score + center_channel_term));
      // This remains a signal proxy, not a vocal separator. Center-channel
      // evidence unlocks the upper confidence range; mono/wide windows stay at
      // the previous 0.65 cap so a single ambiguous cue cannot dominate.
      vocal_conf = fmin(confidence_cap, fmax(0.0,
          0.05 + 0.25 * band_score + 0.15 * center_score +
          0.10 * centroid_stability + 0.30 * vocal_richness +
          0.06 * cpp_score + center_channel_term));
    }
    output[18] = vocal_like;
    output[19] = vocal_conf;
  }

  free(hann); free(real); free(imaginary); free(previous_log_magnitude);
  free(odf); free(phase_odf); free(beat_odf); free(chroma_novelty);
  free(section_novelty); free(rms_values);
  free(rms_frame_values); free(centroid_values);
  free(vocal_band_ratio_values); free(vocal_band_concentration_values);
  free(vocal_band_flatness_values); free(cpp_values); free(cepstrum_real);
  free(cepstrum_imaginary);
  free(twiddle_real); free(twiddle_imaginary); free(frame_magnitudes);
  free(bit_reverse);
  return 1;
}

int32_t nar_automix_analyze(const float* mono, int32_t sample_count,
                            int32_t sample_rate, double* output,
                            int32_t output_count) {
  return analyze_impl(mono, NAN, sample_count, sample_rate, output,
                      output_count);
}

int32_t nar_automix_analyze_centered(const float* mono, int32_t sample_count,
                                     int32_t sample_rate, double center_ratio,
                                     double* output, int32_t output_count) {
  return analyze_impl(mono, center_ratio, sample_count, sample_rate, output,
                      output_count);
}


// ── Time-local chord progression ────────────────────────────────────────────
// Each row is [window_start_ms, root_pitch_class, quality_id, confidence].
// quality_id: 0 major, 1 minor, 2 diminished, 3 augmented, 4 dominant 7,
//             5 major 7, 6 minor 7, 7 suspended 4, 8 suspended 2,
//             9 half-diminished 7, 10 diminished 7, 11 augmented 7.
// Unknown chords use -1/-1/0.
// Two-second windows with a one-second hop. Call only from background analysis.
FFI_PLUGIN_EXPORT int32_t nar_automix_analyze_chords(
    const float* mono, int32_t sample_count, int32_t sample_rate,
    double* output, int32_t output_capacity) {
  if (mono == NULL || output == NULL || sample_rate < 4000 ||
      sample_rate > 192000 || sample_count < 0 || output_capacity < 0) {
    return -1;
  }
  const int32_t window_samples = sample_rate * 2;
  if (sample_count < window_samples || output_capacity < 4) return 0;
  const int32_t expected_segments =
      1 + (sample_count - window_samples) / sample_rate;
  const int32_t capacity_segments = output_capacity / 4;
  const int32_t segment_count =
      expected_segments < capacity_segments ? expected_segments : capacity_segments;
  if (segment_count <= 0) return 0;

  float* hann = (float*)malloc((size_t)FFT_SIZE * sizeof(float));
  float* real = (float*)malloc((size_t)FFT_SIZE * sizeof(float));
  float* imaginary = (float*)malloc((size_t)FFT_SIZE * sizeof(float));
  float* twiddle_real = (float*)malloc((size_t)FFT_BINS * sizeof(float));
  float* twiddle_imaginary = (float*)malloc((size_t)FFT_BINS * sizeof(float));
  float* frame_magnitudes = (float*)malloc((size_t)FFT_BINS * sizeof(float));
  int32_t* bit_reverse = (int32_t*)malloc((size_t)FFT_SIZE * sizeof(int32_t));
  if (hann == NULL || real == NULL || imaginary == NULL ||
      twiddle_real == NULL || twiddle_imaginary == NULL ||
      frame_magnitudes == NULL || bit_reverse == NULL) {
    free(hann); free(real); free(imaginary);
    free(twiddle_real); free(twiddle_imaginary);
    free(frame_magnitudes); free(bit_reverse);
    return -1;
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

  static const int8_t kChordIntervals[12][4] = {
      {0, 4, 7, -1}, {0, 3, 7, -1}, {0, 3, 6, -1}, {0, 4, 8, -1},
      {0, 4, 7, 10}, {0, 4, 7, 11}, {0, 3, 7, 10}, {0, 5, 7, -1},
      {0, 2, 7, -1}, {0, 3, 6, 10}, {0, 3, 6, 9}, {0, 4, 8, 10}};
  static const int8_t kChordToneCount[12] = {
      3, 3, 3, 3, 4, 4, 4, 3, 3, 4, 4, 4};

  double* root_scores =
      (double*)malloc((size_t)segment_count * 12 * sizeof(double));
  int8_t* root_qualities =
      (int8_t*)malloc((size_t)segment_count * 12 * sizeof(int8_t));
  int16_t* back_pointer =
      (int16_t*)malloc((size_t)segment_count * 12 * sizeof(int16_t));
  double* previous = (double*)malloc(12 * sizeof(double));
  double* current = (double*)malloc(12 * sizeof(double));
  if (root_scores == NULL || root_qualities == NULL || back_pointer == NULL ||
      previous == NULL || current == NULL) {
    free(root_scores); free(root_qualities); free(back_pointer);
    free(previous); free(current);
    free(hann); free(real); free(imaginary);
    free(twiddle_real); free(twiddle_imaginary); free(frame_magnitudes);
    free(bit_reverse);
    return -1;
  }

  static const int8_t kCircleOfFifths[12] =
      {0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5};
  double transition[12][12];
  for (int from = 0; from < 12; ++from) {
    int from_index = 0;
    for (int i = 0; i < 12; ++i) {
      if (kCircleOfFifths[i] == from) {
        from_index = i;
        break;
      }
    }
    for (int to = 0; to < 12; ++to) {
      int to_index = 0;
      for (int i = 0; i < 12; ++i) {
        if (kCircleOfFifths[i] == to) {
          to_index = i;
          break;
        }
      }
      int distance = from_index - to_index;
      if (distance < 0) distance = -distance;
      if (distance > 6) distance = 12 - distance;
      transition[from][to] = distance == 0 ? 0.0
          : distance == 1 ? 0.004
          : distance == 2 ? 0.008
          : 0.012;
    }
  }

  const int32_t expected_window_samples = sample_rate * 2;
  for (int32_t segment = 0; segment < segment_count; ++segment) {
    const int32_t start = segment * sample_rate;
    double hpcp[12] = {0.0};
    double total_magnitude = 0.0;
    int32_t frame_count = 0;

    // 50% overlap gives enough spectral stability without an excessively dense STFT.
    for (int32_t offset = 0; offset <= expected_window_samples - FFT_SIZE;
         offset += 1024) {
      for (int32_t i = 0; i < FFT_SIZE; ++i) {
        const float sample = mono[start + offset + i];
        real[i] = (isfinite(sample) ? sample : 0.0f) * hann[i];
        imaginary[i] = 0.0f;
      }
      radix2_fft(real, imaginary, twiddle_real, twiddle_imaginary,
                 bit_reverse);
      for (int32_t bin = 0; bin < FFT_BINS; ++bin) {
        const double magnitude = hypot((double)real[bin], (double)imaginary[bin]);
        const double finite_magnitude =
            isfinite(magnitude) && magnitude > 0.0 ? magnitude : 0.0;
        frame_magnitudes[bin] = (float)finite_magnitude;
        const double frequency = (double)bin * sample_rate / FFT_SIZE;
        if (frequency >= CHROMA_MIN_FREQ && frequency <= CHROMA_MAX_FREQ) {
          total_magnitude += finite_magnitude;
        }
      }
      double frame_chroma[12] = {0.0};
      hpcp_add_frame(frame_magnitudes, FFT_BINS, sample_rate, FFT_SIZE,
                     frame_chroma);
      double frame_total = 0.0;
      for (int note = 0; note < 12; ++note) frame_total += frame_chroma[note];
      if (frame_total > 1e-12) {
        for (int note = 0; note < 12; ++note) {
          hpcp[note] += log1p(64.0 * frame_chroma[note] / frame_total);
        }
      }
      frame_count++;
    }

    double normalized[12] = {0.0};
    double chroma_total = 0.0;
    for (int note = 0; note < 12; ++note) chroma_total += hpcp[note];
    for (int root = 0; root < 12; ++root) {
      root_scores[segment * 12 + root] = -1.0;
      root_qualities[segment * 12 + root] = -1;
    }
    if (chroma_total > 1e-9 && frame_count > 0 && total_magnitude > 1e-7) {
      for (int note = 0; note < 12; ++note) normalized[note] = hpcp[note] / chroma_total;
      for (int root = 0; root < 12; ++root) {
        double best_quality_score = -DBL_MAX;
        int best_quality = -1;
        for (int quality = 0; quality < 12; ++quality) {
          double in_chord = 0.0;
          for (int tone = 0; tone < kChordToneCount[quality]; ++tone) {
            const int pc = (root + kChordIntervals[quality][tone]) % 12;
            in_chord += normalized[pc];
          }
          // A seventh quality is only a chord when the seventh itself has
          // energy. Without this test a plain triad always won the maj7/min7
          // quality with saturated confidence, because the extra tone could
          // only add to the score and never cost anything.
          if (kChordToneCount[quality] == 4) {
            const int seventh_pc =
                (root + kChordIntervals[quality][3]) % 12;
            double triad_sum = 0.0;
            for (int tone = 0; tone < 3; ++tone) {
              triad_sum += normalized[(root + kChordIntervals[quality][tone]) % 12];
            }
            const double seventh_energy = normalized[seventh_pc];
            if (seventh_energy < 0.10 ||
                seventh_energy < 0.70 * (triad_sum / 3.0)) {
              continue;
            }
          }
          const double score = 0.82 * in_chord + 0.18 * normalized[root];
          if (score > best_quality_score) {
            best_quality_score = score;
            best_quality = quality;
          }
        }
        if (best_quality >= 0) {
          root_scores[segment * 12 + root] = best_quality_score;
          root_qualities[segment * 12 + root] = (int8_t)best_quality;
        }
      }
    }
  }

  for (int root = 0; root < 12; ++root) {
    previous[root] = root_scores[root];
    back_pointer[root] = -1;
  }
  for (int32_t segment = 1; segment < segment_count; ++segment) {
    for (int root = 0; root < 12; ++root) {
      double best_previous = -DBL_MAX;
      int best_previous_root = -1;
      for (int prior = 0; prior < 12; ++prior) {
        if (previous[prior] <= -0.5) continue;
        const double candidate =
            previous[prior] - transition[prior][root];
        if (candidate > best_previous) {
          best_previous = candidate;
          best_previous_root = prior;
        }
      }
      const double raw = root_scores[segment * 12 + root];
      if (best_previous_root >= 0) {
        current[root] = raw + best_previous;
        back_pointer[segment * 12 + root] = (int16_t)best_previous_root;
      } else {
        current[root] = raw;
        back_pointer[segment * 12 + root] = -1;
      }
    }
    for (int root = 0; root < 12; ++root) previous[root] = current[root];
  }

  int32_t selected_root = -1;
  double selected_path = -DBL_MAX;
  for (int root = 0; root < 12; ++root) {
    if (previous[root] > selected_path) {
      selected_path = previous[root];
      selected_root = root;
    }
  }
  int32_t* selected_roots =
      (int32_t*)malloc((size_t)segment_count * sizeof(int32_t));
  if (selected_roots == NULL) {
    free(root_scores); free(root_qualities); free(back_pointer);
    free(previous); free(current);
    free(hann); free(real); free(imaginary);
    free(twiddle_real); free(twiddle_imaginary); free(frame_magnitudes);
    free(bit_reverse);
    return -1;
  }
  for (int32_t segment = 0; segment < segment_count; ++segment) {
    selected_roots[segment] = -1;
  }
  int32_t trace_root = selected_root;
  for (int32_t segment = segment_count - 1; segment >= 0; --segment) {
    selected_roots[segment] = trace_root;
    if (trace_root < 0) break;
    const int16_t prior = back_pointer[segment * 12 + trace_root];
    if (segment > 0 && prior < 0) break;
    trace_root = prior;
  }

  int32_t rows_written = 0;
  for (int32_t segment = 0; segment < segment_count; ++segment) {
    const int32_t root = selected_roots[segment];
    int best_root = -1;
    double best_score = -DBL_MAX;
    double second_score = -DBL_MAX;
    int best_quality = -1;
    if (root >= 0) {
      best_root = root;
      best_score = root_scores[segment * 12 + root];
      best_quality = root_qualities[segment * 12 + root];
      for (int other = 0; other < 12; ++other) {
        if (other == root) continue;
        const double score = root_scores[segment * 12 + other];
        if (score > second_score) second_score = score;
      }
    }

    double confidence = 0.0;
    if (best_root >= 0 && isfinite(best_score) && isfinite(second_score)) {
      const double margin = fmax(0.0, best_score - second_score);
      const double tonal_evidence = fmin(1.0, fmax(0.0,
          (best_score - 0.28) / 0.42));
      const double unique_evidence = fmin(1.0, fmax(0.0, margin / 0.035));
      confidence = tonal_evidence * unique_evidence;
      if (best_score < 0.32 || margin < 0.006 || confidence < 0.08) {
        best_root = -1;
        best_quality = -1;
        confidence = 0.0;
      }
    }

    output[rows_written * 4] =
        (double)(segment * sample_rate) * 1000.0 / (double)sample_rate;
    output[rows_written * 4 + 1] = (double)best_root;
    output[rows_written * 4 + 2] = (double)best_quality;
    output[rows_written * 4 + 3] = fmin(1.0, fmax(0.0, confidence));
    rows_written++;
  }

  // Chord hangover across a low-confidence frame. The two-second analysis
  // window straddles a chord change for one row, and the classifier correctly
  // refuses to name either chord there. That gap used to make the *previous*
  // chord look like the current one already several seconds before the
  // boundary, which is exactly the moment a transition cue samples. A short
  // decayed hangover keeps the harmonic timeline continuous without pretending
  // a new chord was detected: at most one missing row, and confidence decays
  // with the gap so a real change still wins once the next row is confident.
  {
    int32_t last_root = -1;
    int32_t last_quality = -1;
    double last_time_ms = -1e9;
    double last_confidence = 0.0;
    for (int32_t row = 0; row < rows_written; ++row) {
      const double time_ms = output[row * 4];
      const int32_t root = (int32_t)llround(output[row * 4 + 1]);
      const int32_t quality = (int32_t)llround(output[row * 4 + 2]);
      const double confidence = output[row * 4 + 3];
      if (root >= 0 && confidence > 0.0) {
        last_root = root;
        last_quality = quality;
        last_time_ms = time_ms;
        last_confidence = confidence;
        continue;
      }
      if (last_root < 0 || !isfinite(time_ms) ||
          time_ms - last_time_ms > 1500.0) {
        continue;
      }
      // Only bridge a gap *between* two confident chords. Trailing silence or
      // an unanalysable ending must stay unknown instead of inheriting the last
      // chord indefinitely.
      int32_t has_next_chord = 0;
      for (int32_t next = row + 1; next < rows_written; ++next) {
        const double next_time = output[next * 4];
        if (!isfinite(next_time) || next_time - time_ms > 1500.0) break;
        if (output[next * 4 + 3] > 0.0 && output[next * 4 + 1] >= 0.0) {
          has_next_chord = 1;
          break;
        }
      }
      if (!has_next_chord) continue;
      const double decay = fmax(0.0, 1.0 - (time_ms - last_time_ms) / 1500.0);
      output[row * 4 + 1] = (double)last_root;
      output[row * 4 + 2] = (double)last_quality;
      output[row * 4 + 3] = fmin(1.0, last_confidence * decay);
    }
  }

  free(selected_roots);
  free(root_scores); free(root_qualities); free(back_pointer);
  free(previous); free(current);
  free(hann); free(real); free(imaginary);
  free(twiddle_real); free(twiddle_imaginary); free(frame_magnitudes);
  free(bit_reverse);
  return rows_written;
}
