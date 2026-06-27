---
name: MediaKit Android Media Session Integration
description: Architecture of MediaKitPlaybackService and the engine-agnostic PlaybackNotificationManager refactor.
---

## Key architectural decisions

### PlaybackNotificationManager is now engine-agnostic
- Constructor changed: `service: MediaSessionService` → `service: Service`, `getPlayer: () -> ExoPlayer?` → `getIsPlaying: () -> Boolean`, added `serviceClass: Class<*>` param (defaults to `Media3PlaybackService::class.java`).
- Both `Media3PlaybackService` and `MediaKitPlaybackService` pass their own class as `serviceClass` so PendingIntent transport buttons target the correct service.
- **Why:** avoids duplicate notification code; both engines share the same professional-grade notification with async artwork loading, generation counter, and LRU cache.

### MediaKitPlaybackService does NOT produce audio
- It is a thin mirror service: holds a `MediaSession` backed by `MediaKitStatePlayer` (SimpleBasePlayer), owns `PlaybackNotificationManager`, and manages audio focus.
- All actual audio comes from Dart's `media_kit Player`.
- **Why:** media_kit is a Dart/C++ player — there is no Java/Kotlin audio pipeline to hook into.

### Transport command flow
```
Lock screen / BT / notification button
  → onStartCommand (ACTION_*) or SimpleBasePlayer.handleSetPlayWhenReady / handleSeek
  → MediaKitEventEmitter.emitTransport(action, positionMs?)
  → EventChannel "musicplayer/mediakit_transport"
  → MediaKitServiceBridge._transportHandler
  → MediaKitEngine._handleTransportCommand
  → _player.play() / pause() / next() / previous() / seek()
```

### Metadata push flow (Dart → Native)
```
MediaKitEngine._subscribeToPlayer: p.stream.playlist.listen(...)
  → MediaKitServiceBridge.updateMetadata(title, artist, artworkUri, durationMs)
  → MethodChannel "musicplayer/mediakit_service" "updateMetadata"
  → MediaKitPlaybackService.handle()
  → statePlayer.updateMetadata() → invalidateState()
  → MediaSession notified → notification refreshed
```

### Channel names
- `musicplayer/mediakit_service` — MethodChannel, Dart→Native (startService, updateMetadata, updatePlaybackState, release)
- `musicplayer/mediakit_transport` — EventChannel, Native→Dart (transport commands)

### AudioFocusManager NOT reused for MediaKit
- `AudioFocusManager` has ExoPlayer-specific `getPlayer: () -> ExoPlayer?` (used for volume duck, direct play/pause). Not viable for MediaKit.
- `MediaKitPlaybackService` has simple inline audio focus (API 26+ only since minSdk=29).
- **Why:** ExoPlayer calls can't be made for a Dart-side player; duplicating 20 lines is justified.

### onUpdateNotification() suppressed
- `MediaKitPlaybackService` overrides `onUpdateNotification()` with empty body — same as `Media3PlaybackService`.
- **Why:** Media3 1.3+ auto-manages notifications via DefaultMediaNotificationProvider which conflicts with our PlaybackNotificationManager.

### Service lifecycle
- Started when `MediaKitEngine.initialize()` is called → `MediaKitServiceBridge.startService()`.
- Stopped when `MediaKitEngine.dispose()` → `MediaKitServiceBridge.stopService()` → native "release" → `stopSelf()`.
- `startForeground()` is called immediately in `onCreate()` to avoid Android's 5 s foreground service timeout.
