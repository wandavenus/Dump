---
name: Media3 transport controls
description: How notification buttons, Bluetooth/headset, and state restoration work after the just_audio/audio_service removal.
---

# Media3 Transport Controls & Migration

## Rule
Notification transport buttons (Prev/Play-Pause/Next) require explicit `addAction()` calls
**and** `MediaStyleNotificationHelper.MediaStyle(sess).setShowActionsInCompactView(0, 1, 2)`.
Media3's `MediaSession` alone does NOT inject these into a custom-built notification.

**Why:** We build our own `NotificationCompat` notification (not using `DefaultMediaNotificationProvider`)
to support MIUI where the OS timer fires before a MediaController connects. Custom notification = must
add actions manually.

## How to apply
- Three `PendingIntent`s use `buildTransportPendingIntent(ACTION_*, requestCode)` helper in
  `Media3PlaybackService`
- On API ≥ 26 uses `PendingIntent.getForegroundService()`; older uses `getService()`
- `onStartCommand` has a `when (intent?.action)` branch for each action constant
- Action constants: `ACTION_PLAY_PAUSE`, `ACTION_SKIP_NEXT`, `ACTION_SKIP_PREV` in companion object

## Bluetooth / headset media buttons
- Media3 `MediaSession` handles `KeyEvent.KEYCODE_MEDIA_*` automatically via the session token
- `android.intent.action.MEDIA_BUTTON` intent-filter added to service in manifest for older BT stacks
- No custom `MediaSession.Callback` needed — ExoPlayer's default command set covers all transport ops

## State restoration after process kill
- `android:stopWithTask="false"` in manifest + `START_STICKY` keep service alive
- `onTaskRemoved()` logs but does NOT call `stopSelf()`
- `AudioService.syncFromNative()` polls `getPlaybackSnapshot()` MethodChannel on cold start
  (called from `lib/main/main.dart`) and on every `AppLifecycleState.resumed`
  (called from `lib/main/app_state.dart`)

## Packages removed
`just_audio: ^0.10.5` and `audio_service: ^0.18.18` had zero imports in lib/ — pure dead entries.
`BackgroundAudioHandler` kept as a no-op shim; its static callbacks remain wired for future use.

## Rapid skip guard (SKIP-01, 1.5.28)
- All next/prev entry points (Flutter UI `skipNext`/`skipPrevious` MethodChannel, notification
  `ACTION_SKIP_NEXT/PREV`, MediaSession/AVRCP via `ActivePlayerProxy.onSkipNext/onSkipPrev`)
  funnel through `TransportCommands.handleSkipNext`/`handleSkipPrevious` — the guard lives there,
  not in any individual caller.
- `SKIP_THROTTLE_MS = 500` (TransportCommands companion): a same-direction repeat inside the
  window is dropped (verbose log) BEFORE any side effect — sleep-timer cancel, crossfade cancel,
  standby rebuild, `preloadNextTrack(force)`, session-artwork replace, notification refresh.
  Direction switch (next → prev) is never throttled (undo gesture).
- `skipNextNative(force)` / `skipPrevNative(force)` bypass the guard. The stuck-playback watchdog
  (`transportState.onStuck` retry 2) calls `skipNextNative(force = true)` so a genuinely
  undecodable file always advances even right after a user skip. End-of-track auto-advance is
  internal to ExoPlayer and never routes through the guard.
