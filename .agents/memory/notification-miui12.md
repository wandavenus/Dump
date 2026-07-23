---
name: Notification MIUI12 fix
description: startForeground() must be called exactly once per service lifecycle; subsequent updates use NotificationManager.notify().
---

# Notification update — MIUI 12 / Android 11 fix

## The Rule
`startForeground()` must be called **exactly once** per service lifecycle.
Repeated calls to `startForeground()` cause issues on MIUI 12 and Android 11 (ANR-style delays, notification flicker, foreground state corruption).

**Why:** `startForeground()` transitions the service into foreground state AND attaches the notification. Calling it again to "refresh" the notification is wrong — the correct API for subsequent updates is `NotificationManager.notify(NOTIFICATION_ID, notification)`.

## How to Apply
- `ensureMediaForeground()` is the **only** place that calls `startForeground()`. It has a `isForeground` guard.
- `refreshNotification()` checks `isForeground`:
  - If `!isForeground` → calls `startForeground()` and sets `isForeground = true`
  - If `isForeground` → calls `getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification)`
- `isForeground` is reset to `false` only in `onDestroy()` and explicit `stopForeground()` calls.

## Code location
`Media3PlaybackService.refreshNotification()` — the guard is the `if (!isForeground)` block near the `builder.build()` call.
