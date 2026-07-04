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

**How to apply:**
Any future change to `MediaKitEngine.dispose()` must preserve steps 1–4 as synchronous (no await between them) and must not move `stopListening()` after `stopService()`.

## All callback locations that need `_disposed` guard

Every lambda inside `_subscribeToPlayer()` captures local `p` (not `_player` field), so all must have `if (_disposed) return` since `p` remains non-null after `_player = null`.

Also guard: `_handleTransportCommand()`, `_pushPositionIfDue()`, `_triggerSleepStop()`, `_rebuildQueue()`.

`_emitPlaybackState()` is self-guarding via `final p = _player; if (p == null) return`.

## `setTransportCommandHandler` accepts nullable

`MediaKitServiceBridge.setTransportCommandHandler(null)` is the way to sever the handler. The bridge's listener uses `_transportHandler?.call(...)` so null is safe.
