# Focused Audit — `NativePaletteBridge.kt`

**Date:** 2026-08-05  
**Scope:** Only `android/app/src/main/kotlin/dev/wndavenz/music/NativePaletteBridge.kt`  
**Out of scope:** `MainActivity.kt`, `ArtworkCacheManager.kt`, Dart callers,
other Android services, and APK/runtime device behavior.

## Executive summary

The file is structurally sound: input validation is explicit, extraction runs
off the Flutter thread, bitmap ownership is released, requests are coalesced
through callback delivery, and OOM/queue errors are mapped to stable
MethodChannel errors. The focused test class and Kotlin compilation both pass.

All four findings from the focused review have been remediated:

| ID | Severity | Area | Status |
|---|---|---|---|
| NPB-F01 | Medium | Accepted Handler callback can be stranded | Fixed |
| NPB-F02 | Low | Small duplicate-work window after extraction | Fixed |
| NPB-F03 | Low | Extraction metrics omit failed-job duration/queue depth | Fixed |
| NPB-F04 | Low | KDoc still references removed harmony logic | Fixed |

No critical security issue was found in this file. The bridge accepts only a
positive song ID and does not accept a Dart-supplied filesystem path or raw
image bytes.

## Validation performed

- Read the complete `NativePaletteBridge.kt`.
- Searched all source/test call sites for the bridge contract and lifecycle.
- Ran:

  ```text
  ./gradlew :app:testDebugUnitTest \
    --tests dev.wndavenz.music.NativePaletteBridgeTest \
    :app:compileDebugKotlin
  ```

- Result: `BUILD SUCCESSFUL`.
- The focused test suite passes with 15/15 tests.
- Existing Kotlin warnings are unrelated to this focused audit except the
  already-known unnecessary non-null assertions in the active selector.
- `flutter pub get` was run to restore the missing `audio_session` Android
  plugin directory in the local dependency cache before Gradle validation.

## Findings

### NPB-F01 — `Handler.post()` acceptance is not delivery confirmation — Fixed

**Severity:** Medium  
**Location:** `completeOnMain()` around lines 379–415

The original risk was that `Handler.post()` returning `true` only confirms
enqueueing, not eventual Looper delivery. A stopped or removed Looper could
therefore leave the Dart Future unresolved.

**Remediation:** Each posted callback is guarded by the existing atomic
exactly-once token and a bounded five-second watchdog. If the Handler accepts
but never dispatches, the watchdog returns `palette_unavailable`. Watchdog
futures are cancelled after normal delivery, and `dispose()` shuts down the
watchdog scheduler.

### NPB-F02 — Coalescing ends before callbacks are delivered — Fixed

**Severity:** Low  
**Location:** `completeJobOnMain()` around lines 355–370

The original risk was removing the per-song job before its result callbacks
had been delivered. A same-song request arriving in that window could start
duplicate decode/MMCQ work.

**Remediation:** A completed `InFlightJob` retains its completion callback until
all request IDs have been delivered. Requests arriving during that window are
replayed through the existing callback path without submitting another
extraction job. The entry is removed as soon as the final request completes.

### NPB-F03 — Metrics are insufficient to measure saturation completely — Fixed

**Severity:** Low  
**Location:** `recordExtractionMetrics()` around lines 340–352

The original metrics only covered successful extraction duration and did not
expose queue depth, which could understate latency during failure bursts.

**Remediation:** Terminal duration is now recorded from `finally` for success,
ordinary error, and OOM outcomes. Debug metrics include failure count, outcome,
current queue depth, and maximum observed queue depth when the supplied
executor is a `ThreadPoolExecutor`.

### NPB-F04 — KDoc still describes removed harmony logic — Fixed

**Severity:** Low  
**Location:** Class/data-model/selector comments around lines 57–62,
166–171, and 527–531

The original wording could make a future maintainer believe a second harmony
selector still existed after the helper implementation had been removed.

**Remediation:** Active comments now describe hue and perceptual-distance
selection without referring to the removed harmony helper implementation.

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
- The focused 15-test JVM suite covers the contract, main selection cases,
  delayed callback delivery, and completed-job coalescing.

## Conclusion

`NativePaletteBridge.kt` passes its focused tests and Kotlin compilation. NPB-F01
through NPB-F04 are fixed. No algorithm cache-version bump is warranted because
the changes affect callback lifecycle, coalescing, metrics, tests, and comments,
not palette-selection behavior.