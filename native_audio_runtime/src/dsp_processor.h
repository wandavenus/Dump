// Generic DSP processor contract (Phase 4).
//
// This header defines the ONE interface every native DSP processor must
// implement — today that's only gain_processor.c, but every future
// processor (parametric EQ, compressor, resampler, ...) reuses this exact
// struct, never a bespoke one. It is an internal (native-only) contract:
// Dart never sees a NarDspProcessorVTable/Descriptor directly, it only
// ever calls the functions exported from dsp_pipeline.h, which drives
// processors registered through this struct.
//
// Lifecycle (mirrors native_audio_runtime.h's overall contract):
//   init()     — called once, by nar_dsp_pipeline_register_internal(),
//                only while the runtime is NAR_STATE_INITIALIZED. May
//                fail; a failed init aborts the registration (the
//                processor is NOT added to the chain).
//   process()  — called for every buffer that flows through the pipeline
//                WHILE this processor is enabled. The pipeline itself
//                skips disabled processors entirely — process() is not
//                even invoked, never mind called-and-early-returned
//                (that's the difference between the pipeline's
//                enable/disable and a processor's own optional "bypass"
//                concept, e.g. gain_processor.h's bypass flag). Must not
//                allocate on this path and must be safe to call
//                repeatedly, back-to-back, on different buffers.
//
//                `stream_slot` (production-hardening pass) identifies WHICH
//                concurrently-playing audio stream this buffer belongs to
//                — see dsp_stream.h for the full rationale. A processor
//                with no persistent per-sample state (e.g. gain,
//                replaygain, soft_clipper) may ignore it entirely. A
//                processor with persistent runtime state (envelope
//                followers, delay lines, filter histories) MUST index that
//                state by `stream_slot` (after clamping via
//                nar_dsp_clamp_stream()) rather than keeping one shared
//                instance, or concurrent streams will corrupt each other's
//                acoustic history. Shared, user-configured PARAMETERS
//                (thresholds, ratios, target LUFS, etc.) are unaffected —
//                they intentionally keep applying uniformly to every
//                stream.
//   reset()    — clear internal state for ALL streams (e.g. filter
//                history, envelope followers) without a full re-init. Safe
//                to call at any time after init(), whether enabled or not.
//                Reset is rare (seek/flush/dispose), not per-buffer, so
//                clearing every stream's state unconditionally is a safe
//                superset of the pre-hardening single-stream behavior.
//   dispose()  — release resources referenced by `self`. Called once, by
//                the pipeline's own dispose, in registration order. Must
//                NOT free `self` itself — the pipeline never allocated it
//                and does not own it (see dsp_pipeline.h); freeing the
//                descriptor's `self` pointer is the registering module's
//                own responsibility (see gain_processor.c for the
//                pattern: nar_gain_processor_unregister_internal()).
//
// Thread-safety: the pipeline only ever calls into a given processor from
// the single thread driving nar_dsp_pipeline_process()/reset() — a
// processor's process()/reset() do not need their own locking as long as
// they only touch their own state and the buffer they're handed. However,
// `enabled` (owned by the pipeline, not this struct) and any per-processor
// knob exposed directly to callers (e.g. gain's set_gain_db) MAY be called
// concurrently from another thread (a UI thread adjusting a slider) while
// process() is running — such knobs must use atomics internally, exactly
// like gain_processor.c does.

#ifndef NATIVE_AUDIO_RUNTIME_DSP_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_DSP_PROCESSOR_H_

#include <stdint.h>

#include "audio_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  // One-time setup. Returns a NativeRuntimeStatus code; anything other
  // than NATIVE_RUNTIME_OK aborts registration.
  int32_t (*init)(void* self);

  // Process `buffer` in place, in the given sample format/frame count, for
  // the given `stream_slot` (see dsp_stream.h). Returns a
  // NativeRuntimeStatus code. A non-OK return no longer aborts the pipeline
  // chain (production-hardening pass) — the pipeline now runs every
  // subsequent processor regardless, so a single failing effect can never
  // skip the limiter/soft-clipper safety net at the end of the chain. The
  // pipeline still surfaces the FIRST non-OK code it observed via
  // native_runtime_last_status()/the process call's own return value.
  int32_t (*process)(void* self, NarAudioBuffer* buffer, int32_t stream_slot);

  // Clear internal state. No return value — expected to always succeed.
  void (*reset)(void* self);

  // Release resources owned by `self`'s internals. Must not free `self`
  // itself (see ownership note above).
  void (*dispose)(void* self);

  // Algorithmic latency this processor introduces, in frames, at the
  // buffer's sample rate. 0 for purely sample-synchronous processors
  // (e.g. gain). Not consumed by anything in Phase 4 — a future
  // A/V-sync-aware caller would sum this across the chain.
  int32_t (*latency_frames)(void* self);
} NarDspProcessorVTable;

// A single entry to register into the pipeline.
typedef struct {
  // Stable id, e.g. "dsp.gain". Must be unique within the pipeline.
  const char* id;

  // Opaque state pointer, passed back into every vtable call as `self`.
  // Owned by the registering module (e.g. gain_processor.c), NOT by the
  // pipeline — see dispose() note above.
  void* self;

  // Function table implementing this processor's behavior. Must outlive
  // the registration (typically a `static const` in the processor's own
  // .c file, as gain_processor.c does).
  const NarDspProcessorVTable* vtable;
} NarDspProcessorDescriptor;

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_DSP_PROCESSOR_H_
