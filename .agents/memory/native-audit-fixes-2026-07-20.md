---
name: Native Audit Fixes 2026-07-20
description: Durable rules and patterns from fixing all 14 findings in Native_Audit_Merged_2026-07-20.md
---

# Native Audit Fixes — Durable Patterns

## Per-stream gain in replaygain_processor.c (NAR-4)
`_gain_bits` is now `_gain_bits[NAR_DSP_MAX_STREAMS]`. The new API
`nar_replaygain_set_gain_for_stream(stream_slot, gain_db, peak, clip)` must be
called by Dart `_applyReplayGain` once crossfade code tracks stream slot per
track. The old `nar_replaygain_set_gain()` sets both slots (backward compat).

**Why:** During crossfade, two tracks play concurrently with different RG values;
a shared knob means the "last-write-wins" track corrupts the other stream's gain.

## nar_loudness_reset_stream() added (NAR-5)
New public API for per-stream loudness reset. Dart should call this (with correct
stream_slot) instead of always `nar_loudness_reset()` once crossfade code is
stream-aware. `nar_loudness_reset()` remains stream-0-only for backward compat.

## FsyncGuard::Fd() + RestoreMetadataRegionFd verification
After `stream.insert()`, pread 4 bytes back on the dup'd fd and compare with
`backup.bytes[0..3]`. Mismatch → return `kWriteFailure` before fsync. TagLib
insert() has no error return; this is the only way to detect silent I/O failures.
Requires `<cstring>` include in tag_writer.cpp.

## steady_clock removed from stretch_jni.cpp audio thread
`std::chrono::steady_clock::now()` removed from `nativeProcess()` hot path.
Replaced with `uint64_t totalFramesProcessed` counter in StretchHandle.
Log interval = `sampleRate * 2.0f` frames (~2 seconds at any SR).
`sampleRate` stored in StretchHandle at `nativeCreate` time.

## ensureCapacity() pre-warmed in nativeCreate (stretch_jni.cpp)
`handle->ensureCapacity(8192, 8192)` called once in `nativeCreate()` on the
Kotlin worker thread. Prevents any heap allocation in ensureCapacity() on the
audio thread for typical ExoPlayer buffer sizes (≤ 4096 frames).

## gain_processor.c — powf moved to control thread (NAR-1)
`_gain_linear_bits` atomic added alongside `_gain_db_bits`.
`powf(10, db/20)` computed only in `nar_gain_processor_set_gain_db()` and stored.
Audio thread only does one additional atomic load — zero transcendentals on hot path.
`_gain_init()` stores `1.0f` (unity) into `_gain_linear_bits`.

## dsp_pipeline.c process_stream guard (NAR-2)
`nar_dsp_pipeline_process_stream()` now has same `_initialized` check as
`process_raw_stream()`. Belt-and-suspenders for architectural invariant
(ExoPlayer stops audio thread before dispose). Converts potential NULL vtable
deref into clean fail-open.

## arm64 data-race acknowledged pattern (NAR-3)
The transient-bypass pattern in loudness_processor.c (set _bypass=1, reset state,
restore _bypass=0) has a theoretical race window but is safe on arm64:
aligned scalar accesses (float/double/int32) are hardware-atomic (ARMv8-A §B2.2).
Worst: one buffer (~10ms) of stale gain, self-corrects in ≤400ms. Seqlock would
require a read-lock on the entire audio hot-path — rejected.

## 15 JNI LocalRef leaks in replaygain_jni.cpp
PackSnapshot: delete `string_class` after NewObjectArray; store each `jstring`
in a local var, call SetObjectArrayElement, then DeleteLocalRef.
PackWriteEnvelope: delete `object_class`, `integer_class`, `code_obj`,
`snap_arr`, `region_bytes` each after SetObjectArrayElement.

## EburAnalyzer::ChannelCount() added
New public const accessor for `channels_` field. Used by nativeAddFramesShort
bounds check: `frame_count > array_len / channel_count` → return JNI_FALSE before
GetShortArrayElements. Prevents out-of-bounds read on corrupt frame_count.

## Dead code removed
- `enum class ErrorCode` in jni_common.h — duplicate of WriteResult, never used
- `std::string path` in WriteRequest struct — never set or read by fd-based API
