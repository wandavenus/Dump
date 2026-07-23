---
name: Crossfade repeat-all artifact (queue[0] plays during fade-in)
description: Root cause and fix for the bug where queue[0] plays ~1 s during B's fade-in when REPEAT_MODE_ALL is active.
---

## The Bug
During A→B crossfade with REPEAT_MODE_ALL: the first song in the queue (queue[0]) briefly plays for ~1 s during B's fade-in.

## Root Cause
`CrossfadeController.beginCrossfade()` used to isolate the old player's queue by removing only the TAIL (items after A):
```kotlin
current.removeMediaItems(ci + 1, current.mediaItemCount)  // removes B, C, D
```
But PREFIX items (queue[0]…A-1) were left intact. When A finishes before the fade completes — common due to:
- VBR/MP3 duration estimation imprecision (`p.duration` ≠ actual track end)
- 200 ms position-ticker jitter (crossfade trigger fires up to 200 ms early)

…ExoPlayer fires an auto-advance. With REPEAT_MODE_ALL and no items after A, it wraps to index 0 = queue[0]. queue[0] plays at the still-nonzero fade-out volume (cos curve) for up to ~1 s until `runEqualPowerFade` step >= steps and calls `oldPlayer.pause()`.

## Fix (CrossfadeController.beginCrossfade)
1. Also remove PREFIX items (indices 0..ci-1) so old player contains exactly [A].
2. After `setActivePlayer(standby)` (NOT before — to suppress `onRepeatModeChanged` emit to Flutter), set `current.repeatMode = Player.REPEAT_MODE_OFF`.

**Why after setActivePlayer:** The listener guard `isActiveEvent()` returns false for the old player after promotion. If done before, `onRepeatModeChanged` fires with REPEAT_MODE_OFF and the Flutter UI repeat button resets incorrectly.

## How to Apply
Any future modification to `beginCrossfade()` that touches player isolation must keep these invariants:
- Old player must contain exactly 1 item (A) after isolation
- `repeatMode = REPEAT_MODE_OFF` must be set on old player AFTER `setActivePlayer(standby)`
