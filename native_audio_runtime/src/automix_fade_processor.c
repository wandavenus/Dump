#include "automix_fade_processor.h"

#include <limits.h>
#include <math.h>
#include <stddef.h>
#include <stdatomic.h>
#include <string.h>

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

#define NAR_AUTOMIX_FADE_PI 3.14159265358979323846f
#define NAR_AUTOMIX_FADE_MIN_GAMMA 0.6f
#define NAR_AUTOMIX_FADE_MAX_GAMMA 1.6f
#define NAR_AUTOMIX_FADE_MAX_FINITE 0x1.fffffep+127f

typedef struct NarAutomixFadeState {
  _Atomic int32_t configured;
  _Atomic int32_t failed;
  _Atomic int32_t armed;
  _Atomic int32_t direction;
  _Atomic int64_t pending_position_ms;
  _Atomic uint32_t pending_position_generation;
  _Atomic int64_t pending_start_position_ms;
  _Atomic int64_t pending_duration_ms;
  _Atomic uint32_t plan_generation;
  _Atomic int64_t start_frame;
  _Atomic int64_t duration_frames;
  _Atomic float gamma;
  _Atomic float outgoing_trim;
  _Atomic float incoming_trim;
  _Atomic int64_t processed_frames;
  _Atomic uint64_t process_calls;
  _Atomic float current_gain;

  // The fields below are audio-thread-owned after configure().
  int32_t sample_rate;
  int32_t channel_count;
  int64_t frame_cursor;
  uint32_t applied_position_generation;
  uint32_t applied_plan_generation;
  int32_t active_armed;
  int32_t active_direction;
  int64_t active_start_frame;
  int64_t active_duration_frames;
  float active_gamma;
  float active_outgoing_trim;
  float active_incoming_trim;
} NarAutomixFadeState;

static NarAutomixFadeState g_states[NAR_AUTOMIX_FADE_STREAM_COUNT];

static int valid_stream_slot(int32_t stream_slot) {
  return stream_slot >= 0 && stream_slot < NAR_AUTOMIX_FADE_STREAM_COUNT;
}

static int valid_channel_count(int32_t channel_count) {
  return channel_count > 0 && channel_count <= NAR_AUTOMIX_FADE_MAX_CHANNELS;
}

static float clamp01(float value, float fallback) {
  if (!isfinite(value)) return fallback;
  if (value < 0.0f) return 0.0f;
  if (value > 1.0f) return 1.0f;
  return value;
}

static float normalize_gamma(float gamma) {
  if (!isfinite(gamma)) return 1.0f;
  if (gamma < NAR_AUTOMIX_FADE_MIN_GAMMA) return NAR_AUTOMIX_FADE_MIN_GAMMA;
  if (gamma > NAR_AUTOMIX_FADE_MAX_GAMMA) return NAR_AUTOMIX_FADE_MAX_GAMMA;
  return gamma;
}

static int checked_ms_to_frames(int64_t position_ms, int32_t sample_rate,
                                int64_t* frames) {
  if (frames == NULL || position_ms < 0 || sample_rate <= 0) return 0;
  if (position_ms > INT64_MAX / (int64_t)sample_rate) return 0;
  const int64_t numerator = position_ms * (int64_t)sample_rate;
  *frames = numerator / 1000;
  return 1;
}

static float fade_progress(int64_t frame, int64_t start_frame,
                           int64_t duration_frames) {
  if (frame <= start_frame) return 0.0f;
  if (duration_frames <= 0 || frame - start_frame >= duration_frames) {
    return 1.0f;
  }
  const double progress = (double)(frame - start_frame) /
      (double)duration_frames;
  if (!isfinite(progress)) return 1.0f;
  return (float)fmin(fmax(progress, 0.0), 1.0);
}

static float compute_gain(float progress, float gamma, float outgoing_trim,
                          float incoming_trim, int32_t direction) {
  const float t = fminf(fmaxf(progress, 0.0f), 1.0f);
  const float g = normalize_gamma(gamma);
  const float out_trim = clamp01(outgoing_trim, 1.0f);
  const float in_trim = clamp01(incoming_trim, 1.0f);
  const float shaped = g == 1.0f ? t : powf(t, 1.0f / g);
  const float theta = shaped * (NAR_AUTOMIX_FADE_PI * 0.5f);
  const float attack = t < 0.25f ? t / 0.25f : 1.0f;
  const float outgoing_trim_now = 1.0f - (1.0f - out_trim) * attack;
  const float release = t <= 0.75f ? 0.0f : (t - 0.75f) / 0.25f;
  const float incoming_trim_now = in_trim + (1.0f - in_trim) * release;

  float outgoing = outgoing_trim_now * cosf(theta);
  float incoming = incoming_trim_now * sinf(theta);
  outgoing = clamp01(outgoing, 0.0f);
  incoming = clamp01(incoming, 0.0f);

  const float sum = outgoing + incoming;
  if (sum > 1.0f) {
    const float scale = 1.0f / sum;
    outgoing *= scale;
    incoming *= scale;
  }
  return direction == NAR_AUTOMIX_FADE_INCOMING ? incoming : outgoing;
}

static float process_sample(float sample, float gain) {
  // A malformed float must not poison the downstream Media3 sink. This is the
  // same fail-open sanitization contract used by the existing native tone DSP.
  if (!isfinite(sample)) return 0.0f;
  const float output = sample * gain;
  return isfinite(output) ? output : 0.0f;
}

static void apply_pending_position(NarAutomixFadeState* state) {
  const uint32_t generation = atomic_load_explicit(
      &state->pending_position_generation, memory_order_acquire);
  if (generation == state->applied_position_generation) return;

  const int64_t position_ms = atomic_load_explicit(
      &state->pending_position_ms, memory_order_relaxed);
  int64_t position_frames = 0;
  if (checked_ms_to_frames(position_ms, state->sample_rate, &position_frames)) {
    state->frame_cursor = position_frames;
    atomic_store_explicit(&state->processed_frames, position_frames,
                          memory_order_release);
  }
  // A timeline update normally cancels the current fade. The exception is a
  // freshly armed plan submitted after that update but before the next audio
  // block; its newer plan generation must survive so the common
  // set-position-then-arm sequence is deterministic.
  const uint32_t plan_generation = atomic_load_explicit(
      &state->plan_generation, memory_order_acquire);
  if (plan_generation == state->applied_plan_generation) {
    state->active_armed = 0;
    atomic_store_explicit(&state->armed, 0, memory_order_release);
    atomic_store_explicit(&state->current_gain, 1.0f, memory_order_release);
  }
  state->applied_position_generation = generation;
}

static void load_plan_if_changed(NarAutomixFadeState* state) {
  const uint32_t generation =
      atomic_load_explicit(&state->plan_generation, memory_order_acquire);
  if (generation == state->applied_plan_generation) return;

  state->active_armed = atomic_load_explicit(&state->armed,
                                             memory_order_acquire);
  if (state->active_armed) {
    state->active_direction = atomic_load_explicit(
        &state->direction, memory_order_relaxed);
    state->active_start_frame = atomic_load_explicit(
        &state->start_frame, memory_order_relaxed);
    state->active_duration_frames = atomic_load_explicit(
        &state->duration_frames, memory_order_relaxed);
    state->active_gamma = atomic_load_explicit(&state->gamma,
                                               memory_order_relaxed);
    state->active_outgoing_trim = atomic_load_explicit(
        &state->outgoing_trim, memory_order_relaxed);
    state->active_incoming_trim = atomic_load_explicit(
        &state->incoming_trim, memory_order_relaxed);
  }
  state->applied_plan_generation = generation;
}

#if defined(__aarch64__)
static float32x4_t sanitize_vector(float32x4_t samples) {
  const float32x4_t abs_samples = vabsq_f32(samples);
  const float32x4_t max_finite = vdupq_n_f32(NAR_AUTOMIX_FADE_MAX_FINITE);
  const uint32x4_t finite = vcleq_f32(abs_samples, max_finite);
  return vbslq_f32(finite, samples, vdupq_n_f32(0.0f));
}

static void process_mono_neon(float* pcm, const float* gains, int32_t frames) {
  for (int32_t offset = 0; offset < frames; offset += 4) {
    const int32_t count = frames - offset < 4 ? frames - offset : 4;
    if (count == 4) {
      float32x4_t samples = vld1q_f32(pcm + offset);
      samples = sanitize_vector(samples);
      samples = vmulq_f32(samples, vld1q_f32(gains + offset));
      samples = sanitize_vector(samples);
      vst1q_f32(pcm + offset, samples);
    } else {
      for (int32_t i = 0; i < count; ++i) {
        pcm[offset + i] = process_sample(pcm[offset + i], gains[offset + i]);
      }
    }
  }
}

static void process_stereo_neon(float* pcm, const float* gains,
                                int32_t frames) {
  for (int32_t offset = 0; offset < frames; offset += 2) {
    const int32_t count = frames - offset < 2 ? frames - offset : 2;
    if (count == 2) {
      float gain_values[4] = {
          gains[offset], gains[offset], gains[offset + 1], gains[offset + 1],
      };
      float32x4_t samples = vld1q_f32(pcm + offset * 2);
      samples = sanitize_vector(samples);
      samples = vmulq_f32(samples, vld1q_f32(gain_values));
      samples = sanitize_vector(samples);
      vst1q_f32(pcm + offset * 2, samples);
    } else {
      pcm[offset * 2] = process_sample(pcm[offset * 2], gains[offset]);
      pcm[offset * 2 + 1] = process_sample(pcm[offset * 2 + 1], gains[offset]);
    }
  }
}
#endif

FFI_PLUGIN_EXPORT int32_t nar_automix_fade_configure(
    int32_t stream_slot, int32_t sample_rate, int32_t channel_count) {
  if (!valid_stream_slot(stream_slot) || sample_rate <= 0 ||
      !valid_channel_count(channel_count)) {
    return 0;
  }

  NarAutomixFadeState* state = &g_states[stream_slot];
  const int64_t pending_position_ms = atomic_load_explicit(
      &state->pending_position_ms, memory_order_relaxed);
  int64_t initial_frame = 0;
  if (!checked_ms_to_frames(pending_position_ms, sample_rate, &initial_frame)) {
    initial_frame = 0;
  }

  state->sample_rate = sample_rate;
  state->channel_count = channel_count;
  state->frame_cursor = initial_frame;
  state->applied_position_generation = atomic_load_explicit(
      &state->pending_position_generation, memory_order_acquire);
  state->applied_plan_generation = atomic_load_explicit(
      &state->plan_generation, memory_order_acquire);
  state->active_armed = atomic_load_explicit(&state->armed,
                                             memory_order_acquire);
  state->active_direction = atomic_load_explicit(&state->direction,
                                                 memory_order_relaxed);
  state->active_start_frame = atomic_load_explicit(&state->start_frame,
                                                   memory_order_relaxed);
  state->active_duration_frames = atomic_load_explicit(
      &state->duration_frames, memory_order_relaxed);
  state->active_gamma = atomic_load_explicit(&state->gamma,
                                             memory_order_relaxed);
  state->active_outgoing_trim = atomic_load_explicit(
      &state->outgoing_trim, memory_order_relaxed);
  state->active_incoming_trim = atomic_load_explicit(
      &state->incoming_trim, memory_order_relaxed);

  if (state->active_armed) {
    const int64_t pending_start_ms = atomic_load_explicit(
        &state->pending_start_position_ms, memory_order_relaxed);
    const int64_t pending_duration_ms = atomic_load_explicit(
        &state->pending_duration_ms, memory_order_relaxed);
    int64_t pending_start_frame = 0;
    int64_t pending_duration_frames = 0;
    if (checked_ms_to_frames(pending_start_ms, sample_rate,
                             &pending_start_frame) &&
        checked_ms_to_frames(pending_duration_ms, sample_rate,
                             &pending_duration_frames) &&
        pending_duration_frames > 0) {
      if (pending_start_frame < initial_frame) {
        pending_start_frame = initial_frame;
      }
      atomic_store_explicit(&state->start_frame, pending_start_frame,
                            memory_order_relaxed);
      atomic_store_explicit(&state->duration_frames, pending_duration_frames,
                            memory_order_relaxed);
      state->active_start_frame = pending_start_frame;
      state->active_duration_frames = pending_duration_frames;
    } else {
      state->active_armed = 0;
      atomic_store_explicit(&state->armed, 0, memory_order_release);
    }
  }

  atomic_store_explicit(&state->failed, 0, memory_order_release);
  atomic_store_explicit(&state->processed_frames, initial_frame,
                        memory_order_release);
  atomic_store_explicit(&state->process_calls, 0, memory_order_release);
  atomic_store_explicit(&state->current_gain, 1.0f, memory_order_release);
  atomic_store_explicit(&state->configured, 1, memory_order_release);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_fade_set_timeline_position_ms(
    int32_t stream_slot, int64_t position_ms) {
  if (!valid_stream_slot(stream_slot) || position_ms < 0) return 0;
  NarAutomixFadeState* state = &g_states[stream_slot];
  atomic_store_explicit(&state->pending_position_ms, position_ms,
                        memory_order_relaxed);
  atomic_fetch_add_explicit(&state->pending_position_generation, 1,
                            memory_order_release);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_fade_arm(
    int32_t stream_slot, int64_t start_position_ms, int64_t duration_ms,
    float gamma, float outgoing_trim, float incoming_trim,
    int32_t direction) {
  if (!valid_stream_slot(stream_slot) || start_position_ms < 0 ||
      duration_ms <= 0 ||
      (direction != NAR_AUTOMIX_FADE_OUTGOING &&
       direction != NAR_AUTOMIX_FADE_INCOMING)) {
    return 0;
  }
  NarAutomixFadeState* state = &g_states[stream_slot];
  if (atomic_load_explicit(&state->failed, memory_order_acquire)) return 0;

  const int32_t sample_rate = state->sample_rate;
  if (sample_rate <= 0) {
    // The processor may not have configured yet. Keep the plan in media-time
    // units by using the pending fields only after configure; the JNI facade
    // will retry readiness before activating native output.
    atomic_store_explicit(&state->start_frame, start_position_ms,
                          memory_order_relaxed);
    atomic_store_explicit(&state->duration_frames, duration_ms,
                          memory_order_relaxed);
  } else {
    int64_t start_frame = 0;
    int64_t duration_frames = 0;
    if (!checked_ms_to_frames(start_position_ms, sample_rate, &start_frame) ||
        !checked_ms_to_frames(duration_ms, sample_rate, &duration_frames) ||
        duration_frames <= 0) {
      return 0;
    }
    atomic_store_explicit(&state->start_frame, start_frame,
                          memory_order_relaxed);
    atomic_store_explicit(&state->duration_frames, duration_frames,
                          memory_order_relaxed);
    int64_t cursor = atomic_load_explicit(&state->processed_frames,
                                          memory_order_acquire);
    const uint32_t pending_position_generation = atomic_load_explicit(
        &state->pending_position_generation, memory_order_acquire);
    const uint32_t applied_position_generation =
        state->applied_position_generation;
    if (pending_position_generation != applied_position_generation) {
      const int64_t pending_position_ms = atomic_load_explicit(
          &state->pending_position_ms, memory_order_relaxed);
      (void)checked_ms_to_frames(pending_position_ms, sample_rate, &cursor);
    }
    // The audio sink may already have decoded ahead of the controller's
    // audible position. Start the envelope at the next PCM frame rather than
    // rejecting the plan; rejecting here would unnecessarily switch to the
    // coarser Kotlin fallback exactly when buffered playback is healthy.
    if (start_frame < cursor) start_frame = cursor;
    atomic_store_explicit(&state->start_frame, start_frame,
                          memory_order_relaxed);
  }

  atomic_store_explicit(&state->pending_start_position_ms, start_position_ms,
                        memory_order_relaxed);
  atomic_store_explicit(&state->pending_duration_ms, duration_ms,
                        memory_order_relaxed);

  atomic_store_explicit(&state->direction, direction, memory_order_relaxed);
  atomic_store_explicit(&state->gamma, normalize_gamma(gamma),
                        memory_order_relaxed);
  atomic_store_explicit(&state->outgoing_trim, clamp01(outgoing_trim, 1.0f),
                        memory_order_relaxed);
  atomic_store_explicit(&state->incoming_trim, clamp01(incoming_trim, 1.0f),
                        memory_order_relaxed);
  atomic_store_explicit(&state->armed, 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&state->plan_generation, 1, memory_order_release);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_fade_disarm(int32_t stream_slot) {
  if (!valid_stream_slot(stream_slot)) return 0;
  NarAutomixFadeState* state = &g_states[stream_slot];
  atomic_store_explicit(&state->armed, 0, memory_order_relaxed);
  atomic_fetch_add_explicit(&state->plan_generation, 1, memory_order_release);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_fade_reset(int32_t stream_slot) {
  if (!valid_stream_slot(stream_slot)) return 0;
  NarAutomixFadeState* state = &g_states[stream_slot];
  atomic_store_explicit(&state->armed, 0, memory_order_relaxed);
  atomic_store_explicit(&state->failed, 0, memory_order_release);
  atomic_store_explicit(&state->current_gain, 1.0f, memory_order_release);
  atomic_fetch_add_explicit(&state->plan_generation, 1, memory_order_release);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_fade_process(
    float* interleaved, int32_t frame_count, int32_t channel_count,
    int32_t stream_slot) {
  if (interleaved == NULL || frame_count <= 0 ||
      !valid_stream_slot(stream_slot) || !valid_channel_count(channel_count)) {
    return 0;
  }
  NarAutomixFadeState* state = &g_states[stream_slot];
  if (!atomic_load_explicit(&state->configured, memory_order_acquire) ||
      channel_count != state->channel_count || state->sample_rate <= 0) {
    atomic_store_explicit(&state->failed, 1, memory_order_release);
    return 0;
  }

  apply_pending_position(state);
  load_plan_if_changed(state);

  if (!state->active_armed) {
    for (int32_t frame = 0; frame < frame_count; ++frame) {
      const size_t base = (size_t)frame * (size_t)channel_count;
      for (int32_t channel = 0; channel < channel_count; ++channel) {
        interleaved[base + (size_t)channel] =
            process_sample(interleaved[base + (size_t)channel], 1.0f);
      }
    }
    state->frame_cursor += frame_count;
    atomic_store_explicit(&state->processed_frames, state->frame_cursor,
                          memory_order_release);
    atomic_store_explicit(&state->current_gain, 1.0f, memory_order_release);
    atomic_fetch_add_explicit(&state->process_calls, 1, memory_order_relaxed);
    return 1;
  }

  float gains[4];
  int32_t gain_count = 0;
  for (int32_t frame = 0; frame < frame_count; ++frame) {
    const int64_t absolute_frame = state->frame_cursor + frame;
    float gain = 1.0f;
    if (state->active_armed) {
      const float progress = fade_progress(
          absolute_frame, state->active_start_frame,
          state->active_duration_frames);
      gain = compute_gain(progress, state->active_gamma,
                          state->active_outgoing_trim,
                          state->active_incoming_trim,
                          state->active_direction);
    }
    gains[gain_count++] = gain;

#if !defined(__aarch64__)
    const size_t base = (size_t)frame * (size_t)channel_count;
    for (int32_t channel = 0; channel < channel_count; ++channel) {
      interleaved[base + (size_t)channel] =
          process_sample(interleaved[base + (size_t)channel], gain);
    }
#else
    // The NEON block below consumes four frame gains. Other channel counts use
    // the scalar loop so every channel in a frame receives the same coefficient.
    if (channel_count != 1 && channel_count != 2) {
      const size_t base = (size_t)frame * (size_t)channel_count;
      for (int32_t channel = 0; channel < channel_count; ++channel) {
        interleaved[base + (size_t)channel] =
            process_sample(interleaved[base + (size_t)channel], gain);
      }
    }
#endif

    if (gain_count == 4 || frame == frame_count - 1) {
#if defined(__aarch64__)
      const int32_t start = frame - gain_count + 1;
      if (channel_count == 1) {
        process_mono_neon(interleaved + start, gains, gain_count);
      } else if (channel_count == 2) {
        process_stereo_neon(interleaved + start * 2, gains, gain_count);
      }
#endif
      gain_count = 0;
    }
  }

  state->frame_cursor += frame_count;
  atomic_store_explicit(&state->processed_frames, state->frame_cursor,
                        memory_order_release);
  atomic_store_explicit(&state->current_gain,
                        gains[(frame_count - 1) % 4], memory_order_release);
  atomic_fetch_add_explicit(&state->process_calls, 1, memory_order_relaxed);
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nar_automix_fade_get_status(
    int32_t stream_slot, NarAutomixFadeStatus* status) {
  if (!valid_stream_slot(stream_slot) || status == NULL) return 0;
  const NarAutomixFadeState* state = &g_states[stream_slot];
  status->configured = atomic_load_explicit(&state->configured,
                                            memory_order_acquire);
  status->armed = atomic_load_explicit(&state->armed, memory_order_acquire);
  status->failed = atomic_load_explicit(&state->failed, memory_order_acquire);
  status->processed_frames = atomic_load_explicit(&state->processed_frames,
                                                  memory_order_acquire);
  status->process_calls = atomic_load_explicit(&state->process_calls,
                                               memory_order_acquire);
  status->current_gain = atomic_load_explicit(&state->current_gain,
                                              memory_order_acquire);
  return 1;
}
