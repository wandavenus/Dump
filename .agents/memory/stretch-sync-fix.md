---
name: Signalsmith Stretch ↔ Media3 timeline synchronization fix
description: Root cause + fix for currentPositionUs drift and READY↔BUFFERING oscillation when Signalsmith runs at speed ≠ 1.0
---

## Rule
Any AudioProcessor that changes output frame count MUST contribute to `audioProcessorChain.getMediaDuration()`; without it DefaultAudioSink reports wrong `currentPositionUs` and triggers buffering oscillation at speed ≠ 1.0.

**Why:** `DefaultAudioSink.applyMediaPositionParameters()` (line 1689) calls `audioProcessorChain.getMediaDuration()`. `DefaultAudioProcessorChain.getMediaDuration()` (line 213) ONLY queries `sonicAudioProcessor`; custom processors in the vararg have no path into this.

**How to apply:** Subclass `DefaultAudioProcessorChain`, override `getMediaDuration()` to apply the stretch processor's I/O frame ratio before delegating to super (Sonic inactive → identity). Wire via `.setAudioProcessorChain()`.

## Status
Implemented, Flutter Analyze clean, **verified on real device (2026-07-15) — position reporting correct, no buffering oscillation at any speed setting.**

## Fix (implemented, Flutter Analyze clean)

### SignalsmithStretchAudioProcessor.kt
- `totalInputFrames` / `totalOutputFrames` (plain Long, audio-thread-only), incremented in `queueInput()` for both fast path (1:1) and stretch path.
- Reset to 0 in `onFlush()` and `onReset()`.
- `fun getMediaDuration(playoutDurationUs)`: `Util.scaleLargeTimestamp(playoutDurationUs, totalInputFrames, totalOutputFrames)` when `totalOutputFrames >= 512`; falls back to `playoutDurationUs × speed` below threshold.
- Override `getDurationAfterProcessorApplied(durationUs)` → `(durationUs / speed).toLong()` — seek-time only, counters are 0 after flush so uses nominal speed.

### StretchAwareAudioProcessorChain.kt (new file)
- Extends `DefaultAudioSink.DefaultAudioProcessorChain`.
- Overrides `getMediaDuration(playoutDuration)`: `stretchProcessor.getMediaDuration(playoutDuration)` → `super.getMediaDuration(corrected)`.

### Media3PlaybackService.kt
- `createConfiguredPlayer()`: replaced `DefaultAudioSink.DefaultAudioProcessorChain(...)` with `StretchAwareAudioProcessorChain(stretchProc, toFloatProc, nativeDspProc, channelMixingProc, stretchProc, toInt16Proc)`.

## Why simpler fixes don't work
- `getDurationAfterProcessorApplied` alone: seek-time only, not real-time getCurrentPositionUs path.
- `player.playbackParameters.speed = stretchSpeed`: activates Sonic on already-stretched audio → double stretch.
- Flutter-side offset: does not fix `hasAudioOutputPendingData()` native buffering oscillation.

## Pitch independence
Pitch-shift alone (speed=1.0, semitones≠0): no frame-count change → ratio 1:1 → getMediaDuration is identity → no correction. Correct by design.
