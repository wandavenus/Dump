---
name: Dual-Player Architecture
description: Callback pattern used to break AudioEngine↔DualPlayerManager circular dependency; promotion flow; crossfade tick approach.
---

# Dual-Player Architecture (Phase 1–3)

## Rule: DualPlayerManager must NOT import AudioEngine
DualPlayerManager and AudioEngine would form a circular import if both imported each other.
DualPlayerManager exposes three static callbacks instead of calling AudioEngine directly:

```dart
static void Function()?           onPrimaryChanged;     // AudioEngine registers
static void Function(int)?        onSecondarySessionId; // AudioEngine registers
static void Function(bool)?       onPromoted;           // AudioService registers
```

AudioEngine.initialize() sets both its callbacks BEFORE calling DualPlayerManager.initialize().

**Why:** Dart does not allow circular imports between non-part files. The callback pattern is the clean solution.

**How to apply:** Any future code that needs DualPlayerManager to call into AudioEngine must go through a callback, not a direct import.

---

## Promotion flow

```
DualPlayerManager.promote(fromCrossfade)
  └─ onPrimaryChanged()         → AudioEngine._onPrimaryChanged()
       ├─ _player = DualPlayerManager.primaryPlayer
       ├─ _equalizer = DualPlayerManager.primaryEqualizer
       └─ re-subscribe _sessionSub to new primary's androidAudioSessionIdStream
  └─ onPromoted(fromCrossfade)  → AudioService._afterPromotion(fromCrossfade)
       ├─ advance _currentIndex via _nextIndexValue (computed BEFORE assignment)
       ├─ update playbackState (currentSong, currentIndex)
       ├─ _resubscribeToPrimaryStreams()
       ├─ if !fromCrossfade: primaryPlayer.play()  (gapless path — secondary was paused)
       ├─ AudioEffectsService.applyAll()           (immediate)
       ├─ Future.delayed(350ms, applyAll)           (native effects session race)
       └─ _schedulePreload()                        (preload track-after-next)
```

**Why:** Secondary player was pre-loaded (paused) for gapless, already playing for crossfade — hence the `fromCrossfade` flag distinguishes whether `play()` is needed.

---

## CrossfadeController tick (20 ms)

- Pure static tick with a `Timer.periodic(20ms)`.
- `updateContext(nextIsGapless, loopOne)` called by AudioService._schedulePreload every preload so controller has up-to-date context.
- Skips crossfade when `loopOne || nextIsGapless`.
- On fade complete: calls `DualPlayerManager.promote(fromCrossfade: true)`.
- `reset()` is public — called by AudioService on manual skips to abort in-flight crossfade.

---

## applyAll() called twice after promotion
After each `promote()`, `AudioEffectsService.applyAll()` is called immediately AND after a 350 ms delay. The delay is intentional — it gives the new audio session time to fire `androidAudioSessionIdStream`, which triggers `_attachNativeEffects` (BassBoost/Reverb/Spatial session setup), after which a second `applyAll()` sets their strength values.

**Why:** Without the delay, `_attachNativeEffects` hasn't fired yet for the new session, so native effects aren't attached when the first `applyAll()` runs.
