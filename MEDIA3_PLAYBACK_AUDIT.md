# Media3PlaybackService Architecture Audit

## Scope

This audit reviewed `Media3PlaybackService.kt` for playback races, queue/crossfade synchronization, state/event consistency, notification updates, listener lifecycle, memory usage, end-of-queue behavior, and work performed during playback. The refactor plan keeps the MethodChannel/EventChannel contract unchanged while moving responsibilities into focused modules.

## Detected Issues

### Race conditions

- Crossfade promotion changes `activePlayer` while ExoPlayer callbacks from the old player can still arrive. The existing guard ignores old-player transition callbacks, but several other callbacks can still emit state during promotion.
- Queue persistence is asynchronous. The existing snapshot fix avoids reading a mutated queue on the worker thread, but saves can still complete out of order when many queue operations happen quickly.
- Sleep timer end-of-song mode and crossfade promotion both react around a track boundary. Without a single coordinator, a timer stop can race with preloading/promotion.

### Queue synchronization issues

- During crossfade, queue mutations update the Dart/native list but intentionally skip the active ExoPlayer queue. This prevents crashes but can leave ExoPlayer and the service queue temporarily divergent.
- `activeQueueIndex` is manually updated in multiple methods, making reorder/remove/transition behavior fragile.
- Shuffle and repeat state are copied to the standby player only during preload. Changes after preload require explicit standby invalidation.

### Crossfade edge cases

- Promotion can occur near the exact end of a track; if the active item ends before the standby player starts, state can flip to completed before promotion finishes.
- Standby queue invalidation is scattered across skip, shuffle, repeat, queue mutation, and duration changes.
- Old-player tail removal during promotion is defensive but may be unnecessary work and can trigger extra callbacks.

### Playback state inconsistencies

- Event emission derives current index from `activeQueueIndex` when crossfade is enabled, but directly from ExoPlayer otherwise. This makes state source-of-truth dependent on crossfade mode.
- `play`, notification play/pause, skip from ended, and repeat/shuffle paths each handle ended/prepare logic separately.

### Notification synchronization bugs

- Notification construction was duplicated between foreground startup and refresh paths, increasing drift risk for icons, actions, title, artist, and ongoing state.
- Artwork decoding happens synchronously during notification refresh and can be triggered by frequent playback callbacks.

### Duplicate event emissions

- `emitAll()` is called by direct method handlers, player listeners, position ticker, notification actions, and final MethodChannel fall-through.
- Repeat mode is partially deduped in `emitAll()`, but listener callbacks also emitted repeat/shuffle immediately.

### Listener leaks and memory leaks

- Player listeners are tracked in an identity map and detached for standby release, which is good. Risk remains if a future path releases a player without going through the helper.
- Static service instance and EventChannel sinks are acceptable for this pattern, but sinks should remain centralized to avoid accidental extra references.
- Notification artwork decode can allocate bitmaps repeatedly without caching or sizing.

### End-of-queue bugs

- Multiple code paths restart from index 0 when ended, even when repeat/shuffle semantics may expect ExoPlayer's next/previous index behavior.
- Crossfade preloading exits when `nextMediaItemIndex` is unset; this is correct for repeat off, but queue mutation during that window can require re-preload.

### Unnecessary work and performance bottlenecks

- `emitAll()` emits many channels every 200ms while playing, even if only position changed.
- Notification refresh can run on every state change and can decode artwork synchronously.
- Persistence starts a raw thread for each save instead of serializing writes.

## Refactor Strategy

1. Introduce module boundaries matching the requested architecture.
2. Keep `Media3PlaybackService.kt` as the compatibility/orchestration layer while moving reusable responsibilities out incrementally.
3. Centralize event emission in `events/EventEmitter` and apply lightweight dedupe for stable scalar events.
4. Centralize media item and current-track mapping in `utils/MediaItemFactory` and `utils/TrackMapper`.
5. Add queue primitives in `queue/QueueManager` to make active-index math reusable and testable.
6. Add queue persistence abstraction in `queue/QueueSync` for serialized snapshot save/restore follow-up work.
7. Add transport state helpers in `transport/TransportCommands` and `transport/TransportState` to avoid duplicated state mapping.
8. Add crossfade/preload state holders to clarify promotion/preload ownership and prepare further extraction.
9. Add audio-focus and sleep-timer managers so focus/timer behavior can be delegated without changing public APIs.
10. Preserve every existing MethodChannel and EventChannel name and payload shape.

## Follow-up Recommendations

- Move notification building into a full notification manager with artwork decode caching or background loading.
- Serialize queue persistence writes on a single executor and coalesce rapid saves.
- Make one canonical playback snapshot source for current index, repeat, shuffle, and processing state.
- Add instrumentation tests for queue mutation during crossfade, repeat-one/all at end of queue, and sleep end-of-song during crossfade.
