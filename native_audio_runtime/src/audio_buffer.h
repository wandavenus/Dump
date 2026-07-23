// AudioBuffer — reusable interleaved PCM buffer abstraction (Phase 4).
//
// A single native heap allocation per buffer, created and destroyed
// explicitly by the caller (Dart owns the lifecycle — see
// NativeAudioBuffer in the Dart layer). Designed for the DSP pipeline to
// process in place: no processor ever allocates a new buffer, they all
// read/write through nar_audio_buffer_data() on the SAME allocation.
//
// Ownership: a NarAudioBuffer* is owned by whoever called
// nar_audio_buffer_create() — exactly one nar_audio_buffer_destroy() call
// is required per buffer, and it must not be used afterward. The struct
// layout is opaque and private to audio_buffer.c; every other file
// (including other native_audio_runtime sources) only ever touches a
// buffer through these accessor functions, the same contract a future
// out-of-tree processor would have to follow too.
//
// Thread-safety: a NarAudioBuffer is NOT internally synchronized. It is
// designed to be owned by a single thread at a time as it flows through
// the pipeline (mirroring Media3/ExoPlayer's own single-audio-thread
// processing model) — concurrent read/write from multiple threads on the
// same buffer is the caller's responsibility to avoid, not this file's.

#ifndef NATIVE_AUDIO_RUNTIME_AUDIO_BUFFER_H_
#define NATIVE_AUDIO_RUNTIME_AUDIO_BUFFER_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Sample formats. Only FLOAT32 is implemented today — the entire DSP core
// (buffer, processor interface, gain processor) is designed around
// interleaved float32 so that future processors share one code path.
// INT16 is declared now as a forward-compatible placeholder (e.g. for a
// future stage that reads raw 16-bit PCM straight from a file before it
// ever reaches a float pipeline) and is rejected by
// nar_audio_buffer_create() until it is actually implemented.
typedef enum {
  NAR_SAMPLE_FORMAT_FLOAT32 = 0,
  NAR_SAMPLE_FORMAT_INT16 = 1,
} NarSampleFormat;

// Opaque handle. Struct layout lives in audio_buffer.c only.
typedef struct NarAudioBuffer NarAudioBuffer;

// Allocate an interleaved PCM buffer. `frame_count` starts equal to
// `capacity_frames` (i.e. "full") — call nar_audio_buffer_set_frame_count()
// to mark fewer valid frames (e.g. a short final block) without
// reallocating. Returns NULL on invalid arguments, an unsupported format,
// or allocation failure — check native_runtime_last_status() for which.
FFI_PLUGIN_EXPORT NarAudioBuffer* nar_audio_buffer_create(
    int32_t capacity_frames,
    int32_t channel_count,
    int32_t sample_rate,
    int32_t format);

// Free a buffer created by nar_audio_buffer_create(). Safe to call with
// NULL (no-op). Must be called exactly once per buffer.
FFI_PLUGIN_EXPORT void nar_audio_buffer_destroy(NarAudioBuffer* buffer);

// Direct pointer to the interleaved sample data — `capacity_frames *
// channel_count` float elements, channel-interleaved. Every reader/writer
// (Dart via Pointer.asTypedList, or a native processor) works through this
// SAME memory — there is no copy in or out. Returns NULL for a NULL buffer
// or a non-FLOAT32 buffer (not implemented yet).
FFI_PLUGIN_EXPORT float* nar_audio_buffer_data(NarAudioBuffer* buffer);

FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_capacity_frames(NarAudioBuffer* buffer);

FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_frame_count(NarAudioBuffer* buffer);

// Narrow (or restore) the number of valid frames. Must be in
// [0, capacity_frames]. Returns NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT
// otherwise, leaving the buffer's frame_count unchanged.
FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_set_frame_count(
    NarAudioBuffer* buffer, int32_t frame_count);

FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_channel_count(NarAudioBuffer* buffer);
FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_sample_rate(NarAudioBuffer* buffer);
FFI_PLUGIN_EXPORT int32_t nar_audio_buffer_format(NarAudioBuffer* buffer);

// Optional per-buffer timestamp (microseconds), for future callers that
// need to correlate a processed block back to a playback position. Not
// interpreted by the buffer or pipeline themselves — pure metadata.
FFI_PLUGIN_EXPORT int64_t nar_audio_buffer_timestamp_us(NarAudioBuffer* buffer);
FFI_PLUGIN_EXPORT void nar_audio_buffer_set_timestamp_us(
    NarAudioBuffer* buffer, int64_t timestamp_us);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_AUDIO_BUFFER_H_
