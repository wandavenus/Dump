---
name: Queue persistence
description: ExoPlayer queue + position saved to SharedPreferences on every mutation; restored on service onCreate() without autoplay.
---

# Queue Persistence

## The Rule
Every queue mutation saves the full queue, current index, position, repeat mode, and shuffle state to SharedPreferences. On `onCreate()`, the queue is restored so the user's music session survives app restarts.

**Why:** Without persistence, the queue is lost after app restart even though background playback continues. Users expect to reopen the app and see their queue + position restored.

## SharedPreferences
- `PREFS_NAME = "media3_queue_prefs"`
- `KEY_QUEUE = "queue_json"` — JSONArray of song maps
- `KEY_INDEX = "queue_index"` — current track index (int)
- `KEY_POS_MS = "position_ms"` — position in ms (long)
- `KEY_REPEAT_MODE = "repeat_mode"` — Player.REPEAT_MODE_* int
- `KEY_SHUFFLE = "shuffle_enabled"` — boolean

## How to Apply
- `saveQueueToPrefs()` — call after every queue mutation (setQueue, insertNext, appendToQueue, removeFromQueue, reorderQueue, setRepeatMode, setShuffleMode, onMediaItemTransition)
- `restoreQueueFromPrefs()` — called once in `onCreate()` after player is ready; calls `player.prepare()` but NOT `player.play()` (paused restore)
- Serialization uses `org.json.JSONArray` + `org.json.JSONObject` (Android SDK built-in, no external dependency)
- Song maps contain: id, title, artist, album, albumId, path, duration

## Caveats
- Crossfade: uses `activeQueueIndex` (not `player.currentMediaItemIndex`) for the saved index since during promotion the active player may only have 1 item
- Empty queue is not saved (early return guard in `saveQueueToPrefs()`)
