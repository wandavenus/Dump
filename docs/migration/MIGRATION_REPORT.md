# Media3 Native Migration Report

## Summary

Complete removal of `just_audio` / `audio_service` Dart runtime dependencies and full
activation of the native Android Media3 (`ExoPlayer` + `MediaSession`) pipeline.
All playback, notifications, transport controls, Bluetooth integration, and state
restoration now run natively on Android — no Dart audio plugins in the critical path.

---

## Changes Made

### 1. Removed Dart Plugin Dependencies (`pubspec.yaml`)

| Package | Version | Status |
|---|---|---|
| `just_audio` | `^0.10.5` | **Removed** |
| `audio_service` | `^0.18.18` | **Removed** |
| `audio_session` | `^0.2.3` | Kept (audio-focus helpers, no runtime dep) |

**Why it was safe:** `grep` of all `lib/` files confirmed zero `import 'package:just_audio'`
or `import 'package:audio_service'` anywhere. The entries were dead rollback comments.

---

### 2. Notification Transport Controls (`Media3PlaybackService.kt`)

**Problem:** `refreshNotification()` built a `MediaStyle` notification but called no
`addAction()` — so the lockscreen and Bluetooth head-unit showed no Previous / Play-Pause /
Next buttons.

**Fix:**
- Added three `NotificationCompat.Action` entries (Previous, Play/Pause, Next) to both
  `ensureMediaForeground()` (initial foreground notification) and `refreshNotification()`
  (every state change).
- Called `MediaStyleNotificationHelper.MediaStyle(sess).setShowActionsInCompactView(0, 1, 2)`
  so all three buttons appear in the collapsed notification AND on the lockscreen / car display.
- The small icon now switches between `ic_media_pause` and `ic_media_play` to reflect live state.
- **Artwork** is loaded in `refreshNotification()` via `ContentResolver` from the
  `content://media/external/audio/albumart/<albumId>` URI (malformed `-1`/`0` URIs are
  skipped with a verbose log).

---

### 3. Transport Button Handling (`onStartCommand`)

**Problem:** Notification action `PendingIntent`s had nowhere to land — `onStartCommand`
only called `ensureMediaForeground()` on every intent.

**Fix:** Added a `when (intent?.action)` branch in `onStartCommand`:

| Intent action | Result |
|---|---|
| `ACTION_PLAY_PAUSE` | Toggle play/pause; re-requests audio focus on play |
| `ACTION_SKIP_NEXT` | `player.seekToNextMediaItem()` |
| `ACTION_SKIP_PREV` | `player.seekToPreviousMediaItem()` |
| *(anything else)* | `ensureMediaForeground()` as before |

After each action: `emitAll()` + `refreshNotification()` so the Dart EventChannel
streams and the notification icon update immediately.

Added `buildTransportPendingIntent(action, requestCode)` helper that uses
`PendingIntent.getForegroundService()` on API ≥ 26 and falls back to
`PendingIntent.getService()` on older devices.

---

### 4. Bluetooth / Headset Media Button Handling (`AndroidManifest.xml`)

**Problem:** No `android.intent.action.MEDIA_BUTTON` intent-filter on the service.
Older Bluetooth profiles (A2DP sink, AVRCP) that broadcast raw media key events could
not reach the service.

**Fix:** Added a second `<intent-filter>` to `Media3PlaybackService` in the manifest:

```xml
<intent-filter>
    <action android:name="android.intent.action.MEDIA_BUTTON"/>
</intent-filter>
```

Media3's `MediaSession` already handles `KeyEvent.KEYCODE_MEDIA_*` natively when the
session token is registered; this intent-filter ensures compatibility with older Bluetooth
stacks that use the broadcast path rather than `AudioManager.dispatchMediaKeyEvent()`.

---

### 5. Foreground/Background Survival (`AndroidManifest.xml`)

**Problem:** `android:stopWithTask` was absent (defaults to `true` for non-started
services). The OS would stop the service when the user removed the app from recents.

**Fix:** Added `android:stopWithTask="false"` to the `<service>` declaration. Combined
with `START_STICKY` return from `onStartCommand`, the service survives task removal.

Added `onTaskRemoved()` override that logs the event and explicitly does **not** call
`stopSelf()` — this makes the survival intent clear and provides a log checkpoint.

---

### 6. State Restoration After App Kill

**Mechanism (already implemented, now documented):**

`AudioService.syncFromNative()` calls `Media3PlaybackBridge.getPlaybackSnapshot()` which
invokes the native `getPlaybackSnapshot` MethodChannel method. The native side returns
the full queue, current index, position, duration, and playback state from the live
ExoPlayer instance.

Call sites:
- `lib/main/main.dart` — once after `AudioEngine.initialize()` on every cold start.
- `lib/main/app_state.dart` — on every `AppLifecycleState.resumed` (foreground return,
  including after OS-kill + reopen).

This means state is restored within one event-loop tick of the Flutter engine starting,
before any EventChannel stream events arrive.

---

### 7. `BackgroundAudioHandler` — Dead Code Status

`BackgroundAudioHandler` is intentionally kept as a **no-op shim**:

```dart
void updateNowPlaying({...}) {}
void pushPlaybackState({...}) {}
```

All notification metadata and lockscreen state are owned by the native `Media3PlaybackService`
and its `MediaSession`. The shim prevents compile errors in `AudioService` call sites without
requiring a broad refactor of the service facade. The static callback fields
(`onPlayRequested`, `onPauseRequested`, etc.) remain wired and could be used if a Dart-side
notification handler is ever needed.

---

### 8. Native Logging

`nativeLog(level, msg)` already existed and emits to the `NativeLogs` EventChannel
(consumed by `LogService` on the Dart side). New log points added in this migration:

| Location | Log |
|---|---|
| `onStartCommand` — each transport action | `"transport: pause/play/skipNext/skipPrev (notification/BT button)"` |
| `onStartCommand` — focus denied | `"transport: play denied — audio focus not granted"` |
| `onTaskRemoved` | `"onTaskRemoved: app removed from recents — service continues in background"` |
| `refreshNotification` — artwork loaded | `"refreshNotification: artwork loaded for '<title>'"` |
| `refreshNotification` — artwork skip | `"refreshNotification: artwork load skipped — <reason>"` |
| `refreshNotification` — notify failure | `"refreshNotification: notify failed — <reason>"` |

All existing log points (onCreate, play, pause, seek, setQueue, audioSessionId,
attachEffects, onDestroy) remain unchanged.

---

## Architecture After Migration

```
Physical button / Bluetooth AVRCP
         │  KeyEvent (KEYCODE_MEDIA_*)
         ▼
  MediaSession (Media3) ──────────────────► ExoPlayer
         │                                        │
  Notification tap / swipe                 Player.Listener
         │  PendingIntent (ACTION_*)              │
         ▼                                        ▼
  onStartCommand ──► seekTo*/play/pause     emitAll()
                                               │
                            ┌──────────────────┤
                            ▼                  ▼
                    EventChannel         refreshNotification()
                    (Dart bridge)        (MediaStyle + 3 actions)
                            │
                    AudioPlayer shim
                            │
                    AudioService facade
                            │
                    Flutter UI
```

---

## Verification Checklist

- [x] `flutter analyze --no-pub` → 0 errors, 0 warnings
- [x] `just_audio` and `audio_service` removed from `pubspec.yaml`
- [x] Transport buttons (Prev / Play-Pause / Next) in notification (`addAction` × 3)
- [x] `setShowActionsInCompactView(0, 1, 2)` for lockscreen / Bluetooth display
- [x] `onStartCommand` handles `ACTION_PLAY_PAUSE`, `ACTION_SKIP_NEXT`, `ACTION_SKIP_PREV`
- [x] `android.intent.action.MEDIA_BUTTON` intent-filter added to manifest
- [x] `android:stopWithTask="false"` added to service declaration
- [x] `onTaskRemoved()` logs and does not stop the service
- [x] `syncFromNative()` called on cold start and on every `AppLifecycleState.resumed`
- [x] Artwork loaded in `refreshNotification()` with malformed-URI guard
- [x] All transport actions emit `nativeLog` entries

---

## Rollback Plan

If a regression is found on a specific device class:

1. Re-add `just_audio: ^0.10.5` and `audio_service: ^0.18.18` to `pubspec.yaml`.
2. Revert `BackgroundAudioHandler` no-ops back to real `audio_service` calls.
3. Revert the `android:stopWithTask` / intent-filter / action changes in the manifest.

The Dart-side architecture (`AudioService`, `Media3PlaybackBridge`, `DualPlayerManager`)
is decoupled from the plugin choice and requires no changes for rollback.
