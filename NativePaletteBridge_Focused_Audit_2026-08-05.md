# Focused Audit — `NativePaletteBridge.kt`

**Date:** 2026-08-05  
**Scope:** Only `android/app/src/main/kotlin/dev/wndavenz/music/NativePaletteBridge.kt`  
**Out of scope:** `MainActivity.kt`, `ArtworkCacheManager.kt`, Dart callers,
other Android services, and APK/runtime device behavior.

## Executive summary

The file is structurally sound: input validation is explicit, extraction runs
off the Flutter thread, bitmap ownership is released, requests are coalesced
while an extraction job is active, and OOM/queue errors are mapped to stable
MethodChannel errors. The focused test class and Kotlin compilation both pass.

Four maintainability/reliability findings remain:

| ID | Severity | Area | Status |
|---|---|---|---|
| NPB-F01 | Medium | Accepted Handler callback can be stranded | Open |
| NPB-F02 | Low | Small duplicate-work window after extraction | Open |
| NPB-F03 | Low | Extraction metrics omit failed-job duration/queue depth | Open |
| NPB-F04 | Low | KDoc still references removed harmony logic | Open |

No critical security issue was found in this file. The bridge accepts only a
positive song ID and does not accept a Dart-supplied filesystem path or raw
image bytes.

## Validation performed

- Read the complete 933-line `NativePaletteBridge.kt`.
- Searched all source/test call sites for the bridge contract and lifecycle.
- Ran:

  ```text
  ./gradlew :app:testDebugUnitTest \
    --tests dev.wndavenz.music.NativePaletteBridgeTest \
    :app:compileDebugKotlin
  ```

- Result: `BUILD SUCCESSFUL`.
- The focused test suite remains at 13/13 passing.
- Existing Kotlin warnings are unrelated to this focused audit except the
  already-known unnecessary non-null assertions in the active selector.
- No production file was modified during this audit.

## Findings

### NPB-F01 — `Handler.post()` acceptance is not delivery confirmation

**Severity:** Medium  
**Location:** `completeOnMain()` around lines 379–415

The bridge treats `mainHandler.post(deliver) == true` as sufficient and relies
on the runnable eventually executing. If the Handler accepts the runnable but
the Looper quits, removes pending callbacks, or otherwise stops dispatching
before `deliver` runs, the request remains in `pendingRequests` and its Dart
Future is never completed. The `post() == false` branch is handled, but the
accepted-then-dropped case is not.

`dispose()` mitigates this when it is definitely called after the callback was
queued, because it snapshots `pendingRequests` and completes them with
`palette_unavailable`. The class itself, however, has no acknowledgement or
timeout for an accepted runnable, so the exactly-once guarantee still depends
on external lifecycle disposal happening in time.

**Impact:** A palette request can remain unresolved during an unusual main
Looper/engine teardown sequence.

**Recommendation:** Keep a lifecycle-safe delivery token for posted callbacks
and ensure teardown removes/invalidates callbacks while completing every still
pending request. Alternatively, use an explicit bounded completion watchdog
only if the project lifecycle contract cannot guarantee `dispose()` promptly.
Any change must preserve exactly-once completion and avoid calling a
`MethodChannel.Result` twice.

### NPB-F02 — Coalescing ends before callbacks are delivered

**Severity:** Low  
**Location:** `completeJobOnMain()` around lines 355–370

`inFlightBySongId.remove(job.songId)` executes before the result runnables are
posted to the main Handler. A new request for the same song can therefore
arrive after extraction completes but before the first result runnable runs.
That request creates a second extraction job even though the first request's
result is still pending delivery.

The normal Dart path already deduplicates same-song requests, so this is mostly
relevant to cross-engine or native callers and to a heavily delayed main
Looper. It is nevertheless a small gap in the native coalescing contract.

**Impact:** Duplicate decode/MMCQ work during a narrow callback-delivery
window; no data corruption.

**Recommendation:** Retain a completed result/error in the per-song in-flight
entry until all current callbacks have been scheduled or delivered, or add a
short-lived native result cache keyed by song ID. Do not retain unbounded
results, and preserve retryability for transient failures.

### NPB-F03 — Metrics are insufficient to measure saturation completely

**Severity:** Low  
**Location:** `recordExtractionMetrics()` around lines 340–352

The bridge records successful extraction count, coalesced request count, queue
rejection count, and average duration. Duration is recorded only after
`extractColors()` returns; jobs that throw an ordinary exception or
`OutOfMemoryError` are not included in the duration aggregate. The bridge also
does not observe queue depth or distinguish artwork-cache hit/miss because
those values belong to the supplied executor/cache manager.

**Impact:** Debug telemetry can understate latency during failure bursts and
cannot independently prove whether the shared executor is close to saturation.

**Recommendation:** Record terminal duration in a `finally`-style job metric,
with a success/error outcome tag. If queue depth is needed, expose it from the
executor owner rather than reaching through this bridge's generic
`ExecutorService` interface.

### NPB-F04 — KDoc still describes removed harmony logic

**Severity:** Low  
**Location:** Class/data-model/selector comments around lines 57–62,
166–171, and 527–531

The source still contains phrases such as:

- “downstream harmony and role-assignment calculations”;
- “Selecting only by hue harmony could choose…”;
- “rather than inventing a mathematically harmonious substitute.”

The harmony helpers were removed by NP-07. The active code uses perceptual
distance and coverage/diversity selection, not a harmony score. These comments
are explanatory historical context, but their current wording can make a
future maintainer believe a second harmony selector still exists.

**Impact:** Documentation drift and increased risk of future incorrect edits;
no runtime impact.

**Recommendation:** Reword the comments to say “hue-only selection” or
“harmony-based selection” as a rejected historical approach, and remove
“downstream harmony” from the `ColorCluster` documentation.

## Verified invariants

### MethodChannel contract

- `getCacheVersion` returns `CACHE_VERSION`.
- Unknown methods call `notImplemented()`.
- `extractPalette` rejects non-`Int`, zero, and negative IDs.
- Only the positive song ID enters the extraction path.

### Request lifecycle and concurrency

- `pendingRequests` and `inFlightBySongId` are guarded by `lifecycleLock`.
- `PendingRequest.completed` provides atomic exactly-once protection.
- Same-song requests share one active extraction job.
- Queue rejection is converted to `palette_busy`.
- `dispose()` rejects future work and completes current requests.

### Error and resource handling

- `OutOfMemoryError` is handled separately from ordinary exceptions.
- Ordinary extraction exceptions become `palette_extraction_failed`.
- Bounds decode happens before full decode.
- Full bitmap decode is bounded by the power-of-two sample calculation and
  requests `ARGB_8888`.
- A decoded bitmap is recycled in `finally`.
- Missing artwork returns `null`, preserving Dart-side retry semantics.

### Palette selection

- AndroidX Palette is capped at 96 swatches.
- Chromatic filtering, 90/10 population-vibrancy scoring, OKLab clustering,
  top-32 role selection, neutral correction, and five-color output are all
  present in the active path.
- Fallback output is padded to five colors.
- The focused 13-test JVM suite covers the contract and main selection cases.

## Conclusion

`NativePaletteBridge.kt` is not manifestly broken and passes its focused tests
and Kotlin compilation. The highest-value follow-up is NPB-F01 because it is
the only finding that can leave a channel Future unresolved. NPB-F02–F04 are
low-risk improvements to coalescing precision, observability, and source
clarity. No algorithm cache-version bump is warranted by this audit because no
palette-selection behavior was changed.