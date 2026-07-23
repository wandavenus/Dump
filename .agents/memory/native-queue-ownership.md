---
name: Native-First Queue Ownership
description: Architecture where Media3PlaybackService owns queue, shuffle, repeat; Dart is a pure EventChannel consumer.
---

# Native-First Queue Ownership

## The Rule
Native (Media3PlaybackService.kt) owns and is the single source of truth for:
- Queue contents and order
- Shuffle mode (ExoPlayer `shuffleModeEnabled`)
- Repeat mode (ExoPlayer REPEAT_MODE_*)
- Sleep timer
- Current index
- Crossfade

Dart owns nothing about queue/playback state. It builds `AudioPlaybackState` exclusively from EventChannel streams.

**Why:** Dart's shuffle order was a separate list that diverged from native's ExoPlayer queue. Notification Skip Next used ExoPlayer's `seekToNextMediaItem()`, which ignored Dart's shuffle order. Queue mutations (add/reorder) only updated Dart's `_playlist` without telling ExoPlayer. This caused constant sync drift.

## How to Apply
- Queue mutations (insertNext, appendToQueue, removeFromQueue, reorderQueue) → `Media3PlaybackBridge` → native MethodChannel → ExoPlayer mutates its queue → emits `queueStream` → Dart updates
- Skip next/prev → straight `Media3PlaybackBridge.skipNext/skipPrevious()` → ExoPlayer advances (respects shuffle order natively)
- Shuffle toggle → `Media3PlaybackBridge.setShuffleMode(bool)` → native sets `player.shuffleModeEnabled`
- Repeat toggle → `Media3PlaybackBridge.setRepeatMode(String)` → native sets `player.repeatMode`
- UI reads state exclusively from: playbackStateStream, positionStream, durationStream, currentTrackStream, queueStream, shuffleModeStream, repeatModeStream, sleepTimerStream

## EventChannel Names
All under prefix `musicplayer/media3_`:
- `playbackState`, `position`, `duration`, `currentTrack`, `queue`, `bufferingState`, `audioSessionId`
- `shuffleMode` (bool), `repeatMode` (String: "off"/"one"/"all"), `sleepTimer` (Map)
