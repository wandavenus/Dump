---
name: Media3PlaybackService startForeground() deadline
description: Why calling pause/stop/seek/skip on a never-started Media3 service reliably crashes with RemoteServiceException, and how needsService should be scoped.
---

`Media3PlaybackService.onCreate()` never calls `startForeground()` itself. That
call only happens via `PlaybackNotificationManager.ensureMediaForeground()`,
triggered either by a genuine `play` transport command reaching a live
instance, or by `onStartCommand()`'s fallback branch — which is gated on
`mediaItemCount > 0`.

If the native MethodChannel handler's `needsService` set includes methods like
`pause`/`stop`/`seek`/`setTrack`/`skipNext`/`skipPrevious`, calling any of them
while `Media3PlaybackService.instance == null` will call
`ContextCompat.startForegroundService()` to spin the service up — but if there
is no persisted queue (e.g. fresh install, or the engine was never actually
used), `mediaItemCount` stays 0 and nothing ever calls `startForeground()`.
Android then kills the app with
`RemoteServiceException: ... did not then call Service.startForeground()`.
This is deterministic, not a race — it reproduces every time on an empty
queue regardless of device speed.

**Why:** you cannot meaningfully pause/stop/seek/skip a service that was never
started — there is nothing to act on. Only `play` (resume from persisted
queue) and `setQueue` (start a new queue) are legitimate reasons to wake the
service from cold.

**How to apply:** any MethodChannel/engine bridge that lazily starts a
platform service must scope its "needs service" allowlist to only the methods
that genuinely establish new state (queue-setting / resume), mirroring what
the MediaKit channel in this app already does (`updateMetadata`,
`updatePlaybackState`, `release` — no pause/stop/seek/skip). If you add a new
transport method, don't add it to that set unless it can independently
guarantee a call to `ensureMediaForeground()`/`startForeground()` on the path
it takes when the service is cold-started with an empty queue.
