---
name: Lyrics Karaoke Layout Cache
description: Cached TextPainter geometry and incremental prewarming for synchronized karaoke lyrics.
---

# Lyrics Karaoke Layout Cache

## Ownership and files
- `lib/widgets/player/synced_lyrics_view/karaoke_layout_cache.dart` contains `KaraokeLayoutCache`, `KaraokeLineLayout`, and `KaraokeWordBox`.
- Each `SyncedLyricsView` owns one cache in `state.dart`; the state disposes it when the view is disposed and clears it when the lyric payload changes.
- The cache owns both TextPainters and the word bounding boxes. `_KaraokeLinePainter` only reads an entry during paint; it does not dispose cached resources.
- The cache is a 16-entry LRU keyed by line index, text/word timeline identity, viewport width, font size, text scale, alignment, direction, and colors.

## Prewarming
- `state_karaoke.dart` captures the geometry configuration from the actual list viewport width.
- While hidden, the current line and neighborhood are queued at idle priority.
- While visible, the current and next two lines use `Priority.animation` so continuous playback tickers cannot starve the immediate transition cache; the remaining neighborhood uses one-line `Priority.idle` tasks.
- A generation token invalidates queued work when the lyric payload, geometry configuration, visibility, or active-line anchor changes. Repeated builds with the same anchor do not restart the task chain.
- Cache capacity 16 is larger than the 11-line prewarm window, so nearby entries can remain warm across normal sequential line changes.

## Invalidation and constraints
- Clear on lyrics/raw-LRC changes and on configuration changes (viewport width, font size, text scale, alignment, active/dim colors). Direction is independently included in each entry key.
- Do not move all-line geometry work synchronously into initState/build. Idle tasks spread work outside the frame that needs the next line.
- A cold active line is rendered as ordinary `Text` until its geometry is prepared at `Priority.animation`; only then is the karaoke painter mounted. Following lines are prepared at `Priority.idle`, so `CustomPainter.paint` does not need a synchronous cold-layout fallback in the normal widget path.
- Existing lyric timestamps, karaoke painter effects, blur, scroll spring (550 ms), and row transition (800 ms) remain unchanged.

## Verification limits
- Cache behavior has focused tests under `test/widgets/player/synced_lyrics_view/karaoke_layout_cache_test.dart`.
- User constraint for Flutter/Dart changes is `flutter analyze` only; do not run Flutter tests or APK builds in this workflow.
- Actual frame-time improvement is not established by static analysis; validate first-open and sequential line-transition frame timing on a real device in profile mode.
