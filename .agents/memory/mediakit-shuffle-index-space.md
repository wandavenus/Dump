---
name: MediaKit shuffle index-space mismatch
description: media_kit/mpv playlist positions are in native/shuffled order, distinct from the Dart _queue's original order — any index crossing this boundary must go through a URI lookup, not be trusted as-is.
---

`media_kit`'s `Player.setShuffle(true)` physically reorders mpv's internal playlist. From then on, `state.index` (from `Player.stream.playlist`) and mpv's `playlist-pos` property (set by `Player.jump(index)`) are in **native/shuffled order** — a different index space than `MediaKitEngine._queue`, which is always kept in original (unshuffled) order for queue display/persistence.

**Why:** `Media.uri` is stored verbatim (no normalization) from the string passed to `Media(uri)`, so it's a stable, cheap identity key across both spaces for local `file://` paths. Any code that takes an index in one space and feeds it into an API expecting the other space (without translating) will silently pick the wrong song — audio may still play correctly (native operates consistently within its own space) while metadata/UI or a jump target is wrong.

**How to apply:** Whenever an index crosses the boundary between `_queue` (original order) and mpv's native playlist (`state.playlist.medias`, `state.index`, `jump()`'s `playlist-pos`), never assume the two align — resolve via URI: build `'file://${song.path}'` and use `indexWhere` against the other side's media/song list to get the correct index before using it. This applies in both directions: native→queue (reading `state.index` to find the current song) and queue→native (calling `jump()` with a queue index). Same fix pattern is needed anywhere else a raw index is passed across this boundary in the future (e.g. any new native-facing media_kit API that takes/returns a playlist position).
