# Notification Artwork Audit — 2026-08-11

## Scope

Audit read-only terhadap jalur artwork Android:

- `PlaybackNotificationManager` — custom foreground notification, `largeIcon`, async loading, prewarm, and caches.
- `SessionArtworkProvider` — high-resolution `MediaMetadata.artworkData`.
- `FallbackBitmapLoader` — Media3 legacy/Bluetooth/lock-screen bitmap loading.
- `Media3PlaybackService` and `ActivePlayerProxy` — lifecycle, player transitions, and metadata publication.

No production code was changed as part of this audit.

## Executive summary

The architecture correctly recognizes that MIUI/SystemUI can render MediaSession artwork rather than the notification `largeIcon`, and it provides separate fallbacks for embedded artwork, the shared artwork cache, and MediaStore. The main remaining correctness risk is an asynchronous notification race: a result for the previous track can be posted after a rapid track transition and temporarily restore the old title/artwork.

There is also an actual cross-thread access problem in the session artwork byte cache, plus a fallback path that can upscale a small MediaStore thumbnail to 1024×1024. These can cause intermittent behavior or preserve pixelation when the higher-quality sources are unavailable.

## Findings

### P1 — Stale async notification result can overwrite the current track

**Evidence**

- `android/app/src/main/kotlin/dev/wndavenz/music/notification/PlaybackNotificationManager.kt:190-217`
- `android/app/src/main/kotlin/dev/wndavenz/music/notification/PlaybackNotificationManager.kt:123-145`

`refreshAsync()` captures `track` and `isPlaying` for the track that initiated the load. When the worker finishes, it checks only the generation for that artwork cache key, then posts:

```kotlin
postNotification(buildNotification(sess, track, isPlaying, bmp))
```

It does not verify that `cacheKey` is still `currentTrackCacheKey()`. A rapid A → B transition can therefore produce this sequence:

1. Track A starts an async artwork load.
2. Track B becomes current and refreshes the notification.
3. Track A's load completes and posts A's captured title/artwork.
4. Track B eventually posts its own result.

This creates a visible stale notification window and may leave the notification wrong if the newer load fails or is delayed.

**Recommendation**

Before posting an async result, require the loaded key to still match the current track. Prefer rebuilding the notification from the current track at completion time rather than using the captured `track` and `isPlaying`; retain the generation check for same-key cancellation.

### P1 — `SessionArtworkProvider.bytesCache` is accessed from multiple threads without synchronization

**Evidence**

- `android/app/src/main/kotlin/dev/wndavenz/music/SessionArtworkProvider.kt:61-93`
- `android/app/src/main/kotlin/dev/wndavenz/music/SessionArtworkProvider.kt:69-87`

`bytesCache` is an Android `LruCache`, which is not thread-safe. `provide()` reads it synchronously on the caller thread, normally the service handler/main thread, while the executor reads and writes the same cache. There is no lock or thread confinement around these operations.

The same method also has no in-flight deduplication. Multiple refresh triggers before the first worker stores the bytes can queue repeated extraction/encoding work on the single provider executor.

**Impact**

- Potential cache map races under repeated transition/READY callbacks.
- Avoidable repeated `MediaMetadataRetriever` and JPEG work during rapid transitions.

**Recommendation**

Use a synchronized cache access boundary (or confine all cache access to the provider executor), and add a per-song in-flight map so repeated requests share one result.

### P2 — Session fallback can upscale a low-resolution MediaStore thumbnail

**Evidence**

- `android/app/src/main/kotlin/dev/wndavenz/music/SessionArtworkProvider.kt:150-158`
- `android/app/src/main/kotlin/dev/wndavenz/music/SessionArtworkProvider.kt:161-175`
- `android/app/src/main/kotlin/dev/wndavenz/music/SessionArtworkProvider.kt:183-205`

When embedded artwork and the persistent cache are unavailable, `rawFromUri()` reads the MediaStore album-art thumbnail. For a non-square source, `letterboxSquare()` always creates a 1024×1024 canvas and scales the source to fit it. A small 256×512 thumbnail can therefore become a 1024×1024 `artworkData` payload without adding detail.

This is a fallback-only issue, but it can reintroduce pixelation in precisely the cases where the high-resolution sources failed.

**Recommendation**

Use a never-upscale target based on the source's longest side, matching the notification/fallback bitmap behavior, or avoid publishing the low-resolution URI result as `artworkData` and leave it only as an `artworkUri` fallback.

### P2 — Negative legacy artwork cache has no refresh window

**Evidence**

- `android/app/src/main/kotlin/dev/wndavenz/music/FallbackBitmapLoader.kt:77-92`
- `android/app/src/main/kotlin/dev/wndavenz/music/FallbackBitmapLoader.kt:140-146`
- `android/app/src/main/kotlin/dev/wndavenz/music/FallbackBitmapLoader.kt:149-169`

`noArtworkCache` is a static process-wide set keyed only by album ID. Once an album fails both embedded and URI resolution, later calls immediately fail for that album until the process restarts. If MediaStore indexes artwork later, or the file is updated while the service remains alive, the legacy/Bluetooth path will not retry.

**Recommendation**

Replace the permanent process-lifetime negative entry with a short TTL, or invalidate it on a MediaStore/library rescan or artwork-cache update. Keep the bounded positive cache.

### P2 — Global pending key can permit duplicate queued loads

**Evidence**

- `android/app/src/main/kotlin/dev/wndavenz/music/notification/PlaybackNotificationManager.kt:60-70`
- `android/app/src/main/kotlin/dev/wndavenz/music/notification/PlaybackNotificationManager.kt:153-179`
- `android/app/src/main/kotlin/dev/wndavenz/music/notification/PlaybackNotificationManager.kt:190-217`

`pendingAsyncCacheKey` is a single key, while the executor can have work for multiple cache keys queued. When the first job completes, its handler callback clears `pendingAsyncCacheKey` even if a later-key job is still queued or running. A subsequent refresh for that later key can enqueue duplicate work.

The per-key generation check prevents stale cache insertion, so this is primarily a latency/CPU issue rather than an artwork correctness issue.

**Recommendation**

Track in-flight keys independently from completion, or use a per-key in-flight map/future. Keep the existing per-key generation guard.

## Verified strengths

- The notification path prefers embedded artwork, then the shared persistent cache, and uses the MediaStore URI only as a last resort.
- Notification and legacy bitmap paths use bounds-first decoding and cap the longest dimension.
- Non-square artwork is letterboxed before the notification/legacy bitmap is returned.
- Session artwork clears old `artworkData` when no source can be resolved.
- Session artwork callbacks verify both the active player and `mediaId` before replacing the current MediaItem.
- Crossfade and non-crossfade transitions both prewarm the next notification artwork.
- `FallbackBitmapLoader` releases `MediaMetadataRetriever` in `finally`.

## Test gap

There are no focused tests covering the asynchronous artwork state machine. The highest-value regression tests should model:

1. A's load completing after an A → B transition.
2. Duplicate requests for the same session artwork while the first request is in flight.
3. A negative legacy cache entry becoming retryable after its TTL/invalidation.
4. A small non-square URI fallback not being upscaled.

## Audit conclusion

The high-resolution MediaSession metadata approach is directionally correct and addresses the original MIUI zoom/pixelation root cause for embedded/cache artwork. The stale async notification result is the most urgent remaining issue because it directly affects visible track correctness during normal rapid-skip behavior. The cache synchronization/deduplication issue should be fixed alongside it before relying on the artwork pipeline under repeated transitions.