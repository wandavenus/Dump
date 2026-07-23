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
