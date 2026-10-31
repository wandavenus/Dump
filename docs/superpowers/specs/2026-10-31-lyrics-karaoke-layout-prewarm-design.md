# Lyrics Karaoke Layout Prewarming — Design

Date: 2026-10-31

## Intent
Remove cold text-layout and word-geometry work from the frame where a karaoke lyric becomes active. Keep the existing lyric appearance, scroll spring, focus blur, and row-transition timings.

## Selected approach
Use a bounded, per-`SyncedLyricsView` LRU cache that owns both `TextPainter` instances and the precomputed word boxes for each line. Prepare the active line before it paints, then prepare a small neighborhood (up to eight following lines and two preceding lines) using low-priority scheduler tasks, one line per task. Reuse cached layouts when the active-line widget is recreated.

## Invalidation and resource limits
Invalidate cached entries when lyric data, viewport width, font size, text scale, text alignment, text direction, or karaoke colors change. Dispose each `TextPainter` when an entry is evicted or the view is disposed. Cap the cache at 16 line layouts. Use a generation token so queued prewarm tasks from old lyrics/configuration cannot populate the current cache.

## Fallback
A cache miss must not force text layout from `CustomPainter.paint`. The active row temporarily renders as a normal Flutter `Text` while its layout is prepared at animation priority; once ready, the karaoke painter is mounted. The next row also uses animation priority so continuous playback tickers cannot starve the immediate transition cache; the remaining neighborhood uses idle priority. This avoids a synchronous cold-layout cost in the visible frame, at the cost of a brief plain-text fallback for an unusually cold seek or immediate first open. Device profiling is still required to prove frame-time behavior.

## Non-goals
Do not change lyric timing/parsing, karaoke paint effects, blur, scroll physics, animation durations, or audio synchronization. Do not precompute the entire lyric file synchronously.

## Verification
Add focused cache tests for reuse, layout-key invalidation, bounded eviction, and disposal behavior. Respect the repository/user verification constraint: run `flutter analyze` only; do not run tests or build an APK in this task. Report that actual frame pacing requires an on-device profile capture.
