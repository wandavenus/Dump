// Parametric Equalizer Processor — Phase 5.
//
// A production-grade multi-band parametric EQ built on the Phase 4 DSP
// pipeline. Registers as "dsp.peq" after "dsp.gain" in the pipeline, so
// the signal flow inside NativeDspAudioProcessor is:
//
//   ExoPlayer PCM → dsp.gain → dsp.peq → StereoWidening → Sonic → AudioTrack
//
// Bands:
//   Up to NAR_PEQ_MAX_BANDS (32) bands, each independently enabled/disabled.
//   Each band is a second-order biquad (see biquad_filter.h) supporting all
//   seven topologies: Peak, Low Shelf, High Shelf, Low Pass, High Pass,
//   Band Pass, Notch.
//
// Runtime parameter updates (thread-safe, no playback interruptions):
//   Parameters are written to a "pending" coefficient struct on the control
//   thread. A dirty flag (C11 _Atomic, release/acquire) signals the audio
//   thread to swap pending → active at the start of the next process() call.
//   Coefficient computation (sinf/cosf/powf) runs on the control thread; the
//   audio thread only does a 20-byte struct copy, then the lock-free biquad
//   recurrence.
//
//   Note: the dirty-flag protocol provides acquire/release ordering, which
//   guarantees the audio thread sees a fully written "pending" whenever it
//   observes dirty==1. A concurrent second write to "pending" before the
//   audio thread finishes its 20-byte copy is a theoretical race with
//   near-zero probability; its audible consequence (if it ever occurred)
//   would be a single-buffer, imperceptible coefficient transient.
//
// Performance:
//   - Zero heap allocations in process().
//   - No locks on the audio thread (lock-free dirty-flag protocol).
//   - SIMD-ready inner loop (5 multiplies + 4 adds per sample per band;
//     auto-vectorized to NEON on arm64 by the NDK's Clang).
//   - Reusable state: reset() clears s1/s2 arrays (called on seek).
//   - Global bypass: zero-copy early return when all EQ is disabled.

#ifndef NATIVE_AUDIO_RUNTIME_PEQ_PROCESSOR_H_
#define NATIVE_AUDIO_RUNTIME_PEQ_PROCESSOR_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

// Maximum configurable bands. Dart must not exceed this.
#define NAR_PEQ_MAX_BANDS    32

// Maximum audio channels processed per band. Channels beyond this limit are
// silently passed through without EQ — in practice, music is mono/stereo (≤2).
#define NAR_PEQ_MAX_CHANNELS  8

// ── Lifecycle ──────────────────────────────────────────────────────────────────

// Register the PEQ processor with the DSP pipeline.
// Must be called AFTER nar_dsp_pipeline_init() and the gain processor.
// Idempotent: returns NATIVE_RUNTIME_ERROR_DUPLICATE_MODULE if already
// registered (safe to call after a hot restart).
FFI_PLUGIN_EXPORT int32_t nar_peq_processor_register_internal(void);

// ── Band configuration ─────────────────────────────────────────────────────────

// Configure a single EQ band. Computes biquad coefficients immediately on the
// calling thread (sinf/cosf/powf) and queues them for atomic swap into the
// audio thread's processing path.
//
// [band_index]  : 0 … NAR_PEQ_MAX_BANDS-1.
// [enabled]     : 1 = process this band, 0 = skip (zero-cost bypass).
// [filter_type] : NarBiquadType cast to int32_t (0=Peak … 6=Notch).
// [freq_hz]     : Centre/corner frequency in Hz. Clamped to (1, Fs/2).
// [q]           : Quality factor. Clamped to [0.001, 100].
// [gain_db]     : Gain in dBFS for Peak/Shelf. Ignored by LP/HP/BP/Notch.
// [sample_rate] : Current playback sample rate. Must match ExoPlayer's output.
//                 If ≤ 0, defaults to 48000 Hz (safe fallback).
//
// Thread-safe: may be called from any thread while process() is running.
// Returns NATIVE_RUNTIME_OK on success, or an error code.
FFI_PLUGIN_EXPORT int32_t nar_peq_set_band(
    int32_t band_index,
    int32_t enabled,
    int32_t filter_type,
    float   freq_hz,
    float   q,
    float   gain_db,
    float   sample_rate);

// Enable (1) or disable (0) a single band without recomputing coefficients.
// Thread-safe (atomic store). Returns NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT
// if band_index is out of range.
FFI_PLUGIN_EXPORT int32_t nar_peq_set_band_enabled(
    int32_t band_index, int32_t enabled);

// Returns 1 if the band is enabled, 0 if disabled.
// Returns NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT if out of range.
FFI_PLUGIN_EXPORT int32_t nar_peq_get_band_enabled(int32_t band_index);

// ── Global bypass ──────────────────────────────────────────────────────────────

// Enable (bypass=1) or disable (bypass=0) the global PEQ bypass.
// When bypassed, process() returns immediately without touching any sample
// (true zero-copy pass-through). Thread-safe.
FFI_PLUGIN_EXPORT void nar_peq_set_bypass(int32_t bypass);

// Returns 1 if global bypass is active, 0 otherwise. Thread-safe.
FFI_PLUGIN_EXPORT int32_t nar_peq_get_bypass(void);

// ── Metadata ───────────────────────────────────────────────────────────────────

// Maximum number of configurable bands (compile-time constant = 32).
FFI_PLUGIN_EXPORT int32_t nar_peq_max_bands(void);

// Number of bands currently configured (i.e. highest band_index passed to
// nar_peq_set_band(), plus one). Zero until the first nar_peq_set_band call.
FFI_PLUGIN_EXPORT int32_t nar_peq_band_count(void);

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_AUDIO_RUNTIME_PEQ_PROCESSOR_H_
