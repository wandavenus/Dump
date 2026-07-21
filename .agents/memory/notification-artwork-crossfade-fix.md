---
name: Notification artwork crossfade fix (Patch A + B)
description: Two patches that eliminate blank-artwork window in notification during crossfade — dedup guard (RC-2) and prewarm artwork (RC-3).
---

# Notification Artwork Crossfade Fix

## Rule
Two complementary patches landed together in v1.3.6. Both are in effect simultaneously.

### Patch A — refreshAsync() dedup guard (RC-2 fix)
`PlaybackNotificationManager` now has a `pendingAsyncCacheKey: String?` field.
`refreshAsync()` bails early if `cacheKey == pendingAsyncCacheKey` — collapsing the 3
back-to-back `refreshAsync()` calls that fire within ~1 ms at crossfade start
(`onIsPlayingChanged` + `onPlaybackStateChanged` + `refreshNotification`) into a single
`loadBitmap()` call. Reduces worst-case artwork latency by ~3×.
`pendingAsyncCacheKey` is reset to `null` inside `handler.post` after load completes.

**Why:** Previously 3 tasks queued on the single-threaded `artworkExecutor`; only the
3rd result was kept (generation check discards the first two), so total wait was 3× one
loadBitmap() call (~150–900 ms on MIUI 12).

**How to apply:**
- `pendingAsyncCacheKey` is a main-thread-only field (all accesses via handler.post).
- Both `refreshAsync()` AND `prewarmArtwork()` must set/clear it to avoid double-enqueue.
- Do not add synchronisation — it's already single-threaded via handler.

### Patch B — prewarmArtwork() called during Phase 1 (RC-3 fix)
`PlaybackNotificationManager.prewarmArtwork(nextSongId, nextArtUri)` is a new public
method that starts a silent background artwork load (no notification posted on completion,
only `bitmapCache` populated).

`CrossfadeController` gains optional constructor parameter:
`prewarmNotificationArtwork: ((songId: Int, artUri: String?) -> Unit)? = null`

Invoked in `maybeCrossfadeOut()` Phase 1 block (the existing `PREWARM_LEAD_MS = 1500 ms`
prewarm window) right after `preloadManager.prewarmStandby()`. The next track's data is
read from `getQueue().getOrNull(preloadManager.preloadedQueueIndex)`, using keys `"id"`
(songId) and `"artworkUri"` (artUri).

`Media3PlaybackService` wires the lambda:
```kotlin
prewarmNotificationArtwork = { songId, artUri ->
    notificationManager.prewarmArtwork(songId, artUri)
},
```

**Why:** `artworkExecutor` was previously idle during the 1500 ms prewarm window.
Moving the load there means `bitmapCache` is populated by the time `beginCrossfade()`
calls `refreshNotification()` — notification posts synchronously with artwork.

**How to apply:**
- `prewarmArtwork()` is a no-op if cacheKey already in bitmapCache or noArtworkCache.
- `prewarmArtwork()` respects `pendingAsyncCacheKey` guard — won't double-enqueue.
- Worst case (very short track, prewarm+load race): falls back to original async behavior.
- Parameter is nullable/optional to keep CrossfadeController backward-compatible.
