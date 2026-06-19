---
name: Dual-Player Architecture
description: Fully native dual ExoPlayer crossfade in Media3PlaybackService.kt; Dart DualPlayerManager + CrossfadeController are no-op stubs.
---

# Dual-Player Crossfade Architecture (Fully Native)

## The Rule
All crossfade logic — standby player preload, fade-in/fade-out, MediaSession promotion — runs in `Media3PlaybackService.kt`.
`DualPlayerManager.dart` and `CrossfadeController.dart` are **no-op stubs** retained only for call-site compatibility.

**Why:** Dart-side crossfade used a 20ms timer on the Dart VM which was unreliable in background. Native Handler tick fires precisely even when the Dart isolate is paused.

## Architecture
- `primaryPlayer` + `secondaryPlayer` (ExoPlayer instances)
- `activePlayer` pointer — the one connected to MediaSession + emitting events
- `standbyPlayer()` — the other one; silently preloads next track at volume=0
- Position ticker: `positionTicker` Runnable (200ms) → `maybeCrossfadeOut()`
- When remaining ≤ crossfadeDurationSec: `promoteSecondaryPlayer()`
  - Switches `activePlayer` to standby
  - Calls `session.setPlayer(newPlayer)`
  - Starts `startCrossfadeFadeIn(new, old)` — 25-step linear fade over crossfadeDuration
  - After fade completes: `restoreQueueOnActivePlayer(newPlayer)` so it knows full queue for next preload
- `crossfadeInProgress` flag prevents duplicate promotions
- `promotionOwner` stores old player reference to ignore its events during transition

## Key Variables
- `crossfadeDurationSec: Float` — 0 = gapless only, >0 = dual-player crossfade
- `activeQueueIndex: Int` — Dart-visible current index; updated on transition
- `preloadedQueueIndex: Int` — which queue index standby currently has loaded
- `playerListeners: IdentityHashMap<ExoPlayer, Player.Listener>` — listener per player

## applyAll() after transition
After track transition, `AudioEffectsService.applyAll()` is called twice from Dart (immediate + 350ms delay) triggered by `_syncCurrentTrackFromNative` inside AudioService. Delay covers native audio session re-attach race on MIUI 12.

## Dart stubs (do not use for logic)
- `DualPlayerManager` — stub, exposes `AudioPlayer` adapter but real playback is native
- `CrossfadeController` — all methods are no-ops; `isFading` always returns false
