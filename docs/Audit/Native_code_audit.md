# Native Code Audit — Full Line-by-Line Review
**Date:** 2026-07-18  
**Scope:** All non-test Android/native source files (C/C++, Kotlin, Java)  
**Target device:** Xiaomi Mi 9T / K20 (SD730, 6 GB RAM, MIUI 12 / Android 11)

---

## Audit Methodology

Every source file was read in full, line-by-line, in two sessions:

**Session 1 (previous):** C/C++ files (`tag_writer.cpp`, `ebur128_analyzer.cpp`, `replaygain_jni.cpp`, `loudness_processor.c`, `stretch_jni.cpp`, `stereo_matrix.h`, etc.)  
**Session 2 (this):** All 40 Kotlin source files + `GeneratedPluginRegistrant.java`

Files read this session:
- `Media3PlaybackService.kt` (1801 lines)
- `MainActivity.kt` (1266 lines)
- `ActivePlayerProxy.kt`
- `ArtworkCacheManager.kt`
- `audio_focus/AudioFocusManager.kt`
- `audio_offload/AudioOffloadManager.kt`
- `crossfade/CrossfadeController.kt`
- `crossfade/PreloadManager.kt`
- `diagnostics/CrossfadeTimelineLogger.kt`
- `effects/AudioEffectsManager.kt`
- `effects/NativeDspAudioProcessor.kt`
- `effects/SignalsmithStretchAudioProcessor.kt`
- `effects/StereoWideningAudioProcessor.kt`
- `effects/StereoWidthManager.kt`
- `effects/StretchAwareAudioProcessorChain.kt`
- `effects/StretchManager.kt`
- `events/EventEmitter.kt` (also contains `ServiceReadyGate` + `NativeLogger`)
- `FallbackBitmapLoader.kt`
- `ffmpeg/FfmpegCapabilityProbe.kt`
- `NowPlayingOverlayActivity.kt`
- `ServiceShutdownCoordinator.kt`
- `metadata/ExoMetadataReader.kt`
- `metadata/MetadataCacheDb.kt`
- `metadata/MetadataPrescanner.kt`
- `metadata/TagBuilder.kt`
- `notification/PlaybackNotificationManager.kt`
- `queue/QueueManager.kt`
- `queue/QueueSync.kt`
- `replaygain/MediaStoreWriteGate.kt`
- `replaygain/PcmDecoder.kt`
- `replaygain/ReplayGainBridge.kt`
- `replaygain/ReplayGainModels.kt`
- `replaygain/ReplayGainNative.kt`
- `replaygain/ReplayGainService.kt`
- `sleep_timer/SleepTimerManager.kt`
- `transport/PlayPauseFadeController.kt`
- `transport/TransportCommands.kt`
- `transport/TransportState.kt`
- `utils/MediaItemFactory.kt`
- `utils/TrackMapper.kt`
- `GeneratedPluginRegistrant.java`

---

## Severity Legend

| Code | Meaning |
|------|---------|
| CRIT | Will crash or corrupt data |
| HIGH | Significant bug, silent misbehaviour, or data loss risk |
| MED | Incorrect logic that affects correctness under a realistic scenario |
| LOW | Latent risk, dead code, misleading comment, or minor inefficiency |
| INFO | Observation only — no bug |

---

## Findings — C / C++ Layer (Session 1)

### MEM-01 — `tag_writer.cpp`: ID3v2 frame replacement loop (HIGH, FIXED)
`replaceId3v2Frame()` walked the frame list while erasing from it via index arithmetic.  
**Status:** Fixed in the version audited (iterator invalidation resolved, atomic-rename rollback present).

### MEM-02 — `ebur128_analyzer.cpp`: album loudness uses `libebur128` multi-track state correctly (INFO)
`ebur128_add_frames_short` called per-track with individual handles; `ebur128_loudness_global_multiple` used for album aggregation with all handles still alive. Correct per EBU Tech 3341.

### MEM-03 — `replaygain_jni.cpp`: `PackWriteEnvelope` packing (INFO)
Returns `Object[3] = [Int, String[9]?, ByteArray?]`; Kotlin side unpacks positionally in `unpackWriteEnvelope()`. The positional contract is documented on both sides. Correct.

### MEM-04 — `loudness_processor.c`: missing `-llog` link (FIXED, per memory)
`liblog` was not in `CMakeLists.txt` link list, causing a link error and silently disabling the DSP pipeline. Fixed; all native DSP calls now fail-open correctly when the library is present but initialization fails.

### MEM-05 — `stretch_jni.cpp`: `nativeLog` JNI callback thread safety (INFO)
`NativeLogger.emit()` (Java static method called from JNI) is safe because `NativeLogger.emit()` always posts to the main looper — it never calls `EventSink.success()` from the audio/JNI thread directly. Correct.

---

## Findings — Kotlin Layer (Session 2)

### K-01 — `MetadataCacheDb.kt::putByPath()`: hash collision for synthetic song ID (LOW)

**File:** `metadata/MetadataCacheDb.kt` line 246  
**Code:**
```kotlin
put(COL_ID, path.hashCode())   // synthetic id from path
```
`String.hashCode()` is a 32-bit value. Two different paths with the same hashCode will map to the same `COL_ID` (the table's `INTEGER PRIMARY KEY`), causing `CONFLICT_REPLACE` to silently overwrite one entry with the other's data.

**Impact:** Rare (hash collisions in practice with typical library paths), but if it occurs the wrong cache entry is served, potentially showing stale loudness data for a track until mtime invalidation triggers a re-read.

**Mitigation options:**  
1. Use `COL_PATH` as PRIMARY KEY instead of `COL_ID`.  
2. Use a 64-bit hash (`path.hashCode().toLong() xor (path.hashCode().toLong() shl 32)`).  
3. After `insertWithOnConflict`, verify the inserted `COL_PATH` matches `path`; on mismatch use a different key.

---

### K-02 — `CrossfadeController.kt`: double `setActiveQueueIndex()` call (LOW)

**File:** `crossfade/CrossfadeController.kt` lines ~224 and ~304  
`setActiveQueueIndex(nextIndex)` is called at the *beginning* of the equal-power fade phase (after a comment saying it must NOT be called at `beginCrossfade()` start to avoid cutting song A) AND again just before `emitAll()` at the end of the same phase. If the second call fires with the same value it is idempotent. However if the standby player has been re-targeted between those two calls (e.g. a rapid `setQueue` during crossfade), the second call overwrites the correct index with a stale one.

**Realistic scenario on Mi 9T:** User taps a new track during the last second of a crossfade. `setQueue()` calls `cancel(resetVolume=true)` first, so the crossfade runnable is removed before the second `setActiveQueueIndex()` fires. Safe in the common path. Not safe if a crossfade continuation tick races with a `setQueue` inside the same Handler message. **Low probability given the Handler's serial execution**, but worth a note.

---

### K-03 — `PlaybackNotificationManager.kt`: stale reference to `MediaKitPlaybackService` (LOW / INFO)

**File:** `notification/PlaybackNotificationManager.kt` line 29  
KDoc says: *"works with both Media3PlaybackService and MediaKitPlaybackService"*  
`MediaKitPlaybackService` was removed entirely (single-engine architecture). The comment is stale and can cause confusion when reading the class.  

**Fix:** Remove the second sentence from the class KDoc.

---

### K-04 — `NowPlayingOverlayActivity.kt`: inline Indonesian comments alongside English architecture comments (INFO)

Lines 122, 150, 197–206 contain Indonesian inline comments mixed with English KDoc-style comments. Not a bug, but inconsistent for a codebase with English documentation conventions. No action required.

---

### K-05 — `StereoWideningAudioProcessor.kt::queueInput()`: unreachable fallback loop (INFO / dead code)

**File:** `effects/StereoWideningAudioProcessor.kt` line 93  
```kotlin
while (inputBuffer.hasRemaining()) output.put(inputBuffer.get())
```
This loop after the frame-processing block is dead code: `inputBuffer.remaining()` is always a multiple of `bytesPerFrame` (4 for PCM_16, 8 for PCM_FLOAT) since ExoPlayer's pipeline guarantees aligned frames. The loop can never execute. It is harmless but confusing.

---

### K-06 — `MetadataPrescanner.kt`: cancellation does not interrupt in-flight `ExoMetadataReader.read()` (INFO)

**File:** `metadata/MetadataPrescanner.kt`  
`cancel()` sets `cancelled = true`, which stops the loop at the next file boundary. However, if `ExoMetadataReader.read()` is mid-execution (blocking on `MetadataRetriever.get(TIMEOUT_SEC, ...)`) it runs to completion (up to 10 s) before the cancellation is honoured.  

**Impact:** On app shutdown or re-scan, the prescanner can hold I/O open for up to 10 s extra. Acceptable for a daemon thread; no data is corrupted. No action required.

---

### K-07 — `ReplayGainModels.kt`: `ReplayGainError` ordinal stability warning (INFO)

**File:** `replaygain/ReplayGainModels.kt` lines 10–31  
The enum has a comment: *"never reorder the values above, they're mapped positionally from native ordinals"*.  
`WRITE_ACCESS_DENIED` and `VERIFICATION_FAILED` are appended after the native-mapped region and are marked as Kotlin-only. This is correct and well-documented. No action needed, but any future addition of a native error code must be inserted before `VERIFICATION_FAILED` or it will break the mapping.

---

### K-08 — `TransportCommands.kt::setPitch()`: pitch factor → semitones conversion (INFO / correct)

```kotlin
val semitones = 12f * (kotlin.math.ln(pitchFactor.toDouble()) / kotlin.math.ln(2.0)).toFloat()
```
`12 * log2(factor)` is the correct equal-tempered semitone conversion. For `factor=1.0` → 0 semitones, `factor=2.0` → +12 semitones, `factor=0.5` → −12 semitones. Correct.

---

### K-09 — `SignalsmithStretchAudioProcessor.kt`: I/O counters NOT reset on bypass→STFT transition (INFO / intentional)

Lines 445–455 document why `totalInputFrames` and `totalOutputFrames` are deliberately not zeroed on the bypass→STFT transition: zeroing mid-stream could cause `getMediaDuration()` to use the nominal-speed fallback with `newSpeed=2.0` and a 2-minute elapsed time, returning 4 minutes which exceeds track duration → ExoPlayer fires EOS → song skips.  

The bypass path always accumulates a 1:1 ratio, so leaving the counters unchanged is both safe and correct. Well-handled.

---

### K-10 — `QueueSync.kt::save()`: ExoPlayer position reads on main thread (INFO / correct)

`save()` correctly captures `p.currentPosition`, `p.repeatMode`, and `p.shuffleModeEnabled` on the calling (main) thread before handing the snapshot to the background executor. This avoids the race condition of reading ExoPlayer state from a background thread.

---

### K-11 — `MediaStoreWriteGate.kt`: single `REQUEST_CODE` limits to one dialog at a time (INFO / correct)

The queue-based serialization correctly prevents two `startIntentSenderForResult` calls from racing for the same `REQUEST_CODE`. The comment documents the historical bug (batch write used to request access for 2 songs concurrently, orphaning the first callback). The fix is correct.

---

### K-12 — `FallbackBitmapLoader.kt`: session-lifetime `noArtworkCache` is a `ConcurrentHashMap.newKeySet()` (INFO / correct)

The negative cache is static (`companion object`) so it survives across `loadBitmap()` calls for the process lifetime. The comment correctly explains the tradeoff: worst case is "no art until cold restart" if MediaStore later indexes art for a previously-absent albumId. Acceptable.

---

### K-13 — `TransportState.kt`: watchdog does not fire during crossfade (INFO / correct)

`checkWatchdog()` guards on `crossfadeController.crossfadeInProgress` — during a crossfade the promoted player briefly holds position while the new audio starts. Without this guard, the watchdog could falsely trigger during a 5–8 s crossfade and attempt recovery that breaks the transition. Correct.

---

### K-14 — `NativeDspAudioProcessor.kt`: `streamSlot` per-instance isolation (INFO / correct)

Each `NativeDspAudioProcessor` instance receives its own `streamSlot` (0 for primary, 1 for secondary), passed to every native call. This correctly isolates the two ExoPlayers' DSP chains during crossfade overlap.

---

### K-15 — `ServiceShutdownCoordinator.kt`: `stopForeground()` only in Phase 1, not Phase 2 (INFO / correct)

`performTeardown()` (Phase 2) does not call `stopForeground()` again. This is correct because:  
1. If Phase 1 (`prepareShutdown()`) already ran, the foreground notification is already gone.  
2. If Phase 2 runs without Phase 1 (system kill), `Service.onDestroy()` is called by the system which handles notification cleanup.  

---

### K-16 — `AudioFocusManager.kt`: `AUDIOFOCUS_REQUEST_DELAYED` treated as granted (INFO / correct)

Per MIUI 12 behavior, `AUDIOFOCUS_REQUEST_DELAYED` is mapped to the "granted" path. This is documented and intentional — MIUI sometimes returns DELAYED synchronously but then grants focus immediately without the `onAudioFocusChange(AUDIOFOCUS_GAIN)` callback.

---

### K-17 — `NativeLogger.kt`: `@Volatile private var sink` + main-looper dispatcher (INFO / correct)

`@Volatile` ensures background threads (ExoPlayer audio thread, JNI callbacks) see the updated sink value from `onListen()` on the main thread. The `dispatcher` wraps all sink calls in `runCatching` so a throw inside `EventSink.success()` never propagates to the calling audio thread. Correct.

---

### K-18 — `EburTrackSession.kt`: album scan ownership warning documented (INFO / correct)

The KDoc correctly warns: for album scans, do NOT wrap in `use{}` immediately — keep the session open until after `nativeComputeAlbumLoudness`, then close. `ReplayGainService.scanAlbum()` follows this pattern correctly (adds to `sessions` list, calls `nativeComputeAlbumLoudness`, closes in `finally`).

---

### K-19 — `GeneratedPluginRegistrant.java`: registered plugins (INFO)

7 Flutter plugins registered: `audio_session`, `jni`, `jni_flutter`, `permission_handler`, `shared_preferences_android`, `sqflite_android`, `url_launcher_android`. All are wrapped in individual try-catch blocks. No issues.

---

### K-20 — `QueueManager.kt::rebuildPlayerQueue()`: incremental `addMediaItems()` vs `setMediaItems()` (INFO / architectural note)

The comment at lines 158–175 thoroughly documents why `addMediaItems()` (Option B) avoids the 50–200 ms audible dropout caused by `setMediaItems()` clearing `mediaSourceHolderSnapshots` and forcing `resetInternal()`. This is a subtle and correct Media3 internals decision. Worth preserving for future maintainers.

---

### K-21 — `PcmDecoder.kt`: does not propagate `Thread.interrupt()` during decode (INFO)

`PcmDecoder.decode()` runs a MediaCodec loop that does not check `Thread.interrupted()`. If the prescanner's thread is interrupted (via `cancel()` setting `cancelled=true` and the outer loop catching `InterruptedException` from `Thread.sleep()`), a decode in progress continues until its natural completion or EOF. No data corruption; bounded by file duration.

---

## Previously-Identified Confirmed Fixes

The following issues were found in earlier auditing sessions and confirmed fixed in the current codebase:

| ID | Description | File | Status |
|----|-------------|------|--------|
| LOW-01 | Queue save spawned unbounded threads | `QueueSync.kt` | Fixed (single executor + coalescing) |
| LOW-02 | `noArtworkUris` unbounded growth | `PlaybackNotificationManager.kt` | Fixed (bounded LinkedHashSet, max 64) |
| LOW-03 | Effect probe instantiated on session 0 | `AudioEffectsManager.kt` | Fixed (`isEffectTypeAvailable()` returns false) |
| LOW-07 | `offloadListener` accumulation on re-attach | `Media3PlaybackService.kt` | Fixed |
| NS-01 | Dual notification builder inconsistency | `PlaybackNotificationManager.kt` | Fixed (single `buildNotification()`) |
| NS-03 | Artwork loaded synchronously on notification thread | `PlaybackNotificationManager.kt` | Fixed (background executor + generation counter) |
| NS-04 | `launchPendingIntent` rebuilt on every refresh | `PlaybackNotificationManager.kt` | Fixed (`lazy val`) |
| CE-05 | Cross-player `createPositionInfo()` inconsistency | `ActivePlayerProxy.kt` | Fixed (all state-query methods overridden) |
| DE-01..06 | Duplicate trailing `emitAll()` in every `handle()` branch | `TransportState.kt` | Fixed (each branch emits exactly once) |
| UW-01 | Sleep timer re-emitted every 200 ms position tick | `TransportState.kt` | Fixed (`emitPositionOnly()` skips it) |
| PS-02 | Repeat-mode double emission | `TransportState.kt` | Fixed (`lastEmittedRepeatMode` dedup) |
| WD-01 | No stuck-playback watchdog | `TransportState.kt` | Fixed (5s/2-retry watchdog in position ticker) |
| QS-02/03 | ExoPlayer mutations during crossfade | `QueueManager.kt` | Fixed (mutations deferred; `rebuildPlayerQueue()` on promotion) |
| MED-01 | `isPreviewMode` path skips `ensureMediaForeground()` | `Media3PlaybackService.kt` | Intentional, undocumented in KDoc |

---

## False Positives from Previous Audit (Confirmed Safe)

| Previous Finding | Resolution |
|-----------------|------------|
| `MediaStore.PRAGMA journal_mode=WAL` via `execSQL` throws on MIUI 12 | Fixed: uses `rawQuery()` + consumes cursor |
| `AudioFocusManager` duck factor 0.2 (−14 dB) is aggressive | Intentional for MIUI 12 background app ducking |
| `ServiceReadyGate` only fires to currently-attached sink | Fixed: `onListen` replays readiness if already ready |

---

## Summary by Priority

### HIGH (1)
- **K-01** `MetadataCacheDb.putByPath()` hash collision: incorrect cache entry silently served for a different path

### LOW (4)
- **K-02** `CrossfadeController` double `setActiveQueueIndex()` — low-probability race
- **K-03** Stale `MediaKitPlaybackService` reference in `PlaybackNotificationManager` KDoc
- **K-05** Dead code: unreachable fallback loop in `StereoWideningAudioProcessor.queueInput()`
- **K-07** `ReplayGainError` ordinal stability: future native error codes must be inserted before Kotlin-only appendages

### INFO (remainder)
All other findings confirm correct implementations of non-trivial patterns (thread safety, I/O counter semantics, STFT transition priming, album loudness aggregation, queue rebuild after crossfade, watchdog guards).

---

## Recommended Actions

1. **Fix K-01** (HIGH): Change `MetadataCacheDb.putByPath()` to use `path` as the primary key (or use a 64-bit hash) to eliminate hash-collision cache corruption.

2. **Fix K-02** (LOW): Audit `CrossfadeController` for the double `setActiveQueueIndex()` call and remove one occurrence, or add an explicit guard.

3. **Fix K-03** (LOW): Remove stale `MediaKitPlaybackService` mention from `PlaybackNotificationManager` KDoc.

4. **Consider K-07** (INFO): Add a comment near `WRITE_ACCESS_DENIED` in `ReplayGainModels` explicitly marking the safe insertion point for future native error codes.
