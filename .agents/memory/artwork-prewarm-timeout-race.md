---
name: Artwork prewarm timeout race on cold start
description: Why Recently Played/Album/Artist artwork sometimes flickers/reloads after app kill instead of showing zero-delay
---

# Artwork prewarm timeout race on cold start

## The bug
`ArtworkRepository.prewarmImageCache()` in `main.dart` decodes the first-frame
home artwork (Recently Played/Album/Artist) into Flutter's `ImageCache` before
`runApp()`, each capped by a `timeout`. If the timeout fires before the decode
finishes, `main()` proceeds to `runApp()` with that image NOT in `ImageCache`,
so `SongArtwork` falls back to its async `_load()` path — a visible reload
instead of zero-delay artwork.

**Why inconsistent:** right after a MIUI system-kill, storage I/O is
contended by other apps also cold-starting, so decode time varies run to run.
`warmUp()` itself (populating `_diskCachedIds`) is NOT the race — it's fully
awaited via `Future.wait` in `main()` and `await for` drains completely before
the Future resolves.

## The fix
- Priority timeout raised from 900ms (album/artist) / 2000ms (recent) to a
  shared 3000ms constant.
- The three prewarm batches (Recently Played/Album/Artist) now run
  concurrently via `Future.wait`, not sequentially — bounds worst-case cold
  start delay to ~3s total instead of summing per-section timeouts.

**How to apply:** if adding a new above-the-fold home section with its own
artwork prewarm, add it to the same concurrent `Future.wait` batch with the
shared timeout constant, not a new sequential `await`.

## Second, actual root cause: split devicePixelRatio reads (fixed)
The timeout fix alone did NOT fix it — user confirmed Recently Played still
reloaded on real device while Album cards (size >= 250, plain `FileImage`,
no `ResizeImage`) were always zero-delay. That size split was the key clue.

`main.dart`'s prewarm and `SongArtwork`'s own load path each independently
called `WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio`
at two different times (once pre-`runApp()`, once per widget build). If those
two reads ever disagreed (display metrics not fully settled on the very first
read in `main()`), the two `ResizeImage(width, height)` instances built for
the same song have different width/height → different `ImageCache` key →
the prewarm is a cache miss for the widget that actually renders it → visible
reload. Only `<250px` artwork uses `ResizeImage` (Recently Played/Artists at
170px); Album cards (>=250px) use plain `FileImage`, unaffected — exactly
matching the field report.

**Fix:** `ArtworkRepository.resolveTargetPx(size)` resolves devicePixelRatio
ONCE, caches it for the process lifetime, and is now the only place that
reads it. `main.dart`'s prewarm and `song_artwork.dart`'s sync+async load
paths all call this shared resolver instead of reading DPR independently.

**How to apply:** never call `devicePixelRatio` directly for artwork sizing —
always go through `ArtworkRepository.instance.resolveTargetPx(size)` so the
prewarm path and the widget's own path can never disagree on the ResizeImage
cache key.
