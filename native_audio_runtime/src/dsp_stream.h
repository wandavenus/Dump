// Per-stream constants — Production hardening pass.
//
// ── Why this exists ───────────────────────────────────────────────────────────
//
// Media3PlaybackService.kt runs TWO concurrently-playing ExoPlayer instances
// during a crossfade (see the dual-player-architecture design): the active
// player and the standby player that is being faded in. Both instances share
// the SAME libnative_audio_runtime.so process image, and therefore the SAME
// global/static DSP processor singletons (comp_processor.c, limiter_processor.c,
// crossfeed_processor.c, loudness_processor.c, ...).
//
// Before this header existed, every processor's AUDIO-THREAD-ONLY runtime
// state (envelope followers, look-ahead delay buffers, biquad filter
// histories, loudness gating accumulators) was a single unsynchronized
// instance. When both ExoPlayer audio threads called into the pipeline
// concurrently during a crossfade, they read and wrote that single instance
// from two different threads with no synchronization at all — a genuine data
// race (undefined behavior in C, and in practice audibly corrupted envelope/
// filter state torn between two unrelated audio streams).
//
// ── The fix ───────────────────────────────────────────────────────────────────
//
// Every processor's state is split into two categories:
//
//   1. SHARED CONTROL-PLANE state — the user-configured parameters (e.g.
//      compressor threshold/ratio, limiter ceiling, PEQ band coefficients,
//      target LUFS). There is only one set of user-facing knobs in the whole
//      app, and both streams are meant to apply the SAME configured settings
//      — so this remains shared, written by the control thread and consumed
//      by both audio threads via the existing dirty-flag double-buffer
//      protocol (now per-stream — see point 2 below for why).
//
//   2. PER-STREAM RUNTIME state — everything derived from and mutated by the
//      actual audio flowing through a specific stream (envelope levels,
//      delay-line contents, filter histories, gating ring buffers/sums).
//      This MUST be isolated per stream, or one stream's audio would corrupt
//      the acoustic history of the other's.
//
// A fixed-size array of NAR_DSP_MAX_STREAMS runtime-state slots replaces each
// former single-instance struct; every process() call is now told which slot
// to use via an explicit `stream_slot` parameter (see dsp_processor.h and
// dsp_pipeline.h). No heap allocation, no locks — purely a wider static array
// indexed by an integer, exactly as fast as before per stream.
//
// The double-buffer "dirty" flag ALSO became per-stream (dirty[stream]),
// not shared: if it were a single shared flag, whichever stream's audio
// thread happened to observe dirty==1 first would clear it, and the OTHER
// stream would permanently miss that parameter update until the next one
// arrives. Each stream now independently notices and consumes new pending
// parameters exactly once.
//
// ── Why exactly 2 ─────────────────────────────────────────────────────────────
//
// Media3PlaybackService.kt's dual-player crossfade architecture never runs
// more than one primary + one standby/secondary player concurrently (see
// dual-player-architecture memory). NAR_DSP_MAX_STREAMS is a compile-time
// constant, not a dynamic pool, matching that fixed topology exactly —
// keeping every per-stream array a small, cache-friendly, statically-sized
// member with zero allocation.

#ifndef NATIVE_AUDIO_RUNTIME_DSP_STREAM_H_
#define NATIVE_AUDIO_RUNTIME_DSP_STREAM_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Maximum number of concurrently-processed audio streams. Stream 0 is
// always the "primary" caller (Dart's own nar_dsp_pipeline_process()/
// nar_dsp_pipeline_process_raw() calls, and any legacy single-stream JNI
// caller, both implicitly target slot 0). Stream 1 is the secondary/standby
// crossfade player.
#define NAR_DSP_MAX_STREAMS 2

// Defensively folds any out-of-range stream_slot (which should never
// legitimately happen — only two ExoPlayer instances ever call in) to slot
// 0, so a stray value from JNI can never index out of bounds into a
// processor's per-stream arrays. Safe to call on the audio thread — no
// branches on shared state, no side effects.
static inline int32_t nar_dsp_clamp_stream(int32_t stream_slot) {
  if (stream_slot < 0 || stream_slot >= NAR_DSP_MAX_STREAMS) return 0;
  return stream_slot;
}

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_DSP_STREAM_H_
