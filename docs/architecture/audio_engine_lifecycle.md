# Audio Engine — Dual-Player Lifecycle (Phase 1–3)

## Architecture Overview

```
main.dart
  └─ AudioEngine.initialize()
       └─ DualPlayerManager.initialize()
            ├─ creates PRIMARY player (+ Android DSP pipeline if Android)
            ├─ calls AudioEngine.setActivePlayer(primary, eq, le)
            └─ creates SECONDARY player in background (fire-and-forget)
```

### Component Responsibilities

| Component | Responsibility |
|---|---|
| `DualPlayerManager` | Owns both `AudioPlayer` instances. Handles create / preload / promote / dispose. |
| `AudioEngine` | Facade: stores active player reference, owns native-effect channel, attaches DSP to each new audio session. |
| `AudioService` | Manual queue management (`_playlist`, `_currentIndex`, shuffle, loop). Subscribes to primary player streams; re-subscribes after every promotion. |
| `CrossfadeController` | 20 ms tick: monitors primary position, starts secondary, fades both players, triggers promotion. |
| `GaplessAlbumDetector` | Pure utility: returns `true` when two songs share album + artist (same album → skip crossfade). |

---

## Player Lifecycle

### 1. Cold Start (`playSongAt`)

```
playSongAt(playlist, index)
  ├─ CrossfadeController.reset()           // abort any prior crossfade
  ├─ primary.setAudioSource(taggedSource)  // MediaItem → lock-screen notification
  ├─ primary.play()
  └─ _schedulePreload()
       ├─ GaplessAlbumDetector.isGapless(current, next) → context for CrossfadeController
       └─ DualPlayerManager.preloadTrack(nextSong)
            └─ secondary.setAudioSource(untaggedSource)
```

The secondary player uses an **untagged** `AudioSource` (no `MediaItem`) so the lock-screen notification is not disturbed during preloading.

---

### 2. Gapless Transition (no crossfade configured, or same-album)

```
primary.processingState == ProcessingState.completed
  └─ AudioService._onTrackCompleted()
       ├─ CrossfadeController.isFading == false → proceed
       └─ _gaplessPromoteAndPlay()
            └─ DualPlayerManager.promote(fromCrossfade: false)
                 ├─ _primary  ← old _secondary  (already buffered → zero gap)
                 ├─ AudioEngine.setActivePlayer(newPrimary, eq, le)
                 ├─ onPromoted(false) → AudioService._afterPromotion(false)
                 │    ├─ _currentIndex++
                 │    ├─ _resubscribeToPrimaryStreams()
                 │    ├─ DualPlayerManager.primaryPlayer.play()
                 │    ├─ AudioEffectsService.applyAll()
                 │    └─ _schedulePreload()
                 ├─ _disposePlayer(oldPrimary)   // async, no await
                 └─ _initSecondary()             // creates a fresh secondary
```

Because the secondary player already has the next track **fully buffered** in memory, `play()` starts instantly with no decoder-init gap.

---

### 3. Crossfade Transition

```
CrossfadeController._onTick()  (every 20 ms)
  ├─ remaining ≤ crossfadeMs AND secondary != null
  │    ├─ secondary.setVolume(0); secondary.play()
  │    └─ _isFading = true
  │
  └─ _isFading == true
       ├─ fadeRatio = elapsed / crossfadeMs  (clamped 0..1)
       ├─ primary.setVolume(_easeInQuad(1 - fadeRatio))   // 1 → 0
       ├─ secondary.setVolume(_easeOutQuad(fadeRatio))    // 0 → 1
       └─ fadeRatio >= 1.0 → _triggerPromotion()
            └─ DualPlayerManager.promote(fromCrossfade: true)
                 ├─ AudioEngine.setActivePlayer(newPrimary, eq, le)
                 ├─ onPromoted(true) → AudioService._afterPromotion(true)
                 │    ├─ _currentIndex++
                 │    ├─ _resubscribeToPrimaryStreams()
                 │    ├─ (no play() — secondary was already playing)
                 │    ├─ AudioEffectsService.applyAll()
                 │    └─ _schedulePreload()
                 ├─ _disposePlayer(oldPrimary)
                 └─ _initSecondary()
```

Easing curves:
- **Primary (fade-out)**: `easeInQuad(1 - t)` — slow start, fast end → sounds natural
- **Secondary (fade-in)**: `easeOutQuad(t)` — fast start, slow end → balanced mix

---

## Crossfade Skip Conditions

Crossfade is automatically suppressed when:

| Condition | Reason |
|---|---|
| `GaplessAlbumDetector.isGapless(a, b)` | Same album + artist → live/DJ content should not be interrupted |
| `LoopMode.one` active | Looping the same track — no sense in crossfading with itself |
| `secondaryPlayer == null` | Secondary wasn't ready in time; gapless promotion is used instead |
| `crossfadeDuration == 0` | User disabled crossfade |

---

## DSP / Effects on Promotion

After `promote()`:

1. `AudioEngine.setActivePlayer(newPrimary, eq, le)` — updates `_player`, `_equalizer`, `_loudnessEnhancer`.
2. `AudioEffectsService.applyAll()` — re-applies EQ band gains, pitch, speed (uses the new references).
3. After 350 ms delay: `applyAll()` again — gives the new audio session time to fire its `androidAudioSessionIdStream`, triggering `_attachNativeEffects` (BassBoost, Reverb, Spatial), after which a second `applyAll()` ensures their strength values are set.

> **Media3 migration note**: The native `MediaSessionService` is now responsible for lock-screen metadata, queue state, and transport controls via platform channels.

---

## Interruption Handling

`AudioSessionHandler` handles phone calls and headphone unplugs:

- **On pause/noisy**: pauses primary + secondary, calls `CrossfadeController.reset()` to abort crossfade cleanly.
- **On duck**: sets primary + secondary to 0.3 volume.
- **On unduck**: restores primary to 1.0, secondary to 0.0 (preloading, not playing).
- **On resume**: plays primary only (secondary is in preload state).

---

## Initialization Order (main.dart)

```
ThemeController.init()
LogService.init()
LyricsSettings.init()
AudioEngine.initialize()         ← DualPlayerManager.initialize() called here
  AudioEffectsService.init()
AudioService.initialize()
AudioFocusService.initialize()
```

> `AudioEffectsService.init()` must run AFTER `AudioEngine.initialize()` because it reads the equalizer / loudness-enhancer references populated by `DualPlayerManager`.
