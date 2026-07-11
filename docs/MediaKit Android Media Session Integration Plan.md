MediaKit Android Media Session Integration Plan

Objective

Create a production-grade Android media integration for the MediaKit engine so that both playback engines provide the same Android user experience.

The goal is feature parity, not code duplication.

When MediaKit is the active engine, Android should behave exactly as it does with Media3:

- playback notification
- lock screen controls
- Bluetooth/headset controls
- Android Auto compatibility (where possible)
- media button events
- foreground service lifecycle
- proper audio focus ownership

The existing engine abstraction ("AbstractAudioEngine" + "AudioEngineManager") must remain unchanged.

---

Current Architecture

Flutter UI
        │
        ▼
AudioService
        │
        ▼
AudioEngineManager
         │
  ┌─────┴──────┐
  │              │
 ▼               ▼
Media3Engine   MediaKitEngine
 │               │
 ▼               ▼
Media3          media_kit Player

Current Android ownership:

Media3Engine
        │
        ▼
Media3PlaybackService
        │
        ├── MediaSession
        ├── Foreground Service
        ├── Notification
        ├── Audio Focus
        └── ExoPlayer

MediaKit currently owns only:

MediaKitEngine
        │
        ▼
media_kit Player

No Android media infrastructure exists.

---

Architectural Goal

The architecture should become symmetrical.

                    AudioEngineManager
                    /               \
                   /                 \
          Media3Engine         MediaKitEngine
                │                    │
                ▼                    ▼
     Media3PlaybackService   MediaKitPlaybackService
                │                    │
                ▼                    ▼
          MediaSession         MediaSession
          Notification         Notification
          ForegroundSvc        ForegroundSvc
          AudioFocus           AudioFocus

Each engine owns its own Android lifecycle.

Neither engine should depend on the other's service.

---

Non-Goals

Do NOT:

- keep Media3PlaybackService alive while MediaKit is active
- proxy MediaKit through Media3
- duplicate the existing PlaybackNotificationManager
- introduce compatibility hacks
- weaken engine isolation

---

Design Principles

1. Engine Isolation

Media3 resources must not exist while MediaKit is active.

MediaKit resources must not exist while Media3 is active.

Exactly one Android playback service should exist at any time.

---

2. Shared Components

Reuse existing Android components whenever possible.

Examples:

- PlaybackNotificationManager
- artwork loading
- notification actions
- metadata formatting
- notification channel
- utility classes

Avoid creating MediaKit-specific copies unless technically required.

---

3. Notification Ownership

Notification ownership belongs to the currently active engine.

Media3 owns notification while Media3 is active.

MediaKit owns notification while MediaKit is active.

Switching engines transfers ownership.

---

Proposed Android Components

Create:

MediaKitPlaybackService.kt

Responsibilities:

- Foreground Service
- MediaSession
- Notification lifecycle
- Audio focus
- Media button handling
- Lock screen metadata
- Communication with Flutter

---

Create:

MediaKitTransportBridge.kt

Responsibilities:

- receive MethodChannel commands
- translate to media_kit Player
- expose state updates
- expose metadata
- expose playback position

---

Create:

MediaKitSessionCallback.kt

Responsibilities:

- play
- pause
- seek
- next
- previous
- stop

---

Notification Layer

PlaybackNotificationManager should become engine-agnostic.

Avoid:

Media3PlaybackNotificationManager
MediaKitPlaybackNotificationManager

Preferred:

PlaybackNotificationManager
                ▲
        accepts MediaSession

The notification renderer should not know which engine is producing playback.

---

Engine Switching

Current:

Media3
↓

release()

↓

MediaKit

Target:

Media3
↓

release()

↓

Media3 service destroyed

↓

MediaKit service starts

↓

MediaSession created

↓

Notification posted

↓

Foreground service active

↓

Playback resumes

Reverse direction:

MediaKit
↓

release()

↓

MediaKit service destroyed

↓

Media3 service starts

↓

Playback restored

---

MethodChannel Changes

Expose MediaKit lifecycle operations separately from Media3.

Avoid sharing native state between services.

Both services should implement equivalent lifecycle semantics:

- initialize
- play
- pause
- seek
- stop
- release

---

Verification Checklist

After implementation verify:

Engine lifecycle

- Media3 → MediaKit
- MediaKit → Media3

Notification

- appears correctly
- updates metadata
- artwork updates
- progress updates
- disappears on release

Lock Screen

- title
- artist
- artwork
- controls

Bluetooth

- play
- pause
- next
- previous

Headset

- media button
- unplug handling

Audio Focus

- request
- abandon
- interruption recovery

Foreground Service

Exactly one foreground service active.

No duplicate notifications.

No orphan MediaSession.

---

Success Criteria

The migration is complete only when:

- MediaKit provides the same Android media experience as Media3.
- Engine switching is transparent to the user.
- Notification ownership cleanly transfers between engines.
- No Media3 service remains alive while MediaKit is active.
- No duplicate foreground services exist.
- Existing abstraction layers remain unchanged.
- PlaybackNotificationManager remains reusable and engine-agnostic.

At that point, the hybrid audio architecture will provide two independent playback engines with equivalent Android integration while preserving clean ownership boundaries and long-term maintainability.
