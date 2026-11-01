#include "automix_tone_processor.h"

#include <float.h>
#include <math.h>
#include <stddef.h>
#include <stdatomic.h>
#include <string.h>

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

#define NAR_AUTOMIX_TONE_PI 3.14159265358979323846f
// Release ramp used when the limiter is disabled at the end of an AutoMix.
#define NAR_AUTOMIX_TONE_TRUE_PEAK_RELEASE_MS 50.0f
// Once the effective ceiling is back at 1.0, the limiter is disengaged only
// after its gain is this close to unity, so bypass cannot step the waveform.
#define NAR_AUTOMIX_TONE_TRUE_PEAK_SETTLED 0.9995f

// A 3-way Linkwitz-Riley fourth-order split is built from two cascaded
// Butterworth biquads at each crossover. The upper split operates on the
// high-passed output of the lower split.
enum {
  NAR_AUTOMIX_TONE_LP_LOW = 0,
  NAR_AUTOMIX_TONE_HP_LOW = 1,
  NAR_AUTOMIX_TONE_LP_HIGH = 2,
  NAR_AUTOMIX_TONE_HP_HIGH = 3,
  NAR_AUTOMIX_TONE_FILTER_COUNT = 4,
  NAR_AUTOMIX_TONE_LR4_SECTIONS = 2,
};

typedef struct NarAutomixToneBiquadCoefficients {
  float b0;
  float b1;
  float b2;
  float a1;
  float a2;
} NarAutomixToneBiquadCoefficients;

// Structure-of-arrays state lets the ARM64 kernel update L/R as two NEON
// lanes while keeping every channel and physical stream independent.
typedef struct NarAutomixToneBiquadState {
  float z1[NAR_AUTOMIX_TONE_MAX_CHANNELS];
  float z2[NAR_AUTOMIX_TONE_MAX_CHANNELS];
} NarAutomixToneBiquadState;

typedef struct NarAutomixToneCrossoverState {
  NarAutomixToneBiquadCoefficients
      coefficients[NAR_AUTOMIX_TONE_FILTER_COUNT];
  NarAutomixToneBiquadState
      filters[NAR_AUTOMIX_TONE_FILTER_COUNT][NAR_AUTOMIX_TONE_LR4_SECTIONS];
  int32_t sample_rate;
  int32_t channel_count;
  int32_t configured;
} NarAutomixToneCrossoverState;

_Static_assert(offsetof(NarAutomixToneState, low_pass_state) == 0,
               "legacy tone low-pass state offset changed");
_Static_assert(offsetof(NarAutomixToneState, high_cut_state) == 32,
               "legacy tone high-cut state offset changed");
_Static_assert(offsetof(NarAutomixToneState, low_pass_alpha) == 64,
               "legacy tone low-pass coefficient offset changed");
_Static_assert(offsetof(NarAutomixToneState, high_cut_alpha) == 68,
               "legacy tone high-cut coefficient offset changed");
_Static_assert(offsetof(NarAutomixToneState, gain_smoothing_alpha) == 72,
               "tone gain coefficient offset changed");
_Static_assert(offsetof(NarAutomixToneState, current_bass_gain) == 76,
               "NEON bass gain offset changed");
_Static_assert(offsetof(NarAutomixToneState, current_high_gain) == 80,
               "NEON high gain offset changed");
_Static_assert(offsetof(NarAutomixToneState, current_fade_gain) == 92,
               "NEON fade gain offset changed");
_Static_assert(offsetof(NarAutomixToneState, current_mid_gain) == 100,
               "NEON mid gain offset changed");
_Static_assert(offsetof(NarAutomixToneState, true_peak_gain) == 104,
               "true-peak gain offset changed");
_Static_assert(offsetof(NarAutomixToneState, true_peak_release_alpha) == 108,
               "true-peak release offset changed");
_Static_assert(offsetof(NarAutomixToneState, true_peak_history) == 112,
               "true-peak history offset changed");
_Static_assert(offsetof(NarAutomixToneState, true_peak_primed) == 240,
               "true-peak primed offset changed");
_Static_assert(offsetof(NarAutomixToneState, true_peak_ceiling) == 244,
               "true-peak ceiling offset changed");
_Static_assert(offsetof(NarAutomixToneState, true_peak_release_frames) == 248,
               "true-peak release frames offset changed");
_Static_assert(offsetof(NarAutomixToneState, true_peak_release_step) == 252,
               "true-peak release step offset changed");
_Static_assert(sizeof(NarAutomixToneState) == 256,
               "true-peak state size changed");

static NarAutomixToneState g_states[NAR_AUTOMIX_TONE_STREAM_COUNT];
static NarAutomixToneCrossoverState
    g_crossover_states[NAR_AUTOMIX_TONE_STREAM_COUNT];
static _Atomic float g_target_bass[NAR_AUTOMIX_TONE_STREAM_COUNT] = {1.0f, 1.0f};
static _Atomic float g_target_mid[NAR_AUTOMIX_TONE_STREAM_COUNT] = {1.0f, 1.0f};
static _Atomic float g_target_high[NAR_AUTOMIX_TONE_STREAM_COUNT] = {1.0f, 1.0f};
static _Atomic float g_target_fade[NAR_AUTOMIX_TONE_STREAM_COUNT] = {1.0f, 1.0f};
// Zero disables the limiter. Kept separate from the per-sample gain so normal
// playback never pays for true-peak estimation.
static _Atomic float g_target_true_peak[NAR_AUTOMIX_TONE_STREAM_COUNT] = {
    0.0f, 0.0f};

static void compute_biquad_coefficients(
    NarAutomixToneBiquadCoefficients* coefficients, int32_t sample_rate,
    float cutoff_hz, int high_pass) {
  const float omega = 2.0f * NAR_AUTOMIX_TONE_PI * cutoff_hz /
      (float)sample_rate;
  const float cosine = cosf(omega);
  const float sine = sinf(omega);
  const float alpha = sine * 0.7071067811865475f;
  const float a0 = 1.0f + alpha;
  if (high_pass) {
    coefficients->b0 = (0.5f * (1.0f + cosine)) / a0;
    coefficients->b1 = (-(1.0f + cosine)) / a0;
    coefficients->b2 = (0.5f * (1.0f + cosine)) / a0;
  } else {
    coefficients->b0 = (0.5f * (1.0f - cosine)) / a0;
    coefficients->b1 = (1.0f - cosine) / a0;
    coefficients->b2 = (0.5f * (1.0f - cosine)) / a0;
  }
  coefficients->a1 = (-2.0f * cosine) / a0;
  coefficients->a2 = (1.0f - alpha) / a0;
}

static float process_biquad_scalar(
    float input, const NarAutomixToneBiquadCoefficients* coefficients,
    NarAutomixToneBiquadState* state, int32_t channel) {
  const float output = coefficients->b0 * input + state->z1[channel];
  const float next_z1 = coefficients->b1 * input -
      coefficients->a1 * output + state->z2[channel];
  const float next_z2 = coefficients->b2 * input -
      coefficients->a2 * output;
  if (!isfinite(output) || !isfinite(next_z1) || !isfinite(next_z2)) {
    state->z1[channel] = 0.0f;
    state->z2[channel] = 0.0f;
    return 0.0f;
  }
  state->z1[channel] = next_z1;
  state->z2[channel] = next_z2;
  return output;
}

static float process_lr4_scalar(
    float input, NarAutomixToneCrossoverState* crossover, int32_t filter,
    int32_t channel) {
  NarAutomixToneBiquadState* sections = crossover->filters[filter];
  const NarAutomixToneBiquadCoefficients* coefficients =
      &crossover->coefficients[filter];
  const float first = process_biquad_scalar(
      input, coefficients, &sections[0], channel);
  return process_biquad_scalar(first, coefficients, &sections[1], channel);
}

#if defined(__aarch64__)
static float32x2_t sanitize_stereo_neon(float32x2_t value) {
  const uint32x2_t finite = vcle_f32(vabs_f32(value), vdup_n_f32(FLT_MAX));
  return vbsl_f32(finite, value, vdup_n_f32(0.0f));
}

static float32x2_t process_biquad_neon(
    float32x2_t input, const NarAutomixToneBiquadCoefficients* coefficients,
    NarAutomixToneBiquadState* state) {
  const float32x2_t z1 = vld1_f32(state->z1);
  const float32x2_t z2 = vld1_f32(state->z2);
  const float32x2_t output = vadd_f32(
      vmul_n_f32(input, coefficients->b0), z1);
  const float32x2_t next_z1 = vadd_f32(
      vsub_f32(vmul_n_f32(input, coefficients->b1),
               vmul_n_f32(output, coefficients->a1)),
      z2);
  const float32x2_t next_z2 = vsub_f32(
      vmul_n_f32(input, coefficients->b2),
      vmul_n_f32(output, coefficients->a2));
  const float32x2_t maximum = vdup_n_f32(FLT_MAX);
  uint32x2_t finite = vand_u32(
      vcle_f32(vabs_f32(output), maximum),
      vcle_f32(vabs_f32(next_z1), maximum));
  finite = vand_u32(finite, vcle_f32(vabs_f32(next_z2), maximum));
  vst1_f32(state->z1, vbsl_f32(finite, next_z1, vdup_n_f32(0.0f)));
  vst1_f32(state->z2, vbsl_f32(finite, next_z2, vdup_n_f32(0.0f)));
  return vbsl_f32(finite, output, vdup_n_f32(0.0f));
}

static float32x2_t process_lr4_neon(
    float32x2_t input, NarAutomixToneCrossoverState* crossover,
    int32_t filter) {
  NarAutomixToneBiquadState* sections = crossover->filters[filter];
  const NarAutomixToneBiquadCoefficients* coefficients =
      &crossover->coefficients[filter];
  const float32x2_t first = process_biquad_neon(
      input, coefficients, &sections[0]);
  return process_biquad_neon(first, coefficients, &sections[1]);
}

static void process_stereo_neon(
    float* interleaved, int32_t frame_count, NarAutomixToneState* state,
    NarAutomixToneCrossoverState* crossover, float target_bass,
    float target_mid, float target_high, float target_fade) {
  float current_bass = state->current_bass_gain;
  float current_mid = state->current_mid_gain;
  float current_high = state->current_high_gain;
  float current_fade = state->current_fade_gain;
  const float gain_alpha = state->gain_smoothing_alpha;
  const float fade_step = (target_fade - current_fade) / (float)frame_count;
  for (int32_t frame = 0; frame < frame_count; ++frame) {
    current_bass += (target_bass - current_bass) * gain_alpha;
    current_mid += (target_mid - current_mid) * gain_alpha;
    current_high += (target_high - current_high) * gain_alpha;
    current_fade += fade_step;

    float32x2_t input = sanitize_stereo_neon(
        vld1_f32(&interleaved[(size_t)frame * 2u]));
    const float32x2_t low = process_lr4_neon(
        input, crossover, NAR_AUTOMIX_TONE_LP_LOW);
    const float32x2_t upper = process_lr4_neon(
        input, crossover, NAR_AUTOMIX_TONE_HP_LOW);
    const float32x2_t mid = process_lr4_neon(
        upper, crossover, NAR_AUTOMIX_TONE_LP_HIGH);
    const float32x2_t high = process_lr4_neon(
        upper, crossover, NAR_AUTOMIX_TONE_HP_HIGH);
    float32x2_t output;
    if (current_bass == 1.0f && current_mid == 1.0f &&
        current_high == 1.0f) {
      // Keep the crossover state warm without changing unity-gain PCM.
      output = input;
    } else {
      output = vadd_f32(
          vadd_f32(vmul_n_f32(low, current_bass),
                   vmul_n_f32(mid, current_mid)),
          vmul_n_f32(high, current_high));
    }
    output = sanitize_stereo_neon(vmul_n_f32(output, current_fade));
    output = vmax_f32(vdup_n_f32(-1.0f),
                      vmin_f32(vdup_n_f32(1.0f), output));
    vst1_f32(&interleaved[(size_t)frame * 2u], output);
  }
  state->current_bass_gain = current_bass;
  state->current_mid_gain = current_mid;
  state->current_high_gain = current_high;
  state->current_fade_gain = current_fade;
}
#endif

static int valid_stream_slot(int32_t stream_slot) {
  return stream_slot >= 0 && stream_slot < NAR_AUTOMIX_TONE_STREAM_COUNT;
}

static float clamp_gain(float gain) {
  if (!isfinite(gain)) return 1.0f;
  if (gain < 0.0f) return 0.0f;
  if (gain > 1.0f) return 1.0f;
  return gain;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_configure(
    int32_t stream_slot, int32_t sample_rate, int32_t channel_count) {
  // The highest crossover is 1.2 kHz; fail open if it is not below Nyquist.
  if (!valid_stream_slot(stream_slot) || sample_rate <= 2400 ||
      channel_count <= 0 || channel_count > NAR_AUTOMIX_TONE_MAX_CHANNELS) {
    return 0;
  }

  NarAutomixToneState* state = &g_states[stream_slot];
  NarAutomixToneCrossoverState* crossover =
      &g_crossover_states[stream_slot];
  memset(state, 0, sizeof(*state));
  memset(crossover, 0, sizeof(*crossover));
  compute_biquad_coefficients(
      &crossover->coefficients[NAR_AUTOMIX_TONE_LP_LOW], sample_rate,
      150.0f, 0);
  compute_biquad_coefficients(
      &crossover->coefficients[NAR_AUTOMIX_TONE_HP_LOW], sample_rate,
      150.0f, 1);
  compute_biquad_coefficients(
      &crossover->coefficients[NAR_AUTOMIX_TONE_LP_HIGH], sample_rate,
      1200.0f, 0);
  compute_biquad_coefficients(
      &crossover->coefficients[NAR_AUTOMIX_TONE_HP_HIGH], sample_rate,
      1200.0f, 1);
  crossover->sample_rate = sample_rate;
  crossover->channel_count = channel_count;
  crossover->configured = 1;
  state->gain_smoothing_alpha =
      1.0f - expf(-1.0f / ((float)sample_rate * 0.020f));
  state->current_bass_gain =
      atomic_load_explicit(&g_target_bass[stream_slot], memory_order_relaxed);
  state->current_mid_gain =
      atomic_load_explicit(&g_target_mid[stream_slot], memory_order_relaxed);
  state->current_high_gain =
      atomic_load_explicit(&g_target_high[stream_slot], memory_order_relaxed);
  state->current_fade_gain =
      atomic_load_explicit(&g_target_fade[stream_slot], memory_order_relaxed);
  state->true_peak_gain = 1.0f;
  state->true_peak_release_alpha =
      1.0f - expf(-1.0f / ((float)sample_rate * 0.050f));
  state->true_peak_primed = 0;
  state->true_peak_ceiling = 0.0f;
  state->true_peak_release_frames = 0;
  state->true_peak_release_step = 0.0f;
  state->sample_rate = sample_rate;
  state->channel_count = channel_count;
  state->configured = 1;
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_bass_gain(
    int32_t stream_slot, float gain) {
  if (!valid_stream_slot(stream_slot)) return 0;
  atomic_store_explicit(&g_target_bass[stream_slot], clamp_gain(gain),
                       memory_order_relaxed);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_mid_gain(
    int32_t stream_slot, float gain) {
  if (!valid_stream_slot(stream_slot)) return 0;
  atomic_store_explicit(&g_target_mid[stream_slot], clamp_gain(gain),
                       memory_order_relaxed);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_high_gain(
    int32_t stream_slot, float gain) {
  if (!valid_stream_slot(stream_slot)) return 0;
  atomic_store_explicit(&g_target_high[stream_slot], clamp_gain(gain),
                       memory_order_relaxed);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_fade_gain(
    int32_t stream_slot, float gain) {
  if (!valid_stream_slot(stream_slot)) return 0;
  atomic_store_explicit(&g_target_fade[stream_slot], clamp_gain(gain),
                        memory_order_relaxed);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_true_peak_limit(
    int32_t stream_slot, float ceiling) {
  if (!valid_stream_slot(stream_slot)) return 0;
  // Non-finite or non-positive ceilings disable the limiter explicitly rather
  // than falling back to a "safe" gain: normal playback must stay transparent.
  float normalized = 0.0f;
  if (isfinite(ceiling) && ceiling > 0.0f) {
    normalized = fminf(fmaxf(ceiling, 0.05f), 1.0f);
  }
  atomic_store_explicit(&g_target_true_peak[stream_slot], normalized,
                        memory_order_relaxed);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_compute_fade_gains(
    float progress, float gamma, float outgoing_trim, float incoming_trim,
    float* outgoing_gain, float* incoming_gain) {
  if (outgoing_gain == NULL || incoming_gain == NULL || !isfinite(progress) ||
      !isfinite(gamma) || !isfinite(outgoing_trim) ||
      !isfinite(incoming_trim)) {
    return 0;
  }

  const float t = fminf(fmaxf(progress, 0.0f), 1.0f);
  const float g = fminf(fmaxf(gamma, 0.6f), 1.6f);
  // gamma > 1 accelerates handover (quick/short handover); gamma < 1 decelerates (long blend).
  const float shape = (g == 1.0f) ? t : powf(t, 1.0f / g);
  const float theta = shape * (NAR_AUTOMIX_TONE_PI * 0.5f);
  const float trim_out = fminf(fmaxf(outgoing_trim, 0.0f), 1.0f);
  const float trim_in = fminf(fmaxf(incoming_trim, 0.0f), 1.0f);
  // Symmetric level-match ramps. The outgoing trim fades in over the first
  // quarter so an already-playing deck never steps down at t=0; the incoming
  // trim is released over the last quarter so the promoted deck ends at its
  // own level. This must stay identical to AutomixGainEnvelope.kt: the Kotlin
  // volume-ramp fallback and this per-sample path are two implementations of
  // one cue, and a missing attack here made them disagree by up to 6 dB on the
  // outgoing deck.
  const float attack = t >= 0.25f ? 1.0f : t / 0.25f;
  const float outgoing_trim_now = 1.0f - (1.0f - trim_out) * attack;
  const float release =
      t <= 0.75f ? 0.0f : (t - 0.75f) / 0.25f;
  const float incoming_trim_now = trim_in + (1.0f - trim_in) * release;

  float outgoing = clamp_gain(outgoing_trim_now * cosf(theta));
  float incoming = clamp_gain(incoming_trim_now * sinf(theta));

  *outgoing_gain = outgoing;
  *incoming_gain = incoming;
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_crossfade_gains(
    int32_t outgoing_slot, int32_t incoming_slot, float progress, float gamma,
    float outgoing_trim, float incoming_trim) {
  if (!valid_stream_slot(outgoing_slot) || !valid_stream_slot(incoming_slot) ||
      outgoing_slot == incoming_slot) {
    return 0;
  }

  float outgoing_gain;
  float incoming_gain;
  if (!nar_automix_tone_compute_fade_gains(
          progress, gamma, outgoing_trim, incoming_trim,
          &outgoing_gain, &incoming_gain)) {
    return 0;
  }
  atomic_store_explicit(&g_target_fade[outgoing_slot], outgoing_gain,
                        memory_order_relaxed);
  atomic_store_explicit(&g_target_fade[incoming_slot], incoming_gain,
                        memory_order_relaxed);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_reset(int32_t stream_slot) {
  if (!valid_stream_slot(stream_slot)) return 0;
  NarAutomixToneState* state = &g_states[stream_slot];
  NarAutomixToneCrossoverState* crossover =
      &g_crossover_states[stream_slot];
  memset(crossover->filters, 0, sizeof(crossover->filters));
  state->current_bass_gain =
      atomic_load_explicit(&g_target_bass[stream_slot], memory_order_relaxed);
  state->current_mid_gain =
      atomic_load_explicit(&g_target_mid[stream_slot], memory_order_relaxed);
  state->current_high_gain =
      atomic_load_explicit(&g_target_high[stream_slot], memory_order_relaxed);
  state->current_fade_gain =
      atomic_load_explicit(&g_target_fade[stream_slot], memory_order_relaxed);
  memset(state->true_peak_history, 0, sizeof(state->true_peak_history));
  state->true_peak_gain = 1.0f;
  state->true_peak_primed = 0;
  state->true_peak_ceiling = 0.0f;
  state->true_peak_release_frames = 0;
  state->true_peak_release_step = 0.0f;
  return 1;
}

// Cubic Lagrange interpolation at 4x oversampling. history[0] is the current
// sample and history[1..3] are the three previous input samples; the three
// coefficient sets evaluate 25 %, 50 % and 75 % of the way from history[0]
// back towards history[1]. Using the *input* samples keeps the detector
// input-referred, so a gain reduction does not hide a still-loud source peak.
static const float kTruePeakCoeffs[3][4] = {
    {0.6015625f, 0.6015625f, -0.2578125f, 0.0546875f},
    {0.3125f, 0.9375f, -0.3125f, 0.0625f},
    {0.1171875f, 1.0546875f, -0.2109375f, 0.0390625f},
};

static float true_peak_frame(const float history[4]) {
  float peak = fabsf(history[0]);
  for (int set = 0; set < 3; ++set) {
    const float* c = kTruePeakCoeffs[set];
    const float interpolated = c[0] * history[0] + c[1] * history[1] +
        c[2] * history[2] + c[3] * history[3];
    const float magnitude = fabsf(interpolated);
    if (magnitude > peak) peak = magnitude;
  }
  return peak;
}

// Starts the end-of-overlap release. The ceiling must walk back to 1.0 over
// the same ~50 ms window as the gain release; jumping straight to bypass would
// step every sample that the clamp was holding at the AutoMix ceiling.
static void begin_true_peak_release(NarAutomixToneState* state) {
  if (state->true_peak_release_frames > 0 ||
      state->true_peak_ceiling >= 1.0f) {
    return;
  }
  int32_t frames = (int32_t)(
      (float)state->sample_rate * NAR_AUTOMIX_TONE_TRUE_PEAK_RELEASE_MS /
          1000.0f +
      0.5f);
  if (frames < 1) frames = 1;
  state->true_peak_release_frames = frames;
  state->true_peak_release_step =
      (1.0f - state->true_peak_ceiling) / (float)frames;
}

// Per-deck safety limiter. The platform mixer is downstream and sums both
// decks, so limiting each deck independently does not bound their combined
// peak. A shared post-mix limiter would be required for a hard sum ceiling.
// This is a causal estimator with instant attack and a ~50 ms release, so the first transient
// after enabling can still overshoot slightly; the sample clamp below keeps
// the per-deck output inside the ceiling.
static void apply_true_peak_limiter(
    float* interleaved, int32_t frame_count, int32_t channel_count,
    float ceiling, int32_t release_ceiling, NarAutomixToneState* state) {
  if (!state->true_peak_primed) {
    memset(state->true_peak_history, 0, sizeof(state->true_peak_history));
    state->true_peak_gain = 1.0f;
    state->true_peak_ceiling = ceiling;
    state->true_peak_release_frames = 0;
    state->true_peak_release_step = 0.0f;
    state->true_peak_primed = 1;
  }
  float gain = state->true_peak_gain;
  const float release = state->true_peak_release_alpha;
  float effective_ceiling = state->true_peak_ceiling;
  for (int32_t frame = 0; frame < frame_count; ++frame) {
    if (release_ceiling && state->true_peak_release_frames > 0) {
      effective_ceiling =
          fminf(1.0f, effective_ceiling + state->true_peak_release_step);
      state->true_peak_release_frames--;
    }
    const size_t base = (size_t)frame * (size_t)channel_count;
    float peak = 0.0f;
    for (int32_t channel = 0; channel < channel_count; ++channel) {
      float* history = state->true_peak_history[channel];
      history[3] = history[2];
      history[2] = history[1];
      history[1] = history[0];
      history[0] = interleaved[base + (size_t)channel];
      const float frame_peak = true_peak_frame(history);
      if (frame_peak > peak) peak = frame_peak;
    }
    const float desired =
        peak > effective_ceiling ? effective_ceiling / peak : 1.0f;
    if (desired < gain) {
      gain = desired;
    } else {
      gain += (desired - gain) * release;
    }
    if (gain < 0.0f) gain = 0.0f;
    if (gain > 1.0f) gain = 1.0f;
    if (release_ceiling && state->true_peak_release_frames == 0 &&
        effective_ceiling >= 1.0f &&
        gain >= NAR_AUTOMIX_TONE_TRUE_PEAK_SETTLED) {
      // Release finished. Use unity for the rest of this block so the first
      // bypassed block cannot inherit a residual gain step.
      gain = 1.0f;
    }
    for (int32_t channel = 0; channel < channel_count; ++channel) {
      float sample = interleaved[base + (size_t)channel] * gain;
      if (!isfinite(sample)) sample = 0.0f;
      sample = fminf(effective_ceiling, fmaxf(-effective_ceiling, sample));
      interleaved[base + (size_t)channel] = sample;
    }
  }
  state->true_peak_gain = gain;
  state->true_peak_ceiling = effective_ceiling;
}

static int32_t process_tone_impl(
    float* interleaved, int32_t frame_count, int32_t channel_count,
    int32_t stream_slot, int use_neon) {
  if (interleaved == NULL || frame_count <= 0 ||
      !valid_stream_slot(stream_slot)) {
    return 0;
  }

  NarAutomixToneState* state = &g_states[stream_slot];
  NarAutomixToneCrossoverState* crossover =
      &g_crossover_states[stream_slot];
  if (!state->configured || !crossover->configured ||
      channel_count != state->channel_count ||
      channel_count != crossover->channel_count) {
    return 0;
  }

  const float target_bass =
      atomic_load_explicit(&g_target_bass[stream_slot], memory_order_relaxed);
  const float target_mid =
      atomic_load_explicit(&g_target_mid[stream_slot], memory_order_relaxed);
  const float target_high =
      atomic_load_explicit(&g_target_high[stream_slot], memory_order_relaxed);
  const float target_fade =
      atomic_load_explicit(&g_target_fade[stream_slot], memory_order_relaxed);
  const float true_peak_ceiling =
      atomic_load_explicit(&g_target_true_peak[stream_slot],
                           memory_order_relaxed);

  int processed_neon = 0;
#if defined(__aarch64__)
  if (use_neon && channel_count == 2) {
    process_stereo_neon(interleaved, frame_count, state, crossover,
                        target_bass, target_mid, target_high, target_fade);
    processed_neon = 1;
  }
#else
  (void)use_neon;
#endif

  if (!processed_neon) {
    float current_bass = state->current_bass_gain;
    float current_mid = state->current_mid_gain;
    float current_high = state->current_high_gain;
    float current_fade = state->current_fade_gain;
    const float gain_alpha = state->gain_smoothing_alpha;
    const float fade_step = (target_fade - current_fade) / (float)frame_count;

    for (int32_t frame = 0; frame < frame_count; ++frame) {
      current_bass += (target_bass - current_bass) * gain_alpha;
      current_mid += (target_mid - current_mid) * gain_alpha;
      current_high += (target_high - current_high) * gain_alpha;
      current_fade += fade_step;
      for (int32_t channel = 0; channel < channel_count; ++channel) {
        const size_t index =
            (size_t)frame * (size_t)channel_count + (size_t)channel;
        float sample = interleaved[index];
        if (!isfinite(sample)) sample = 0.0f;
        const float low = process_lr4_scalar(
            sample, crossover, NAR_AUTOMIX_TONE_LP_LOW, channel);
        const float upper = process_lr4_scalar(
            sample, crossover, NAR_AUTOMIX_TONE_HP_LOW, channel);
        const float mid = process_lr4_scalar(
            upper, crossover, NAR_AUTOMIX_TONE_LP_HIGH, channel);
        const float high = process_lr4_scalar(
            upper, crossover, NAR_AUTOMIX_TONE_HP_HIGH, channel);
        const float output = current_bass == 1.0f && current_mid == 1.0f &&
                current_high == 1.0f
            ? sample
            : low * current_bass + mid * current_mid + high * current_high;
        const float faded = output * current_fade;
        // Sample-peak safety clamp before the optional true-peak post-pass.
        interleaved[index] = isfinite(faded)
            ? fminf(1.0f, fmaxf(-1.0f, faded))
            : 0.0f;
      }
    }

    state->current_bass_gain = current_bass;
    state->current_mid_gain = current_mid;
    state->current_high_gain = current_high;
    state->current_fade_gain = current_fade;
  }

  if (true_peak_ceiling > 0.0f) {
    // A new or continuing overlap owns the ceiling; cancel any release ramp.
    state->true_peak_ceiling = true_peak_ceiling;
    state->true_peak_release_frames = 0;
    state->true_peak_release_step = 0.0f;
    apply_true_peak_limiter(interleaved, frame_count, channel_count,
                            true_peak_ceiling, 0, state);
  } else if (state->true_peak_primed) {
    // Do not bypass in place at the end of an AutoMix. Ramp the clamp back to
    // 1.0 and keep the limiter engaged until its release gain has settled;
    // then drop to the transparent path without a waveform step.
    begin_true_peak_release(state);
    apply_true_peak_limiter(interleaved, frame_count, channel_count,
                            1.0f, 1, state);
    if (state->true_peak_release_frames == 0 &&
        state->true_peak_ceiling >= 1.0f &&
        state->true_peak_gain >= NAR_AUTOMIX_TONE_TRUE_PEAK_SETTLED) {
      state->true_peak_primed = 0;
      state->true_peak_gain = 1.0f;
      state->true_peak_ceiling = 0.0f;
      state->true_peak_release_step = 0.0f;
      memset(state->true_peak_history, 0, sizeof(state->true_peak_history));
    }
  }
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_process(
    float* interleaved, int32_t frame_count, int32_t channel_count,
    int32_t stream_slot) {
  return process_tone_impl(
      interleaved, frame_count, channel_count, stream_slot, 1);
}

#if defined(__GNUC__)
__attribute__((visibility("hidden")))
#endif
int32_t nar_automix_tone_process_scalar_for_test(
    float* interleaved, int32_t frame_count, int32_t channel_count,
    int32_t stream_slot) {
  return process_tone_impl(
      interleaved, frame_count, channel_count, stream_slot, 0);
}
