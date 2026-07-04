---
name: MediaKit engine dispose pattern
description: Correct shutdown order for MediaKitEngine to prevent "Player has been disposed" crash.
---

## The pattern (as of the lifecycle fix)

`dispose()` in `MediaKitEngine` must follow this exact order to eliminate the async race:

1. `_disposed = true` — gates ALL callbacks and continuations immediately
2. `MediaKitServiceBridge.setTransportCommandHandler(null)` — severs transport handler before any await
3. `_cancelSleepTimerInternal()` — pure Dart, no await
4. `final playerToDispose = _player; _player = null; _queue = []; _currentIndex = 0;` — **null the field before any await**, closing the async race window for all suspended continuations
4.5. `await playerToDispose?.pause();` — **explicitly stop playback here**, using the captured reference, before any teardown call below
5. `await MediaKitServiceBridge.stopListening()` — cancel EventChannel sub BEFORE stopService
6. `MediaKitSettingsService.unregisterPlayer()`
7. `await MediaKitServiceBridge.stopService()` — native can emit "stop" event here but sub is already cancelled
8. cancel `_subs`, `_subs.clear()`
9. `await playerToDispose?.dispose()` — dispose the captured instance last

**Why:**
- `_disposed = true` + handler severed synchronously (steps 1–2) guarantees no new transport command enters after this point.
- Nulling `_player` before the first `await` (step 4) means any async continuation that was suspended BEFORE `_disposed` was set will resume and see `_player == null`, making all `_player?.method()` calls safe no-ops.
- `stopListening()` before `stopService()` (steps 5→7): native "release" handler calls `updateStateAndEmit("stop")` before returning the MethodChannel result — so the event is enqueued in Dart BEFORE the `await stopService()` completes. Cancelling the sub first means that event is dropped by the channel layer rather than delivered to Dart.

**Why not the other way (stopService before stopListening):**
The old order caused native to enqueue a transport event → Dart subscription still active → event delivered → `_handleTransportCommand` called with non-null but internally-disposed player → assertion failure.

**Why step 4.5 exists (added after a regression):**
Before the disposed/no-await-race fix existed, playback was actually stopped as a *side effect* of native emitting a "stop" transport event that flowed through the (still-listening) EventChannel into `_handleTransportCommand('stop')`. Once steps 1–2 sever the transport handler and `_disposed` gates it, that side channel no longer stops audio — so without an explicit stop, `stopListening()`/`stopService()` just tear down the notification/service while mpv keeps playing, and `playerToDispose.dispose()` runs on a still-playing player (notification disappears, audio keeps going; also lets two engines play simultaneously during `switchEngine`). `Player.pause()` in media_kit forwards synchronously to mpv's `pause` property before the platform-channel call returns, so `await pause()` alone is sufficient — no `Future.delayed()` polling needed.

**How to apply:**
Any future change to `MediaKitEngine.dispose()` must preserve steps 1–4 as synchronous (no await between them), must not move `stopListening()` after `stopService()`, and must keep step 4.5 (explicit `await playerToDispose?.pause()`) — do not go back to relying on a native "stop" transport event to halt audio during teardown.

## All callback locations that need `_disposed` guard

Every lambda inside `_subscribeToPlayer()` captures local `p` (not `_player` field), so all must have `if (_disposed) return` since `p` remains non-null after `_player = null`.

Also guard: `_handleTransportCommand()`, `_pushPositionIfDue()`, `_triggerSleepStop()`, `_rebuildQueue()`.

`_emitPlaybackState()` is self-guarding via `final p = _player; if (p == null) return`.

## `setTransportCommandHandler` accepts nullable

`MediaKitServiceBridge.setTransportCommandHandler(null)` is the way to sever the handler. The bridge's listener uses `_transportHandler?.call(...)` so null is safe.
