# Native Code Audit — Independent Verification Report

**Date:** 2026-07-19  
**Source audit:** `Audit/Native_code_audit.md` (dated 2026-07-18)  
**Method:** Every finding verified directly against current codebase; no assumption that the audit is correct.  
**Scope of new-pass scan:** All C files in `native_audio_runtime/src/`, JNI glue (`native_dsp_jni.c`, `jni_common.h`), and Kotlin spot-checks (`PreloadManager`, `AudioEffectsManager`, `QueueManager`, `ArtworkCacheManager`).

---

## 1. Verification Table

| ID | Original Finding | Original Severity | Current Status | Re-evaluated Severity | Verdict |
|----|-----------------|------------------|---------------|----------------------|---------|
| K-01 | `MetadataCacheDb.putByPath()` 32-bit `hashCode()` collision | HIGH | **FIXED** | INFO | FNV-1a 64-bit `pathToId()` replaces `hashCode()` |
| K-02 | `CrossfadeController` double `setActiveQueueIndex()` | LOW | **INTENTIONAL** | INFO | Both calls documented and race-safe; see detail below |
| K-03 | Stale `MediaKitPlaybackService` reference in `PlaybackNotificationManager` KDoc | LOW | **FIXED** | — | Comment removed entirely |
| K-04 | Mixed Indonesian/English inline comments in `NowPlayingOverlayActivity` | INFO | **INTENTIONAL** | INFO | Style choice, no bug |
| K-05 | Dead/unreachable fallback loop in `StereoWideningAudioProcessor.queueInput()` | INFO | **INTENTIONAL** | INFO | Now documented as defensive drain; DO NOT FIX |
| K-06 | `MetadataPrescanner` cancellation doesn't interrupt in-flight `ExoMetadataReader.read()` | INFO | **INTENTIONAL** | INFO | Bounded by 10s timeout, no data corruption |
| K-07 | `ReplayGainError` ordinal stability — no comment marking safe insertion point | INFO | **FIXED** | INFO | Comment + K-07 label added at exact insertion point |
| K-08 | `setPitch()` semitone conversion | INFO | **INTENTIONAL** | INFO | `12 * log2(factor)` is correct |
| K-09 | `SignalsmithStretch` I/O counters not reset on bypass→STFT | INFO | **INTENTIONAL** | INFO | Zeroing would cause false EOS |
| K-10 | `QueueSync.save()` ExoPlayer position reads on main thread | INFO | **INTENTIONAL** | INFO | Correct snapshot-before-background pattern |
| K-11 | `MediaStoreWriteGate` single `REQUEST_CODE` | INFO | **INTENTIONAL** | INFO | Queue-based serialisation is correct fix |
| K-12 | `FallbackBitmapLoader.noArtworkCache` session-lifetime static set | INFO | **INTENTIONAL** | INFO | Tradeoff documented |
| K-13 | Watchdog suppressed during crossfade | INFO | **INTENTIONAL** | INFO | Correct guard |
| K-14 | `NativeDspAudioProcessor` per-instance `streamSlot` | INFO | **INTENTIONAL** | INFO | Correct isolation |
| K-15 | `ServiceShutdownCoordinator` — `stopForeground()` only in Phase 1 | INFO | **INTENTIONAL** | INFO | Correct lifecycle |
| K-16 | `AUDIOFOCUS_REQUEST_DELAYED` treated as granted | INFO | **INTENTIONAL** | INFO | Correct for MIUI 12 |
| K-17 | `NativeLogger` `@Volatile` + main-looper dispatcher | INFO | **INTENTIONAL** | INFO | Correct thread model |
| K-18 | `EburTrackSession` album scan ownership | INFO | **INTENTIONAL** | INFO | `ReplayGainService.scanAlbum()` follows pattern correctly |
| K-19 | `GeneratedPluginRegistrant.java` registered plugins | INFO | **INTENTIONAL** | INFO | All 7 wrapped in individual try-catch |
| K-20 | `QueueManager.rebuildPlayerQueue()` incremental vs `setMediaItems()` | INFO | **INTENTIONAL** | INFO | Correct Media3 decision |
| K-21 | `PcmDecoder` doesn't propagate `Thread.interrupt()` | INFO | **INTENTIONAL** | INFO | Bounded, no data corruption |
| MEM-01 | `tag_writer.cpp` ID3v2 iterator invalidation | HIGH | **FIXED** | — | Pre-existing fix confirmed |
| MEM-02..05 | C/C++ layer observations | INFO | **INTENTIONAL** | INFO | All confirmed correct |

---

## 2. Detailed Analysis of Re-check Items

### K-01 — MetadataCacheDb hash collision

**Original finding:** `path.hashCode()` (32-bit) in `putByPath()` → CONFLICT_REPLACE silently overwrites colliding paths.

**Current code (`MetadataCacheDb.kt` lines 51–66 + 264):**
```kotlin
fun pathToId(path: String): Long {
    var h = -3750763034362895579L   // FNV-1a 64-bit offset basis
    for (c in path) {
        h = h xor c.code.toLong()
        h *= 1099511628211L          // FNV-1a 64-bit prime
    }
    return h
}
// ...
put(COL_ID, pathToId(path))    // collision-safe 64-bit id from path
```

The KDoc explicitly documents the fix: *"Uses FNV-1a 64-bit instead of String.hashCode() (32-bit, ~50% collision probability at 77K entries per birthday-paradox)"*.

Also noteworthy: `getByPath()` queries by `COL_PATH = ?` (not by id), so even if a hash collision were to occur, the read path would not serve the wrong entry — only the write/overwrite behaviour was the actual risk.

**Verdict: FIXED.** Original HIGH severity was warranted; the current fix is correct and well-documented.

---

### K-02 — CrossfadeController double `setActiveQueueIndex()`

**Original finding:** Two `setActiveQueueIndex(nextIndex)` calls — one early in the fade phase, one at completion — risk stale index if `setQueue()` races mid-crossfade.

**Current code:**

- **Call 1 (`beginCrossfade()`, line 309):** Called immediately after `setActivePlayer(standby)`, before `emitAll()`. Comment at lines 305–309: *"Update activeQueueIndex ke lagu B sekarang — sebelum emitAll() — supaya TrackMapper.currentTrackMap() langsung membaca metadata lagu B saat fade dimulai"*. This is intentional: the notification and Flutter UI must show track B immediately when the fade starts, not wait until completion.

- **Call 2 (`runEqualPowerFade`, line 368):** Called when `step >= steps` (fade complete). Uses the same captured `nextIndex` — idempotent.

**Why the race cannot happen:**
1. `cancel(resetVolume=true)` is called by every `setQueue()` path before any queue mutation. `cancel()` calls `handler.removeCallbacks(crossfadeFadeRunnable)` (line 139), ensuring the runnable (including the second `setActiveQueueIndex`) never fires after a cancel.
2. The abort guard at line 347 — `if (getActivePlayer() !== newPlayer)` — exits the runnable immediately if the active player changed, before reaching line 368.
3. Both calls are on the same Handler (serial execution) — no actual concurrency.

**K-02 comment in code (line 224–229):** The code self-documents the K-02 label and the reasoning explicitly.

**Verdict: INTENTIONAL.** The double call is a deliberate two-phase design: first call updates the index for UI display during the fade; second call is the durable update at completion. The race described in the audit cannot occur due to `cancel()` + abort guard. **Downgraded from LOW to INFO.**

---

### K-03 — Stale `MediaKitPlaybackService` reference

**Original finding:** KDoc at line 29 of `PlaybackNotificationManager.kt` says *"works with both Media3PlaybackService and MediaKitPlaybackService"*.

**Current code (lines 24–40):**
```kotlin
/**
 * Media playback notification manager for [Media3PlaybackService].
 *
 * Accepts any [android.app.Service] as host and manages the foreground
 * media notification lifecycle.
 * ...
 * NS-01: Unified notification building ...
 * NS-03: Artwork bitmap loading ...
 * NS-04: launchPendingIntent is cached as a lazy val ...
 */
```

No mention of `MediaKitPlaybackService` anywhere in the class or its KDoc.

**Verdict: FIXED.** The stale reference has been removed.

---

### K-05 — Unreachable loop in `StereoWideningAudioProcessor.queueInput()`

**Original finding (INFO/dead code):** The `while (inputBuffer.hasRemaining())` loop after frame processing is unreachable because ExoPlayer always delivers aligned buffers.

**Current code (lines 93–98):**
```kotlin
// K-05: Defensive drain for any sub-frame bytes left after the integer
// division above (e.g. remaining % 4 != 0 for PCM-16 or remaining % 8 != 0
// for PCM-float). In practice ExoPlayer always delivers aligned buffers, so
// this loop is never entered; it is kept to avoid silent data loss if an
// upstream processor ever produces a misaligned buffer.
while (inputBuffer.hasRemaining()) output.put(inputBuffer.get())
```

**Does ExoPlayer ALWAYS guarantee frame alignment?**

ExoPlayer's `DefaultAudioSink` drives its `AudioProcessorChain` with the output of the preceding processor. The chain is: `ToFloatPcmAudioProcessor → NativeDspAudioProcessor → StereoWideningAudioProcessor → ...`. Each processor calls `replaceOutputBuffer(remaining)` and processes exactly `remaining / bytesPerFrame` complete frames. The contract is that `queueInput()` is called with whatever bytes remain in the pipeline — which are always multiples of the format's frame size because `DefaultAudioSink.handleBuffer()` computes `bytesToProcess` as a multiple of `inputFrameSize` before entering the processor chain. No processor in the chain introduces sub-frame padding.

However: if a future processor inserted upstream of `StereoWidening` were to produce a non-multiple-of-frame output (e.g., a bug in a custom processor), the loop would be the only thing preventing data loss. The loop is therefore correctly classified as a defensive guard.

**Verdict: INTENTIONAL.** Kept as DO NOT FIX. The K-05 comment in the code confirms this was deliberate.

---

## 3. Newly Discovered Findings

### NEW-01 — `comp_processor.c`: potential divide-by-zero when `knee_db = 0.0`

**File:** `native_audio_runtime/src/comp_processor.c`, line 125  
**Severity:** LOW

**Code:**
```c
const float t = (over + knee_half) / p->knee_db;
```

`knee_half = p->knee_db * 0.5f`. This path executes only in the soft-knee region (`over >= -knee_half && over <= knee_half`). If `knee_db = 0`, then `knee_half = 0` too, and the condition collapses to exactly `over == 0.0f` — a floating-point equality that is astronomically unlikely but theoretically reachable (signal level exactly at threshold). In that case: `0 / 0 = NaN (IEEE 754)`, `t * t * 0 * ... = NaN`, `nar_db_to_linear(... - NaN) = NaN`.

**Parameter clamp in `nar_comp_set_params()` (line 308):**
```c
if (knee_db < 0.0f) knee_db = 0.0f;   // minimum is 0, not > 0
```
Zero is an allowed value. The UI default is 6.0 dB, so this only triggers if the user (or Dart code) explicitly sets knee_db to 0.

**Mitigation already present:** Line 226:
```c
if (!isfinite(gain_linear)) gain_linear = 1.0f;  // defensive fail-open
```
This isfinite() guard catches the NaN and falls back to unity gain. No audio crash occurs; worst case is one frame at unity gain instead of the computed gain.

**Recommendation:** Change the knee_db floor from `0.0f` to `0.01f` in `nar_comp_set_params()`, or add an early-return in `_gain_reduction_db()` for `p->knee_db < 0.001f` (treat as hard knee). Either eliminates the division entirely.

**Realistic impact:** Near-zero. Requires the user to set knee_db = 0 AND the signal to be exactly at threshold simultaneously. The isfinite() guard makes this a no-op in practice.

---

### NEW-02 — `dsp_pipeline.c`: `nar_dsp_pipeline_reset()` has no initialized guard

**File:** `native_audio_runtime/src/dsp_pipeline.c`, line 85–90  
**Severity:** INFO

**Code:**
```c
FFI_PLUGIN_EXPORT void nar_dsp_pipeline_reset(void) {
  int32_t count = atomic_load(&_count);
  for (int32_t i = 0; i < count; i++) {
    _slots[i].vtable->reset(_slots[i].self);
  }
}
```

Unlike `nar_dsp_pipeline_process_stream()` (which has no guard either, but the call chain from Kotlin's `queueReset()` is always within an active session), `reset()` has no `if (!_initialized) return` guard. If `dispose()` zeroes `_slots` and sets `_count = 0` **after** `reset()` reads `_count` but **before** the loop dereferences `_slots[i].vtable`, this would dereference a NULL pointer.

**Why this is practically unreachable:** `dispose()` is called during `onDestroy()` of `Media3PlaybackService`. ExoPlayer's audio thread (which calls `reset()` on seek/flush) is stopped by `player.stop()` / `player.clearMediaItems()` long before `onDestroy()` is reached. The system-kill path skips `onDestroy()` entirely. No realistic execution path reaches this race.

**Recommendation:** Add `if (!atomic_load(&_initialized)) return;` at the top of `reset()` for defensive consistency with `dispose()`'s existing guard.

---

### NEW-03 — `jni_common.h` `GetStringUTFChars` / `ReleaseStringUTFChars` — FALSE POSITIVE

**Grep flagged** `GetStringUTFChars` at line 37 without `ReleaseStringUTFChars`. On inspection, line 40 immediately follows:
```cpp
const char* chars = env->GetStringUTFChars(jstr, nullptr);
if (chars == nullptr) return {};
std::string result(chars);
env->ReleaseStringUTFChars(jstr, chars);   // line 40 — correctly paired
return result;
```
Properly paired. **FALSE POSITIVE.**

---

### NEW-04 — `audio_buffer.c` unchecked `calloc` — FALSE POSITIVE

**Grep flagged** `calloc` at lines 33 and 40 without null checks. On inspection:
```c
NarAudioBuffer* buffer = (NarAudioBuffer*)calloc(1, sizeof(NarAudioBuffer));
if (buffer == NULL) { nar_runtime_set_last_status(...); return NULL; }   // line 34-36

buffer->data = (float*)calloc(sample_count, sizeof(float));
if (buffer->data == NULL) { free(buffer); nar_runtime_set_last_status(...); return NULL; }  // lines 41-44
```
Both allocations are null-checked with proper cleanup. **FALSE POSITIVE.**

---

## 4. False Positives from Original Audit (Reconfirmed)

All items previously listed as false positives (`MediaStore PRAGMA WAL`, duck factor, `ServiceReadyGate` replay) remain confirmed safe per the current codebase.

Additionally, the following items from the verification grep scan are false positives:

| Grep hit | Why it's safe |
|---|---|
| `jni_common.h:37` `GetStringUTFChars` | Paired with `ReleaseStringUTFChars` at line 40 in same function |
| `audio_buffer.c:33,40` `calloc` | Both null-checked with cleanup immediately following |
| `comp_processor.c:125` divide — knee region | `if (!isfinite(gain_linear)) gain_linear = 1.0f` guard catches any NaN; only a LOW finding |

---

## 5. Recommended Fixes

Only two actionable items remain unfixed:

| Priority | ID | Fix | File | Effort |
|---|---|---|---|---|
| LOW | NEW-01 | Change `knee_db` floor from `0.0f` to `0.01f` in `nar_comp_set_params()` | `comp_processor.c:308` | 1 line |
| INFO | NEW-02 | Add `if (!atomic_load(&_initialized)) return;` guard at top of `nar_dsp_pipeline_reset()` | `dsp_pipeline.c:86` | 1 line |

All other original findings are either FIXED, INTENTIONAL, or INFO with no required action.

---

## 6. Final Assessment

**The native audit is: MOSTLY ACCURATE**

- The one HIGH finding (K-01) was real and has since been fixed with a correct 64-bit FNV-1a hash.
- The LOW findings (K-02, K-03) are either intentional design (K-02) or already fixed (K-03).
- All INFO findings are confirmed correct implementations.
- The original audit did **not** cover `native_audio_runtime/src/` (the C DSP runtime). The new pass over those files found **2 minor new items** (NEW-01 LOW, NEW-02 INFO), both negligible in impact.
- No critical or high severity issues exist in the current codebase.

**Overall native code quality: HIGH.** Thread safety (atomics, per-stream isolation, dirty-flag acquire/release), fail-open error handling (isfinite guards on every DSP hot loop), and JNI contract (GetStringUTFChars paired, direct buffer null checks) are all correctly implemented throughout.
