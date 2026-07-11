// AudioBuffer implementation — see audio_buffer.h for the contract.
//
// The full NarAudioBuffer struct layout lives in audio_buffer_internal.h so
// that other intra-package TUs (dsp_pipeline.c) can stack-allocate view buffers
// without heap allocation. External callers must use the opaque API only.

#include "audio_buffer_internal.h"  // includes audio_buffer.h + full struct

#include <stdlib.h>

#include "native_audio_runtime_internal.h"

FFI_PLUGIN_EXPORT NarAudioBuffer* nar_audio_buffer_create(
    int32_t capacity_frames,
    int32_t channel_count,
    int32_t sample_rate,
    int32_t format) {
  if (capacity_frames <= 0 || channel_count <= 0 || sample_rate <= 0) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT);
    return NULL;
  }
  if (format != NAR_SAMPLE_FORMAT_FLOAT32) {
    // INT16 is a declared-but-unimplemented placeholder (see header).
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_UNSUPPORTED_PLATFORM);
    return NULL;
  }

  NarAudioBuffer* buffer = (NarAudioBuffer*)calloc(1, sizeof(NarAudioBuffer));
  if (buffer == NULL) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_ALLOCATION_FAILED);
    return NULL;
  }

  size_t sample_count = (size_t)capacity_frames * (size_t)channel_count;
  buffer->data = (float*)calloc(sample_count, sizeof(float));
  if (buffer->data == NULL) {
    free(buffer);
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_ALLOCATION_FAILED);
    return NULL;
  }

  buffer->capacity_frames = capacity_frames;
  buffer->frame_count = capacity_frames;  // starts "full"
  buffer->channel_count = channel_count;
  buffer->sample_rate = sample_rate;
  buffer->format = format;
  buffer->timestamp_us = 0;

  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return buffer;
}

FFI_PLUGIN_EXPORT void nar_audio_buffer_destroy(NarAudioBuffer* buffer) {
  if (buffer == NULL) return;
  free(buffer->data);
  free(buffer);
}

FFI_PLUGIN_EXPORT float* nar_audio_buffer_data(NarAudioBuffer* buffer) {
  if (buffer == NULL || buffer->format != NAR_SAMPLE_FORMAT_FLOAT32) {
    return NULL;
  }
  return buffer->data;
}

FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_capacity_frames(NarAudioBuffer* buffer) {
  return buffer == NULL ? 0 : buffer->capacity_frames;
}

FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_frame_count(NarAudioBuffer* buffer) {
  return buffer == NULL ? 0 : buffer->frame_count;
}

FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_set_frame_count(
    NarAudioBuffer* buffer, int32_t frame_count) {
  if (buffer == NULL || frame_count < 0 || frame_count > buffer->capacity_frames) {
    nar_runtime_set_last_status(NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT);
    return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  }
  buffer->frame_count = frame_count;
  nar_runtime_set_last_status(NATIVE_RUNTIME_OK);
  return NATIVE_RUNTIME_OK;
}

FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_channel_count(NarAudioBuffer* buffer) {
  return buffer == NULL ? 0 : buffer->channel_count;
}

FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_sample_rate(NarAudioBuffer* buffer) {
  return buffer == NULL ? 0 : buffer->sample_rate;
}

FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_format(NarAudioBuffer* buffer) {
  return buffer == NULL ? -1 : buffer->format;
}

FFI_PLUGIN_EXPORT int64_t nar_audio_buffer_timestamp_us(NarAudioBuffer* buffer) {
  return buffer == NULL ? 0 : buffer->timestamp_us;
}

FFI_PLUGIN_EXPORT void nar_audio_buffer_set_timestamp_us(
    NarAudioBuffer* buffer, int64_t timestamp_us) {
  if (buffer == NULL) return;
  buffer->timestamp_us = timestamp_us;
}
