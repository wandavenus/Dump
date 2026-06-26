# Crossfade Renderer Restart Investigation

## Background

### Symptoms

Every crossfade produces a consistent 50–200 ms audible dropout that occurs immediately
**after** the fade completes, not during it. The fade itself sounds clean. The gap appears
in the first fraction of a second of the promoted track's full-volume playback. The
symptom is reproducible on every crossfade regardless of track format or library size.

### Timeline Summary

Instrumentation added to `CrossfadeTimelineLogger`, `QueueManager`, `AudioEffectsManager`,
and the `AnalyticsListener` block in `Media3PlaybackService` revealed the following event
order on every crossfade:

```
[+0 ms]   CrossfadeController.beginCrossfade()
[+Xms]    runEqualPowerFade: COMPLETE
          oldPlayer.pause() / stop() / clearMediaItems()
          setActivePlayer(newPlayer)
          ActivePlayerProxy.switchTo(newPlayer)
[+Xms]    onCrossfadeComplete() ENTER
[+Xms]    rebuildPlayerQueue() PRE-setMediaItems   ← synchronous call on Handler thread
[+Xms]    rebuildPlayerQueue() POST-setMediaItems
[+Xms]    attachEffects() START
[+Xms]    attachEffects() DONE
[+Xms]    AudioRenderer DISABLED  (isActive=true)  ← dropout begins here
[+Xms]    AudioDecoder RELEASED   (isActive=true)
[+Xms]    AudioTrack  RELEASED    (isActive=true)
[+Xms]    AudioRenderer ENABLED   (isActive=true)
[+Xms]    AudioDecoder INITIALIZED (isActive=true, initDuration=50–200 ms)
[+Xms]    AudioTrack  INITIALIZED  (isActive=true)
```

`AudioRenderer DISABLED` fires after both `rebuildPlayerQueue()` and `attachEffects()`
have returned on the main thread. This is the canonical async-cause / delayed-effect
pattern: the operation that causes the renderer disable posts a message to ExoPlayer's
playback looper and returns immediately; the looper processes the message and fires the
`AnalyticsListener` callback after the main thread has moved on.

---

### Root Cause Investigation

#### Why the renderer restart occurs

ExoPlayer's `MediaCodecAudioRenderer` is disabled by `ExoPlayerImplInternal` whenever the
currently playing `MediaPeriod` is invalidated. A period is invalidated when the
`MediaSourceHolder` that owns it is removed from (or replaced in) the `MediaSourceList`.

`ExoPlayerImplInternal.resetInternal()` always calls `disableRenderers()` unconditionally,
regardless of the `resetRenderers` parameter. `resetRenderers` only controls whether the
codec state is additionally cleared. The `disableRenderers()` call itself is not optional.

Once the renderer is disabled, the audio pipeline shuts down:

1. `AudioRenderer` releases its `MediaCodec` decoder (`AudioDecoder RELEASED`).
2. `DefaultAudioSink` releases its `AudioTrack` (`AudioTrack RELEASED`).
3. The renderer is re-enabled and a new `AudioTrack` is created.
4. A new decoder session initialises (`AudioDecoder INITIALIZED`, `initializationDurationMs`
   = the audible gap duration).

The `initializationDurationMs` reported by `onAudioDecoderInitialized` is the exact
acoustic dropout length (50–200 ms).

---

#### Why `setMediaItems()` causes the renderer reset

`QueueManager.rebuildPlayerQueue()` is called in `onCrossfadeComplete()` to restore the
full queue on the promoted player. At the moment this call is made:

- The promoted player (former standby) has **exactly one** `MediaItem` — the single track
  loaded by `PreloadManager.preloadNextTrack()` — at internal ExoPlayer index 0.
- `activeQueueIndex` is the position of that track within the full N-item
  `queueManager.queue`.

`rebuildPlayerQueue()` then calls:

```kotlin
p.setMediaItems(
    queue.map { MediaItemFactory.from(it) },  // N new MediaItem objects, new UIDs
    activeQueueIndex,                          // target index in the new list
    currentPos,
)
```

Internally (`ExoPlayerImpl.java` → `ExoPlayerImplInternal.java`):

1. `setMediaItems()` calls `setMediaSourcesInternal()`, which clears
   `mediaSourceHolderSnapshots` and replaces the entire `MediaSourceList` with N new
   `MediaSourceHolder` objects, each with a freshly allocated UID.
2. The currently playing `MediaPeriod` holds a reference to the **old** `MediaSourceHolder`
   UID (the single item that was loaded at prewarm time). That UID no longer exists in the
   new `MediaSourceList`.
3. ExoPlayer detects the period invalidation. `resetInternal(resetRenderers=false)` is
   called, which calls `disableRenderers()` unconditionally.
4. The audio pipeline is torn down and rebuilt.

This is not an edge case or a timing issue. **Every call to `setMediaItems()` on a playing
ExoPlayer instance goes through `disableRenderers()`** because `setMediaItems()` always
creates a new `MediaSourceList` with new UIDs. There is no path through `setMediaItems()`
that preserves the current period.

The comment in `rebuildPlayerQueue()` that says _"ExoPlayer recognises it and keeps the
active decoder alive without any audible interruption"_ is incorrect. ExoPlayer does not
compare URIs or `MediaItem` content to preserve a playing decoder across `setMediaItems()`.
It compares `MediaSourceHolder` object identity (UID), which is always different after a
`setMediaItems()` call.

---

#### Why `attachEffects()` is not the root cause

`AudioEffectsManager.attachEffects()` calls `AudioEffect.release()` on existing effects,
then constructs new `Equalizer`, `LoudnessEnhancer`, `BassBoost`, `Virtualizer`, and
`PresetReverb` objects against the audio session ID. These are Android OS AudioFlinger
operations that are entirely external to ExoPlayer's renderer.

`DefaultAudioSink` owns its `AudioTrack` object independently. No external `AudioEffect`
operation can cause ExoPlayer to call `DefaultAudioSink.reset()` or release that
`AudioTrack`. `AudioTrack RELEASED` is an event that only ExoPlayer's own sink emits,
triggered exclusively by renderer lifecycle events inside ExoPlayer.

The fact that `AudioRenderer DISABLED` appears **after** `attachEffects()` in the log does
not mean `attachEffects()` caused it. `setMediaItems()` posts a message to ExoPlayer's
playback looper and returns immediately. `attachEffects()` then runs synchronously on the
main thread. The looper processes the `setMediaItems` message and fires `DISABLED` only
after `attachEffects()` has already completed on the main thread — classic async-cause /
delayed-callback ordering.

---

## Design Options Considered

---

### Option A — Skip rebuild when queue is unchanged

**Description:**  
Add a `queueMutatedDuringCrossfade: Boolean` flag to `QueueManager`. Set it whenever any
mutation (`insertNext`, `appendToQueue`, `removeFromQueue`, `reorderQueue`) fires while
`isCrossfadeInProgress()` is true. In `onCrossfadeComplete()`, call `rebuildPlayerQueue()`
only when the flag is set; skip it otherwise.

**Advantages:**
- Smallest possible change: one boolean field, one conditional, one flag reset.
- Eliminates the dropout for the statistically dominant case: uninterrupted natural
  playback where the user does not mutate the queue during a crossfade.
- Zero risk to any other code path.
- Can be deployed immediately as a stopgap.

**Disadvantages:**
- Does not eliminate the dropout unconditionally. If the user inserts, removes, or reorders
  a track during a crossfade (even once per listening session), the dropout still occurs.
- The fix is incomplete by design; it documents that the problem exists and defers it.
- The structural issue in `rebuildPlayerQueue()` remains and can regress.

---

### Option B — Incremental queue rebuild using `addMediaItems()` *(Recommended)*

**Description:**  
Replace the single `setMediaItems(fullQueue, activeIdx, pos)` call in
`rebuildPlayerQueue()` with two sequential `addMediaItems()` calls — one for the items
before the current track, one for the items after it.

#### Technical explanation

After crossfade promotion, the promoted player has exactly one `MediaSourceHolder` in its
`MediaSourceList` — the item that was loaded during prewarm. Its internal ExoPlayer index
is 0. `activeQueueIndex` is the logical position of that item in the full
`queueManager.queue`.

The expansion is:

```kotlin
val prefix = queue.subList(0, activeQueueIndex)           // items before current track
val suffix  = queue.subList(activeQueueIndex + 1, queue.size) // items after current track

if (prefix.isNotEmpty()) {
    // Inserts N items at index 0. ExoPlayer shifts the current item's window
    // index from 0 to activeQueueIndex. The MediaSourceHolder UID is unchanged.
    p.addMediaItems(0, prefix.map { MediaItemFactory.from(it) })
}
if (suffix.isNotEmpty()) {
    // Inserts M items after the current track. Current item stays at activeQueueIndex.
    p.addMediaItems(activeQueueIndex + 1, suffix.map { MediaItemFactory.from(it) })
}
```

#### Why it preserves the current `MediaSourceHolder`

`ExoPlayerImpl.addMediaItems()` calls `addMediaSourcesInternal()`, which calls
`mediaSourceHolderSnapshots.add(i + index, ...)` — inserting new holders without
replacing any existing ones. The `MediaSourceHolder` for the currently playing track retains
its original UID throughout both `addMediaItems()` calls.

`ExoPlayerImplInternal.addMediaItemsInternal()` calls `handleMediaSourceListInfoRefreshed()`
with the updated timeline. Because the current period's `MediaSourceHolder` UID still
exists in the updated `MediaSourceList`, ExoPlayer resolves the new window index for the
unchanged period, updates its internal timeline representation, and continues rendering.
`disableRenderers()` is never called.

This is the same mechanism that allows any playlist application to add tracks to an
`ExoPlayer` instance during playback without causing audio interruption.

#### Why it avoids the renderer restart

`addMediaItems()` does not call `resetInternal()`. It calls `handleMediaSourceListInfoRefreshed()`
directly, which evaluates whether the current `MediaPeriod` is still valid. Since the UID
is preserved, the period is valid, and the renderer lifecycle is not touched.

The `onAudioDecoderInitialized`, `onAudioDecoderReleased`, `AudioRenderer DISABLED`, and
`AudioRenderer ENABLED` callbacks will not fire as a result of these two `addMediaItems()`
calls.

#### Memory impact

No change. The promoted player gains N-1 `MediaSourceHolder` references (one was already
present). Each reference is approximately 300–500 bytes. For a 1 000-track library the
total additional heap use is approximately 500 KB. ExoPlayer does not buffer or open
connections for any items outside its lookahead window; descriptor-only items have no I/O
cost.

#### Queue synchronisation impact

`queueManager.queue` remains the single authoritative source of truth throughout. The
prefix and suffix passed to `addMediaItems()` are sliced from `queueManager.queue` at
the moment `onCrossfadeComplete()` fires. Any mutations that occurred during the crossfade
(insertions, removals, reorders) are already reflected in `queueManager.queue` because all
mutation methods update the in-memory list immediately, even when the ExoPlayer call is
deferred. The resulting promoted player queue is always exactly consistent with
`queueManager.queue`.

The existing deferred-mutation pattern (mutations update the list but skip the ExoPlayer
call during `isCrossfadeInProgress()`) is unchanged. `rebuildPlayerQueue()` remains in
`onCrossfadeComplete()` exactly where it is now; only the internals change.

#### Expected behavior

After the fix is applied:

```
[+0 ms]   CrossfadeController.beginCrossfade()
[+Xms]    runEqualPowerFade: COMPLETE
[+Xms]    onCrossfadeComplete() ENTER
[+Xms]    rebuildPlayerQueue(): addMediaItems(0, prefix)   ← no disableRenderers()
[+Xms]    rebuildPlayerQueue(): addMediaItems(N+1, suffix) ← no disableRenderers()
[+Xms]    attachEffects() START / DONE
          [no AudioRenderer DISABLED]
          [no AudioDecoder RELEASED]
          [no AudioTrack RELEASED]
          [no AudioDecoder INITIALIZED]
```

The crossfade is acoustically seamless.

#### Remaining edge cases

- **`queue.size == 1`**: Both prefix and suffix are empty. Neither `addMediaItems()` call
  is made. No behaviour change.
- **`activeQueueIndex == 0`**: Prefix is empty, only the suffix call is made.
- **`activeQueueIndex == queue.size - 1`**: Suffix is empty, only the prefix call is made.
- **Shuffle order**: Each `addMediaItems()` call internally rebuilds the `ShuffleOrder`
  via `shuffleOrder.cloneAndInsert()`. The resulting shuffle order matches the behaviour of
  the current `setMediaItems()` call (both produce a new shuffle order). Users who have
  shuffle enabled will see the same behaviour as today.
- **Repeat mode**: Unaffected. Repeat mode is set on the standby player during
  `preloadNextTrack()` (`standby.repeatMode = current.repeatMode`) and is not touched by
  queue expansion.
- **`setMediaItems()` fallback**: If the promoted player somehow already has the full queue
  (`p.mediaItemCount == queue.size`), the expansion is skipped entirely to avoid
  redundant work.

---

### Option C — Preload full queue into standby

**Description:**  
Change `PreloadManager.preloadNextTrack()` to call
`standby.setMediaItems(fullQueue, nextIndex, 0)` instead of
`standby.setMediaItem(queue[nextIndex])`. The standby player holds the full queue from
the moment it is preloaded. `rebuildPlayerQueue()` in `onCrossfadeComplete()` is removed
or becomes a no-op.

**Advantages:**
- Eliminates the `setMediaItems()` call on the promoted player entirely.
- The promoted player arrives fully configured; no post-promotion work is required.
- Dropout is eliminated for the common case (no queue mutations during preload lifetime).

**Disadvantages:**
- **Queue divergence**: `preloadNextTrack()` is called at the start of each track (or after
  each crossfade). The preload-to-promotion window is the full playback duration of the
  current track — potentially 3–5 minutes for a long piece. Any mutation during this window
  (`insertNext`, `removeFromQueue`, `reorderQueue`) applies to `queueManager.queue` and to
  the active player, but **not** to the standby player, because the existing mutation
  methods only target `getPlayer()` (the active player). After promotion, the standby's
  ExoPlayer queue is stale. Subsequent skip, remove, or reorder operations act on wrong
  indices.
- **Structural complexity**: To close the divergence window, every mutation method must be
  extended to also update the standby player when a standby player exists. This doubles the
  ExoPlayer mutation surface and eliminates the current clean separation where only the
  active player is ever mutated during a crossfade.
- **Prewarm latency risk**: Calling `setMediaItems()` on the standby during `prewarmStandby()`
  restarts the standby's decoder (inaudible at volume=0 but consumes buffer time). The
  prewarm lead time is approximately 1.5 s. On slow storage, the decoder restart and
  rebuffer may not complete before the actual crossfade begins, reducing crossfade
  readiness.
- **Mutation case not fully eliminated**: Even with full-queue preloading at prewarm time
  (narrowing the window to 1.5 s), mutations during that window still cause divergence,
  requiring a fallback `rebuildPlayerQueue()` that reintroduces the original problem.

**Why it was rejected:**  
The synchronisation complexity is disproportionate to the benefit. Option B eliminates the
dropout in all cases without touching the preload/prewarm architecture or the mutation
propagation model.

---

### Option D — Delay rebuild

**Description:**  
Defer `rebuildPlayerQueue()` until a safe point where the renderer is already idle: the
next user-initiated pause, or the next natural track transition.

**Advantages:**
- No `setMediaItems()` call on the promoted player immediately after promotion.
- Dropout eliminated for the first few seconds of the promoted track.

**Disadvantages:**
- **Immediate correctness regression**: After promotion, the promoted player has exactly one
  `MediaItem`. Calling `skipNext()` on a player with one item has no next item to seek to
  and silently fails. `insertNext()` inserts at ExoPlayer index 1, not the correct position
  relative to the full queue. Every queue-dependent operation is broken until the deferred
  rebuild fires.
- **No viable deferral point**: A user pause is not guaranteed to occur before the next skip.
  A natural track transition moves to the next item in the (wrong) single-item queue, which
  loops the current track rather than advancing.
- **Not self-contained**: This approach requires simultaneously preloading the full queue
  into the standby (Option C) to provide the skip target before the rebuild fires, which
  inherits all of Option C's problems on top of its own.

**Why it was rejected:**  
Deferring the rebuild without first ensuring the promoted player has a valid queue produces
immediate, observable playback failures. The approach is not viable without Option C, which
itself is rejected.

---

## Final Recommendation

**Option B — incremental queue rebuild using `addMediaItems()` — is the recommended
implementation.**

It satisfies every criterion:

| Criterion | Option A | Option B | Option C | Option D |
|---|---|---|---|---|
| Eliminates dropout unconditionally | No | **Yes** | Partial | No |
| Preserves dual-player architecture | Yes | **Yes** | No | No |
| Requires standby/full-queue sync | No | **No** | Yes | Yes |
| `QueueManager.queue` single source of truth | Yes | **Yes** | No | No |
| Handles queue mutations during crossfade | No | **Yes** | No | No |
| Implementation scope | Minimal | **Minimal** | Large | Medium |
| Memory impact | None | **Negligible** | Negligible | None |
| Risk | Low | **Low** | Moderate | High |

Option B is the preferred implementation unless future runtime evidence reveals an
ExoPlayer behaviour where `addMediaItems()` on a playing player does trigger renderer
disables under conditions not covered by the analysis above (e.g., a format change
required by a newly inserted adjacent item causing gapless lookahead to fail). If such
evidence appears, Option A should be deployed as an immediate stopgap while the new
evidence is analysed.

**No production code has been modified as of this document.** This document records the
design decision. The implementation of Option B is a separate commit.
