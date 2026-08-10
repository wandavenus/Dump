---
name: Artwork prefetch speed-up
description: Faster artwork loading — parallel prefetch batches, next-track prefetch, and viewport-aware scroll prefetch (1.5.18)
---

# Artwork prefetch speed-up (1.5.18)

User request: make artwork load faster inside the app. Three zero-trade-off
changes (scope F-A + F-C + F-D), all disk-path prefetch (never bitmap decode).

## 1. `ArtworkRepository.prefetch()` — parallel batches (F-D)

`lib/services/artwork_repository.dart` — prefetch no longer resolves one song
per 120ms sequentially. It processes IDs in small parallel batches:

- `concurrency` param, default **2** (native extractor runs on its own
  executor; 2 concurrent resolves roughly halve total prefetch time without
  contending with the UI thread on SD730).
- Yield between batches lowered 120ms → **60ms**.
- Still guarded by `_prefetching` (one batch at a time), dedups IDs, skips
  already-cached songs, never decodes bitmaps.

## 2. `AudioService._prefetchUpcomingArtwork()` — next-track warm-up (F-A)

`lib/services/audio_service/service.dart` — when a track starts (both
`playSongAt` and the internal current-song set path), fire-and-forget prefetch
of the **next 3** queue entries' artwork disk paths (`unawaited`).

- Skipped on web (`kIsWeb`) and empty queue.
- Mini player / queue overlay swap artwork with zero placeholder when the
  track advances.

## 3. Viewport-aware scroll prefetch in Library → Songs tab (F-C)

`lib/widgets/pages/library_sections/detail.dart`
(`_LibraryDetailPageState`) — the Songs tab renders hundreds of rows; every
not-yet-extracted song that scrolls into view used to trigger a native
extraction while visible (placeholder flash). Now:

- `_kickArtworkPrefetch()` warms the next **15** songs' disk paths.
- Triggered on songs load/rescan and when scrolling within **1200px** of the
  list bottom (`_kPrefetchTriggerExtent`).
- Cursor `_prefetchedUpTo` tracks how far the list has been warmed.

## Lesson: in-flight guard + progress cursor

`prefetch()` returns immediately while a batch is running (in-flight guard).
Callers that keep their own progress cursor MUST check
`ArtworkRepository.instance.isPrefetching` **before advancing** the cursor.

Why: during a fast fling near the list bottom, scroll events fire every
frame (~60/s) while one batch runs for ~0.5s+. Naively advancing the cursor
on every kick commits ranges that were never actually prefetched (their
`prefetch()` call no-oped) → those songs get on-demand extraction later =
the exact placeholder flash the feature exists to prevent. The guard makes a
skipped kick retry the same range on the next scroll tick.

**How to apply:** any new scroll-driven prefetch caller must use the same
pattern: check `isPrefetching` → advance cursor → `await prefetch(...)`.

## Validation

- `flutter analyze lib test` → No issues found.
- `flutter test` → 58/58 passed.
- pubspec 1.5.17 → 1.5.18 + changelog entry (3 items).
