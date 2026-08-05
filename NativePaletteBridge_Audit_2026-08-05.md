# NativePaletteBridge Full Audit

**Date:** 2026-08-05  
**Scope:** `android/app/src/main/kotlin/dev/wndavenz/music/NativePaletteBridge.kt` and its direct integration points in `MainActivity.kt`, `ArtworkCacheManager.kt`, `NativePaletteService.dart`, and the Android palette dependency.  
**Status:** Complete — findings NP-01 through NP-06 remediated after the audit;
NP-07 remains open.

## Executive summary

`NativePaletteBridge` has a solid basic architecture: it validates the MethodChannel
argument, keeps decode and quantization off the Flutter UI thread, uses a bounded
executor, recycles the decoded bitmap, and preserves retryability for missing or
temporarily unavailable artwork. The OKLab clustering and coverage-oriented role
selection are also reasonable for the stated palette goals.

The original audit risks were around lifecycle, cache contracts, documentation,
and test/queue maintenance rather than the palette math itself. NP-01 through
NP-06 are now fixed; the remaining open item is summarized below:

1. **Fixed —** A request could be left unresolved when `MainActivity.onDestroy()` shuts down the
   shared executor, and a running request can post a result after the Flutter
   engine/activity is being torn down.
2. **Fixed —** `OutOfMemoryError` was not covered by `catch (Exception)`, so a native memory
   failure can terminate the worker without resolving the Dart MethodChannel
   Future.
3. **Fixed —** `NativePaletteBridge.CACHE_VERSION` was not connected to the Dart cache filename,
   so bumping the native version alone does not invalidate persisted results.
4. **Fixed —** The original source documentation described a 32-color palette, center
   weighting, and a 70/30 score, while the implementation uses 96 colors, no
   center weighting, and a 90/10 score. This documentation drift was corrected
   after the audit.
5. **Fixed —** JVM tests now cover the bridge contract, extraction errors,
   fallback behavior, lifecycle races, request coalescing, and palette-role selection.

## Findings summary

| ID | Severity | Area | Confidence | Status |
|---|---|---|---|---|
| NP-01 | High | Lifecycle / MethodChannel completion | High | Fixed |
| NP-02 | High | OOM failure handling | Medium | Fixed |
| NP-03 | Medium | Cache version invalidation | High | Fixed |
| NP-04 | Medium | Algorithm documentation drift | High | Fixed |
| NP-05 | Medium | Shared queue saturation / duplicate work | Medium | Fixed |
| NP-06 | Medium | Test coverage gap | High | Fixed |
| NP-07 | Low | Dead legacy harmony implementation | High | Open |

No critical security vulnerability was found in the reviewed bridge. The bridge
does not accept filesystem paths or raw image bytes from Dart; it accepts only a
positive song ID and resolves artwork through the app-owned cache manager.

---

## NP-01 — Request completion race during Activity/engine teardown

**Severity:** High  
**Confidence:** High  
**Files/locations:**

- `NativePaletteBridge.kt:169-203`
- `NativePaletteBridge.kt:188-198`
- `MainActivity.kt:1360-1367`
- `MainActivity.kt:51-55`

### Description

`handleCall()` submits work to the shared `artworkExecutor`. Completion is always
deferred with `mainHandler.post { result.success(...) }` or
`mainHandler.post { result.error(...) }`.

`MainActivity.onDestroy()` calls `artworkExecutor.shutdownNow()` without notifying
the bridge or resolving requests that are already queued. Consequently:

- queued palette jobs can be removed by `shutdownNow()` before their callback runs;
- the corresponding Dart `invokeListMethod()` Future receives no success/error
  response;
- a job already running can finish after teardown and attempt to reply to a
  MethodChannel result whose Flutter engine is no longer attached;
- `Handler.post()` returns a boolean, but the result is ignored, so a rejected
  post also leaves the request unresolved.

This is especially relevant because the executor is shared with other artwork
operations and the Activity owns the executor lifecycle.

### Impact

During Activity recreation, engine teardown, or process shutdown, palette callers
can hang until their Dart-side lifecycle abandons them. A later retry may then
produce unnecessary duplicate artwork work. A late callback may also produce
noisy engine/channel errors depending on the Flutter embedding state.

### Recommendation

Introduce an explicit bridge lifecycle:

1. Add a `@Volatile` disposed/closing flag and reject new calls with a stable
   `palette_unavailable` error after disposal.
2. Track pending requests, or wrap each submitted job in a request object.
3. On disposal, resolve pending results exactly once with a teardown error before
   shutting down the executor.
4. Check the disposed flag before posting and inside the main-thread callback.
5. Treat a `false` return from `mainHandler.post()` as a failed delivery path and
   resolve/log it where possible.
6. Prefer owning the executor at Flutter-engine scope if the engine can outlive
   the Activity, or explicitly detach the bridge in `onDestroy()`.

Add a regression test for:

- queued request + disposal;
- running request + disposal;
- callback post rejection;
- duplicate completion prevention.

---

## NP-02 — `OutOfMemoryError` can leave the MethodChannel Future unresolved

**Severity:** High  
**Confidence:** Medium  
**Files/locations:**

- `NativePaletteBridge.kt:184-199`
- `NativePaletteBridge.kt:214-237`
- `NativePaletteBridge.kt:230-236`

### Description

The worker catches `Exception`, but `OutOfMemoryError` is an `Error`, not an
`Exception`. A failure during bitmap decoding, AndroidX Palette generation, or
temporary allocation can therefore escape the worker callback. In that case the
bridge never posts `result.success()` or `result.error()`.

The code does bound the decoded image to a target size and recycles the bitmap,
which makes this lower probability, but the failure path is still incomplete.
The current AndroidX Palette call uses `maximumColorCount(96)`, also increasing
temporary quantization work compared with the documented 32-color configuration.

### Impact

The Dart Future can remain unresolved, and the executor worker can die or log an
uncaught exception. Repeated artwork requests can amplify memory pressure on the
target Snapdragon 730 device.

### Recommendation

- Catch `OutOfMemoryError` explicitly around decode/quantization and convert it
  into a stable `palette_memory_error` MethodChannel error.
- Keep bitmap cleanup in `finally` as it is now.
- Consider reducing `maximumColorCount` if 96 is not required by measured palette
  quality.
- Add a decode/quantization failure test using an injectable extractor or a
  test seam rather than trying to induce real process OOM in a unit test.
- Do not broadly swallow every `Throwable`; handle memory failure explicitly and
  let programming errors remain visible.

---

## NP-03 — Native cache version is declared but does not invalidate the Dart cache

**Severity:** Medium  
**Confidence:** High  
**Files/locations:**

- `NativePaletteBridge.kt:111-118`
- `NativePaletteService.dart:80-83`
- `NativePaletteBridge.kt:229-234`

### Description

`NativePaletteBridge.CACHE_VERSION` is declared as `8`, but it is not read by
the bridge or transmitted over the MethodChannel. The actual persisted filename
is independently hardcoded in Dart as `palette_cache_v8.json`.

Therefore, changing the native selection algorithm and bumping only
`NativePaletteBridge.CACHE_VERSION` has no runtime effect on cache invalidation.
The cache remains valid only when a developer also remembers to update the Dart
filename manually.

### Impact

Users can receive palettes generated by an older algorithm after a native
algorithm change. This is particularly visible for primary/secondary/accent
role changes, because the stale result is considered valid and is returned by
`getSync()` without re-extraction.

### Recommendation

Use one source of truth:

- expose the native algorithm version through a channel method and include it in
  the Dart cache filename/key; or
- move the version constant to a shared build-generated value; or
- remove the unused native constant and make the Dart cache version the explicit
  owner, with a test/check that algorithm changes require a cache bump.

Add a test proving that a version change cannot load an old persisted palette.

---

## NP-04 — Algorithm comments and implementation have drifted

**Severity:** Medium  
**Confidence:** High  
**Files/locations:**

- `NativePaletteBridge.kt:27-44`
- `NativePaletteBridge.kt:75-82`
- `NativePaletteBridge.kt:242-247`
- `NativePaletteBridge.kt:263-297`
- `NativePaletteBridge.kt:300-318`

### Description

The class documentation is no longer an accurate description of the code:

- It says `maximumColorCount = 32`; implementation uses `96`.
- It describes a center-crop/center-boost term; `selectBestFive()` accepts only
  `Palette` and has no bitmap or spatial population input.
- It documents a `0.70 × population + 0.30 × saturation` score; implementation
  uses `0.90 × population + 0.10 × vibrancy`.
- It says clustering runs over “a few dozen” swatches, while the configured
  maximum is 96.
- `selectBestFive()` KDoc says it uses `[bitmap]` for center-crop weighting,
  but no bitmap parameter exists.

These were documentation-only discrepancies: they made future tuning and review
unsafe because the intended scoring model could not be inferred from the source
reliably. The KDoc, Dart comments, memory notes, and active technical documents
were corrected after the audit to describe the current implementation.

### Impact

Before remediation, future contributors could tune the wrong constants, believe
center weighting was active when it was not, or incorrectly assess performance
and cache-version changes. The source documentation now states the active
constants and selection path.

### Recommendation

Keep KDoc/comments synchronized with the current 96-color, population-dominant
90/10 implementation. The unused `[bitmap]` reference and obsolete center/
70/30/32-color descriptions have been removed. The output and scoring invariants
are now documented at the native and Dart boundaries.

---

## NP-05 — Shared artwork executor can saturate under palette bursts

**Severity:** Medium  
**Confidence:** Medium  
**Files/locations:**

- `MainActivity.kt:51-55`
- `NativePaletteBridge.kt:184-203`
- `ArtworkCacheManager.kt:91-146`

### Description

Palette extraction shares the two-thread artwork executor and its queue capacity
of 48 with artwork cache extraction. A palette miss can include:

1. MediaMetadataRetriever artwork extraction;
2. WebP decode/encode and file I/O;
3. a second bitmap decode;
4. Palette quantization and clustering.

Before remediation, the Dart service deduplicated calls only within one Dart
isolate and the native bridge had no per-song in-flight coalescing. Multiple
callers could enqueue duplicate work. Queue rejection returned `palette_busy`
and Dart retried twice with a fixed 120 ms delay.

### Impact

Homepage artwork warm-up and palette extraction can compete for the same two
workers. Under a large library or rapid player changes, extraction latency rises
and `palette_busy` retries can amplify the burst. This is a performance and
responsiveness risk on the target device, not a data-integrity issue.

### Remediation status

NP-05 is fixed without increasing the worker count:

- `NativePaletteBridge` coalesces concurrent native requests by `songId` into
  one in-flight extraction job and fans the same result/error out to all
  waiting MethodChannel results.
- The bridge records sampled debug metrics for extraction count, coalesced
  request count, queue rejection count, and average extraction duration.
- Dart waits 240 ms after `palette_busy` before the bounded retry, reducing
  immediate pressure on a saturated queue.
- The existing two-thread bounded executor remains in place for the target
  Xiaomi Mi 9T/K20. A dedicated/priority executor is intentionally deferred
  until metrics show that coalescing is insufficient.

---

## NP-06 — No direct tests for the bridge or palette selection

**Severity:** Medium  
**Confidence:** High  
**Files/locations:**

- `android/app/src/main/kotlin/dev/wndavenz/music/NativePaletteBridge.kt`
- `android/app/src/test/` — no palette bridge test found

### Original gap

The Android test suite originally contained tests for queue, metadata, audio
focus, crossfade, event, and lifecycle-related components, but no tests covered
`NativePaletteBridge`.

Untested behavior includes:

- invalid/non-Int/zero/negative MethodChannel arguments;
- executor rejection;
- null artwork and invalid bitmap bounds;
- output always containing five colors;
- one-family and two-family role selection;
- dominant neutral replacement;
- highlight/shadow derivation;
- OKLab clustering;
- cache-version behavior;
- lifecycle teardown and exactly-once callback completion.

### Remediation

Added `android/app/src/test/kotlin/dev/wndavenz/music/NativePaletteBridgeTest.kt`
with 13 deterministic JVM tests using a fake executor, synchronous test Handler,
fake MethodChannel results, and real AndroidX `Palette.Swatch` inputs.

Coverage includes:

- invalid MethodChannel arguments and `getCacheVersion`;
- unknown method handling;
- native per-song request coalescing and fan-out;
- independent jobs for different songs;
- queue rejection;
- null artwork result;
- ordinary extraction exceptions;
- `OutOfMemoryError` mapping;
- dispose-time completion and post-dispose rejection;
- five-color output and warm-family preservation;
- dominant-neutral correction;
- empty-palette fallback.

The production bridge gained only a test seam: injectable Handler/extractor and
an internal selector entry point. Runtime behavior and the public MethodChannel
contract are unchanged.

### Impact

Palette algorithm changes can silently regress the warm/beige/skin-tone and
navy/neutral cases that this engine was introduced to preserve. Lifecycle bugs
also remain difficult to reproduce without deterministic tests.

### Validation

`./gradlew :app:testDebugUnitTest --tests
dev.wndavenz.music.NativePaletteBridgeTest` passed with **13/13 tests**.

---

## NP-07 — Dead legacy harmony code increases maintenance surface

**Severity:** Low  
**Confidence:** High  
**Files/locations:**

- `NativePaletteBridge.kt:544-626`

### Description

`selectHarmoniousTriplet()` and `harmonyScore()` are retained as legacy helpers,
but no production call site uses them. They are documented as being kept for
future comparisons, yet there is no test or diagnostic path that consumes them.

### Impact

The file is already 800+ lines. Keeping unused selection logic makes it harder
to identify the active algorithm and increases the chance that a future change
updates one path while assuming the other is active.

### Recommendation

Remove the dead helpers, or move them into a clearly named test/benchmark helper
with tests that explicitly compare the legacy and current algorithms. Do not
leave dormant production logic in the bridge without a consumer.

---

## Positive findings

1. **Input validation:** only the expected method and positive `Int` song IDs are
   accepted (`NativePaletteBridge.kt:173-181`).
2. **UI-thread protection:** artwork decode and Palette generation are dispatched
   to a bounded background executor (`NativePaletteBridge.kt:184-187`,
   `MainActivity.kt:51-55`).
3. **Queue rejection is explicit:** `RejectedExecutionException` is returned as a
   distinct `palette_busy` error rather than silently dropping the request.
4. **Bitmap lifecycle:** decoded bitmaps are recycled in `finally`
   (`NativePaletteBridge.kt:229-237`).
5. **Efficient channel contract:** only a song ID crosses MethodChannel; raw image
   bytes are not copied through Flutter.
6. **Retryable transient failures:** missing artwork returns `null` from the
   native extraction path, and Dart does not persist the hardcoded fallback for
   channel/extraction failure (`NativePaletteBridge.kt:208-212`,
   `NativePaletteService.dart:246-253`).
7. **Perceptual selection:** OKLab distance and coverage-aware role selection are
   preferable to raw RGB distance or naïve named-swatch ordering.
8. **Artwork cache safety:** the direct cache manager uses app-owned storage,
   per-song locking, atomic WebP writes, and explicit `MediaMetadataRetriever`
   release.
9. **No obvious input-path vulnerability:** the bridge does not let Dart provide
   an arbitrary filesystem path to `BitmapFactory.decodeFile`; the path comes
   from `ArtworkCacheManager`.

## Recommended priority order

### P0/P1 — before relying on the bridge during lifecycle churn

1. Fix NP-01 lifecycle completion and disposal behavior.
2. Fix NP-02 OOM completion behavior.

### P2 — before the next palette algorithm revision

3. Connect or remove the unused cache version (NP-03).
4. Synchronize algorithm documentation and implementation (NP-04).
5. Add deterministic selection and channel tests (NP-06). **Completed** —
   covered by `NativePaletteBridgeTest`.
6. Measure and then address shared-queue saturation/coalescing (NP-05).

### P3 — maintainability

7. Remove or isolate dead harmony code (NP-07).

## Audit limitations

- No APK build or device run was performed, in line with the current project
  instruction not to build APKs.
- No real OOM or Activity teardown race was induced.
- The audit used source inspection, call-site tracing, history/blame inspection,
  and repository test discovery.
- Existing unrelated working-tree changes were left untouched.

## Remediation update

The following fixes were applied after the initial audit:

- **NP-01:** `NativePaletteBridge` now tracks pending requests, completes them
  exactly once, rejects new work after disposal, handles main-handler delivery
  failure, and is disposed from `MainActivity.onDestroy()` before the shared
  executor shuts down.
- **NP-02:** `OutOfMemoryError` during decode/quantization is converted into a
  stable `palette_memory_error` result instead of leaving the Dart Future
  unresolved.
- **NP-03:** `NativePaletteService.warmUp()` asks the native bridge for
  `CACHE_VERSION` through `getCacheVersion` and uses that value in the persisted
  cache filename, with a compatibility fallback for older/non-Android engines.

Validation of these changes is tracked separately from the original audit
findings. NP-05 is fixed by native per-song request coalescing, lightweight
debug metrics, and a longer Dart retry delay for `palette_busy`. NP-06 is fixed
by a deterministic 13-test JVM suite. The remaining open item is the dead
legacy harmony implementation.

### NP-05 remediation

- Concurrent native requests for the same `songId` now share one extraction
  job and receive the same result/error.
- The bridge tracks extraction count, coalesced request count, queue rejection
  count, and sampled average extraction duration in debug logs.
- Queue rejection remains bounded and retryable; Dart waits 240 ms after
  `palette_busy` instead of immediately adding pressure to the saturated queue.
- The existing two-thread bounded executor is retained for the Snapdragon 730
  target; no extra worker pool was introduced.

### Remediation validation

- `Flutter Analyze`: passed with **No issues found**.
- `dart format --output=none lib/services/native_palette_service.dart`:
  completed successfully after formatting the updated Dart file.
- `git diff --check`: passed.
- `:app:compileDebugKotlin`: passed successfully with the Android SDK
  environment configured. Existing unrelated deprecation warnings remain.
- `NativePaletteBridgeTest`: passed with **13/13 tests**.
- Release APK build: intentionally not run.