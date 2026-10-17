#include "automix_tone_processor.h"

#include <math.h>
#include <stddef.h>
#include <stdatomic.h>
#include <string.h>

#define NAR_AUTOMIX_TONE_PI 3.14159265358979323846f

_Static_assert(offsetof(NarAutomixToneState, low_pass_state) == 0,
               "NEON low-pass state offset changed");
_Static_assert(offsetof(NarAutomixToneState, high_cut_state) == 32,
               "NEON high-cut state offset changed");
_Static_assert(offsetof(NarAutomixToneState, low_pass_alpha) == 64,
               "NEON low-pass coefficient offset changed");
_Static_assert(offsetof(NarAutomixToneState, high_cut_alpha) == 68,
               "NEON high-cut coefficient offset changed");
_Static_assert(offsetof(NarAutomixToneState, gain_smoothing_alpha) == 72,
               "NEON gain coefficient offset changed");
_Static_assert(offsetof(NarAutomixToneState, current_bass_gain) == 76,
               "NEON bass gain offset changed");
_Static_assert(offsetof(NarAutomixToneState, current_high_gain) == 80,
               "NEON high gain offset changed");
_Static_assert(offsetof(NarAutomixToneState, current_fade_gain) == 92,
               "NEON fade gain offset changed");
_Static_assert(offsetof(NarAutomixToneState, current_mid_gain) == 100,
               "NEON mid gain offset changed");

static NarAutomixToneState g_states[NAR_AUTOMIX_TONE_STREAM_COUNT];
static _Atomic float g_target_bass[NAR_AUTOMIX_TONE_STREAM_COUNT] = {1.0f, 1.0f};
static _Atomic float g_target_mid[NAR_AUTOMIX_TONE_STREAM_COUNT] = {1.0f, 1.0f};
static _Atomic float g_target_high[NAR_AUTOMIX_TONE_STREAM_COUNT] = {1.0f, 1.0f};
static _Atomic float g_target_fade[NAR_AUTOMIX_TONE_STREAM_COUNT] = {1.0f, 1.0f};

#if defined(__aarch64__)
extern void nar_automix_tone_process_stereo_neon(
    float* interleaved, int32_t frame_count, NarAutomixToneState* state,
    float target_bass, float target_mid, float target_high, float target_fade);
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
  if (!valid_stream_slot(stream_slot) || sample_rate <= 0 ||
      channel_count <= 0 || channel_count > NAR_AUTOMIX_TONE_MAX_CHANNELS) {
    return 0;
  }

  NarAutomixToneState* state = &g_states[stream_slot];
  memset(state, 0, sizeof(*state));
  state->low_pass_alpha =
      1.0f - expf(-2.0f * NAR_AUTOMIX_TONE_PI * 150.0f / sample_rate);
  state->high_cut_alpha =
      1.0f - expf(-2.0f * NAR_AUTOMIX_TONE_PI * 1200.0f / sample_rate);
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

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_compute_fade_gains(
    float progress, float gamma, float outgoing_trim, float incoming_trim,
    float* outgoing_gain, float* incoming_gain) {
  if (outgoing_gain == NULL || incoming_gain == NULL || !isfinite(progress) ||
      !isfinite(gamma) || !isfinite(outgoing_trim) ||
      !isfinite(incoming_trim)) {
    return 0;
  }

  const float t = fminf(fmaxf(progress, 0.0f), 1.0f);
  const float shape = powf(t, fminf(fmaxf(gamma, 0.6f), 1.6f));
  const float theta = shape * (NAR_AUTOMIX_TONE_PI * 0.5f);
  const float trim_out = fminf(fmaxf(outgoing_trim, 0.0f), 1.0f);
  const float trim_in = fminf(fmaxf(incoming_trim, 0.0f), 1.0f);
  const float release =
      t <= 0.75f ? 0.0f : (t - 0.75f) / 0.25f;
  const float incoming_trim_now = trim_in + (1.0f - trim_in) * release;

  float outgoing = clamp_gain(trim_out * cosf(theta));
  float incoming = clamp_gain(incoming_trim_now * sinf(theta));

  // Equal-power gains can sum above unity for correlated source material.
  // Normalize their L1 budget to 1.0 so overlapping, sample-peak-bounded PCM
  // streams cannot exceed unity when summed by the platform mixer.
  const float gain_sum = outgoing + incoming;
  if (gain_sum > 1.0f) {
    const float scale = 1.0f / gain_sum;
    outgoing *= scale;
    incoming *= scale;
  }

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
  memset(state->low_pass_state, 0, sizeof(state->low_pass_state));
  memset(state->high_cut_state, 0, sizeof(state->high_cut_state));
  state->current_bass_gain =
      atomic_load_explicit(&g_target_bass[stream_slot], memory_order_relaxed);
  state->current_mid_gain =
      atomic_load_explicit(&g_target_mid[stream_slot], memory_order_relaxed);
  state->current_high_gain =
      atomic_load_explicit(&g_target_high[stream_slot], memory_order_relaxed);
  state->current_fade_gain =
      atomic_load_explicit(&g_target_fade[stream_slot], memory_order_relaxed);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_process(
    float* interleaved, int32_t frame_count, int32_t channel_count,
    int32_t stream_slot) {
  if (interleaved == NULL || frame_count <= 0 ||
      !valid_stream_slot(stream_slot)) {
    return 0;
  }

  NarAutomixToneState* state = &g_states[stream_slot];
  if (!state->configured || channel_count != state->channel_count) return 0;

  const float target_bass =
      atomic_load_explicit(&g_target_bass[stream_slot], memory_order_relaxed);
  const float target_mid =
      atomic_load_explicit(&g_target_mid[stream_slot], memory_order_relaxed);
  const float target_high =
      atomic_load_explicit(&g_target_high[stream_slot], memory_order_relaxed);
  const float target_fade =
      atomic_load_explicit(&g_target_fade[stream_slot], memory_order_relaxed);

#if defined(__aarch64__)
  if (channel_count == 2) {
    nar_automix_tone_process_stereo_neon(
        interleaved, frame_count, state, target_bass, target_mid, target_high,
        target_fade);
    return 1;
  }
#endif

  float current_bass = state->current_bass_gain;
  float current_mid = state->current_mid_gain;
  float current_high = state->current_high_gain;
  float current_fade = state->current_fade_gain;
  const float gain_alpha = state->gain_smoothing_alpha;
  const float low_alpha = state->low_pass_alpha;
  const float high_alpha = state->high_cut_alpha;
  const float fade_step = (target_fade - current_fade) / (float)frame_count;

  for (int32_t frame = 0; frame < frame_count; ++frame) {
    current_bass += (target_bass - current_bass) * gain_alpha;
    current_mid += (target_mid - current_mid) * gain_alpha;
    current_high += (target_high - current_high) * gain_alpha;
    current_fade += fade_step;
    for (int32_t channel = 0; channel < channel_count; ++channel) {
      const size_t index = (size_t)frame * channel_count + channel;
      float sample = interleaved[index];
      if (!isfinite(sample)) sample = 0.0f;
      const float low = state->low_pass_state[channel] +
          low_alpha * (sample - state->low_pass_state[channel]);
      state->low_pass_state[channel] = low;

      const float high_low = state->high_cut_state[channel] +
          high_alpha * (sample - state->high_cut_state[channel]);
      state->high_cut_state[channel] = high_low;

      const float high = sample - high_low;
      const float mid = high_low - low;

      const float output = low * current_bass + mid * current_mid + high * current_high;
      // Bound post-EQ PCM BEFORE applying the deck's fade coefficient. If an
      // upstream filter produces an over-range sample, clamping only after
      // the fade could erase the coefficient's headroom (e.g. 4.0 * 0.25
      // then clamp => 1.0). Pre-envelope clamping preserves the L1 mix budget.
      const float bounded_output = isfinite(output)
          ? fminf(1.0f, fmaxf(-1.0f, output))
          : 0.0f;
      const float faded = bounded_output * current_fade;
      // Defensive final clamp; current_fade is constrained to [0, 1].
      // This is sample-peak protection, not a reconstructed true-peak limiter.
      interleaved[index] = isfinite(faded)
          ? fminf(1.0f, fmaxf(-1.0f, faded))
          : 0.0f;
    }
  }

  state->current_bass_gain = current_bass;
  state->current_mid_gain = current_mid;
  state->current_high_gain = current_high;
  state->current_fade_gain = current_fade;
  return 1;
}
