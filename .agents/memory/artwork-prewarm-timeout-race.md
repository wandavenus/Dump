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
