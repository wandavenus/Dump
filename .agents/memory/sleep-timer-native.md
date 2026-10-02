---
name: Sleep timer native
description: Sleep timer runs natively in Media3PlaybackService.kt Handler; SleepTimerService.dart is a thin delegate.
---

# Native Sleep Timer Architecture

## The Rule
Sleep timer logic runs entirely in `Media3PlaybackService.kt` using Android `Handler.postDelayed()`.
The Dart `SleepTimerService` is a thin adapter that delegates to native and mirrors the native `sleepTimerStream` into `ValueNotifier<bool> isActive` and `ValueNotifier<Duration?> remaining` for UI.

**Why:** Dart Timer fires unreliably when the app is backgrounded (Dart VM may be paused). A native Handler fires reliably even in background, keeping playback pausing accurate.

## How to Apply
- `SleepTimerService.startDuration(duration)` → calls `Media3PlaybackBridge.setSleepTimer(ms)`
- `SleepTimerService.startEndOfSong()` → calls `Media3PlaybackBridge.setSleepTimerEndOfSong()`
- `SleepTimerService.cancel()` → calls `Media3PlaybackBridge.cancelSleepTimer()`
- `SleepTimerService.initialize()` must be called in `main()` AFTER `AudioService.initialize()` to subscribe to `sleepTimerStream`
- `AudioPlaybackState` also has `sleepTimerActive` (bool) and `sleepTimerRemainingMs` (int) fields updated by AudioService's subscription to the same stream

## Native MethodChannel methods
- `setSleepTimer({durationMs: int})` — duration mode
- `setSleepTimerEndOfSong` — end-of-song mode (pauses at onMediaItemTransition REASON_AUTO)
- `cancelSleepTimer` — cancel and reset

## Two cancel variants (don't collapse them)
- `SleepTimerManager.cancel()` — logs a `[VRB] "cancelSleepTimer called but no active timer or fade"` line when nothing is armed. Reserved for the **user-initiated** `cancelSleepTimer` MethodChannel call, where hitting the no-op branch is a genuine Dart/native mirror desync worth surfacing.
- `SleepTimerManager.cancelIfActive()` — same semantics, silent when nothing is armed. Used by the **session-reset** callers that must cancel unconditionally so a timer can never survive a queue change: `setQueue`, `setTrack`, `stop`, `skipNext`, `skipPrevious`, `setTrackNative` (Android Auto/AVRCP), the notification `ACTION_STOP`, and the `ServiceShutdownCoordinator` shutdown lambda.

**Why:** those reset callers run on ordinary actions (every song tap is a `setQueue`), so the unguarded `cancel()` spammed the log on every tap / skip / service destroy even when the Sleep Timer was never used.

## End-of-song behavior
Native checks in `onMediaItemTransition(reason=MEDIA_ITEM_TRANSITION_REASON_AUTO)`: if `sleepEndOfSong && sleepTimerActive`, posts `triggerSleepStop()` on Handler. Also checked in `onPlaybackStateChanged(STATE_ENDED)` for the last track case.
