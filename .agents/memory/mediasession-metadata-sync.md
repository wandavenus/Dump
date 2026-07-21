---
name: MediaSession metadata sync on crossfade (title/artist lag fix)
description: Why title/artist in the MIUI media widget lags during crossfade, and the fix applied in ActivePlayerProxy.switchTo().
---

# MediaSession Metadata Sync on Crossfade

## Rule
`ActivePlayerProxy.switchTo(newPlayer)` must fire synthetic `onMediaItemTransition` +
`onMediaMetadataChanged` events to `registeredListeners` immediately after migrating
listeners, so `MediaSessionCompat.setMetadata()` is broadcast to the system
synchronously — before `refreshNotification()` posts the notification.

## Why
On MIUI 12 (Android 11), the media notification layout (expanded card in notification shade
and lock screen media widget) reads title/artist from `MediaSessionCompat.metadata` via IPC,
NOT from `Notification.setContentTitle()` / `setContentText()`. Our `buildNotification()`
correctly sets `setContentTitle(newTitle)` at T=0, but MIUI renders the stale MediaSession
cache value until Media3's internal listener fires.

Without the fix, the sequence is:
1. T=0: `switchTo(standby)` → listeners migrated but no events fired → MediaSession cache = old track
2. T=0: `refreshNotification()` → notification posted with new title/artist (our setContentTitle) ← correct but MIUI ignores it for the media widget
3. T+16ms: ExoPlayer posts async callbacks → Media3 listener fires → MediaSessionCompat.setMetadata(new) → MIUI media widget updates

User sees: title/artist lags ~16ms+ (can be 100-500ms on MIUI due to SystemUI update cycle).

With the fix: step 1 immediately fires synthetic events → MediaSession broadcasts new metadata → by the time refreshNotification() posts the notification, MIUI reads the (now correct) metadata.

## How to apply
- `registeredListeners` in `ActivePlayerProxy` contains ONLY listeners registered via
  `activePlayerProxy.addListener()` — primarily Media3's internal `MediaSessionImpl.PlayerListener`.
- Our per-ExoPlayer listeners (registered directly on each ExoPlayer via `attachPlayerListener`)
  are NOT in `registeredListeners`, so synthetic events do NOT trigger our custom
  `onMediaItemTransition` handler in `Media3PlaybackService`.
- Fire `onMediaItemTransition(newItem, MEDIA_ITEM_TRANSITION_REASON_PLAYLIST_CHANGED)` and
  `onMediaMetadataChanged(newMeta)` — these are the two events Media3's PlayerListener
  uses to trigger `updateMediaSessionCompat()`.
- Wrap each call in try/catch to be resilient to listener implementation changes.
- This is safe even when `switchTo()` is called a second time at the end of crossfade
  (from `runEqualPowerFade` completion) — it fires again with the same newItem/newMeta,
  which is a no-op for the system since the metadata didn't change.
