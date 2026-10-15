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

static NarAutomixToneState g_states[NAR_AUTOMIX_TONE_STREAM_COUNT];
static _Atomic float g_target_bass[NAR_AUTOMIX_TONE_STREAM_COUNT] = {1.0f, 1.0f};
static _Atomic float g_target_high[NAR_AUTOMIX_TONE_STREAM_COUNT] = {1.0f, 1.0f};

#if defined(__aarch64__)
extern void nar_automix_tone_process_stereo_neon(
    float* interleaved, int32_t frame_count, NarAutomixToneState* state,
    float target_bass, float target_high);
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
  state->current_high_gain =
      atomic_load_explicit(&g_target_high[stream_slot], memory_order_relaxed);
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

FFI_PLUGIN_EXPORT int32_t nar_automix_tone_set_high_gain(
    int32_t stream_slot, float gain) {
  if (!valid_stream_slot(stream_slot)) return 0;
  atomic_store_explicit(&g_target_high[stream_slot], clamp_gain(gain),
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
  state->current_high_gain =
      atomic_load_explicit(&g_target_high[stream_slot], memory_order_relaxed);
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
  const float target_high =
      atomic_load_explicit(&g_target_high[stream_slot], memory_order_relaxed);

#if defined(__aarch64__)
  if (channel_count == 2) {
    nar_automix_tone_process_stereo_neon(
        interleaved, frame_count, state, target_bass, target_high);
    return 1;
  }
#endif

  float current_bass = state->current_bass_gain;
  float current_high = state->current_high_gain;
  const float gain_alpha = state->gain_smoothing_alpha;
  const float low_alpha = state->low_pass_alpha;
  const float high_alpha = state->high_cut_alpha;

  for (int32_t frame = 0; frame < frame_count; ++frame) {
    current_bass += (target_bass - current_bass) * gain_alpha;
    current_high += (target_high - current_high) * gain_alpha;
    for (int32_t channel = 0; channel < channel_count; ++channel) {
      const size_t index = (size_t)frame * channel_count + channel;
      float sample = interleaved[index];
      if (!isfinite(sample)) sample = 0.0f;
      const float low = state->low_pass_state[channel] +
          low_alpha * (sample - state->low_pass_state[channel]);
      state->low_pass_state[channel] = low;
      const float bass_adjusted = sample + low * (current_bass - 1.0f);
      const float high_low = state->high_cut_state[channel] +
          high_alpha * (bass_adjusted - state->high_cut_state[channel]);
      state->high_cut_state[channel] = high_low;
      const float output =
          high_low + (bass_adjusted - high_low) * current_high;
      interleaved[index] = isfinite(output) ? output : 0.0f;
    }
  }

  state->current_bass_gain = current_bass;
  state->current_high_gain = current_high;
  return 1;
}
