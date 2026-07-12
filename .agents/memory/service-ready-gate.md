---
name: Native service readiness gate for cold-start MethodChannel races
description: Why a fresh install hits a one-time PlatformException(not_ready) on the Media3 bridge, and the pattern used to fix it for real.
---

`Media3PlaybackService` is only created on-demand by the native `needsService`
allowlist ("play"/"setQueue") — it must NOT be force-started for other calls,
because a service with no queue has no path to `startForeground()` and Android
kills it deterministically (RemoteServiceException) if that deadline is missed.

Because of that, any Dart startup step that unconditionally pushes settings
into the native engine (bass boost, virtualizer, EQ, crossfade, skip-silence,
stereo-widening — anything fired from a `services/*.init()` at app boot) is
racing `Media3PlaybackService.onCreate()`. On a genuine fresh install nothing
has ever called "play" yet, so `instance` is null and the generic `_invoke`
retry/backoff in `Media3PlaybackBridge` (~3s total) eventually exhausts and
rethrows `PlatformException(not_ready)` — exactly once, because every later
launch finds the service (or a persisted queue restore) already warm.

**Why:** the correct fix is not a longer retry window or a caught/ignored
exception — those mask the ordering bug instead of removing it, and a longer
window can still lose the race on a slower cold start.

**How to apply:** use a genuine one-shot readiness signal instead:
- Native: `ServiceReadyGate` (in `events/EventEmitter.kt`) holds a `ready`
  flag + a single `EventChannel.EventSink`. `markReady()` is called once, at
  the very end of `Media3PlaybackService.onCreate()` (after every manager,
  including `TransportCommands`, is wired). `reset()` runs in `onDestroy()`.
  Its `onListen()` replays `true` immediately to a listener that subscribes
  after the service already became ready (e.g. Dart reattaching while the
  service process survived) — a plain broadcast emit would miss that case.
- Bridge: `Media3PlaybackBridge.serviceReadyStream` wraps the
  `musicplayer/media3_serviceReady` EventChannel; `PlaybackManager.waitForServiceReady()`
  exposes `.first` on it.
- Dart callers that must configure the engine before any transport command
  (`AudioEffectsService.applyAll()`, `MediaCapabilitiesService._applyAll()`)
  `await PlaybackManager.waitForServiceReady()` before firing their pushes,
  instead of firing immediately at Dart-process startup.
- This pattern generalizes: any *new* Dart init step that must reach the
  Media3 native service before the user has triggered playback should await
  `waitForServiceReady()` first, not rely on the generic `not_ready` retry.
