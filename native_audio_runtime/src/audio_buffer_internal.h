// audio_buffer_internal.h
//
// INTERNAL USE ONLY — do not include this header from outside
// native_audio_runtime/src/. It exposes the full NarAudioBuffer struct layout
// so that intra-package translation units (dsp_pipeline.c) can stack-allocate
// view buffers without calling nar_audio_buffer_create() (heap allocation).
//
// External callers (JNI, Dart FFI) must use the opaque NarAudioBuffer* API
// declared in audio_buffer.h.

#ifndef NATIVE_AUDIO_RUNTIME_AUDIO_BUFFER_INTERNAL_H_
#define NATIVE_AUDIO_RUNTIME_AUDIO_BUFFER_INTERNAL_H_

#include <stdint.h>

#include "audio_buffer.h"

// Full struct definition — single source of truth shared by audio_buffer.c
// and any internal translation unit that needs to stack-allocate a view.
struct NarAudioBuffer {
  float*  data;             // heap-allocated: capacity_frames * channel_count floats
  int32_t capacity_frames;
  int32_t frame_count;      // valid frames, <= capacity_frames
  int32_t channel_count;
  int32_t sample_rate;
  int32_t format;           // NarSampleFormat enum value
  int64_t timestamp_us;     // optional playback-position metadata
};

#endif  // NATIVE_AUDIO_RUNTIME_AUDIO_BUFFER_INTERNAL_H_
