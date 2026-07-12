---
name: getSongs() native call had no timeout — Home sections could spin forever
description: Every Home section and MusicList awaits MediaStoreService.getSongs() directly; if the underlying native MethodChannel call ever stalls with no persisted cache to fall back on, every one of them stays in its loading spinner forever with no error surfaced.
---

## The bug
`MediaStoreService._refreshSongsImpl()` awaited `_channel.invokeListMethod('getSongs')`
with no `.timeout(...)`. This is the single shared implementation behind
`MediaStoreService.getSongs()`, which every Home section
(`_RecentlyPlayedSectionState._load`, `_LocalAlbumsSectionState._load`,
artists_section, MusicList's `FutureBuilder`) awaits directly and gates its own
`_isLoading` / `FutureBuilder` spinner on. `getSongs()` only returns instantly
without hitting this native call when `_songsCache` is already populated (from
`MediaStoreService.warmUp()`'s persisted-cache hydration in `main()`) — on a
genuinely fresh install/first real-device run, there is no persisted cache, so
every section's first load goes through this unguarded native round-trip.

**Why this matters:** a MethodChannel call has no guaranteed response. If the
native side is ever slow to reply (e.g. a very large library's first
`ContentResolver` scan under I/O contention on a real device) or never replies
for any reason, the Dart `await` never resolves — every Home section and
MusicList stays stuck on its loading indicator indefinitely, which reads to
the user as "the app hangs and never reaches Home" even though the Scaffold
shell technically rendered.

**How to apply:** any new call site that awaits `MediaStoreService.getSongs()`
(or adds a new native MethodChannel round-trip anywhere reachable from a
first-frame UI path, not just `main()`'s own startup chain) must go through a
call that has a timeout with a fail-open fallback — same convention already
used for `ArtworkRepository.prewarmImageCache` and `FfmpegDecoderBridge`'s
capability probe. The fix here added a 20s `.timeout()` + `TimeoutException`
catch inside `_refreshSongsImpl()` itself, so the fallback is centralized and
every caller benefits without touching call sites individually.

**Related but distinct from** [Native MethodChannel startup blocking](native-methodchannel-startup-blocking.md),
which covers awaited platform-channel calls inside `main()`'s own serial
startup chain (before `runApp()`). This one is a per-widget async call on the
Home UI's first-render path, discovered separately — the same failure mode
(unguarded MethodChannel await = block forever) can recur outside `main()`
too, so audit both when chasing a "hangs / never shows content" report.
