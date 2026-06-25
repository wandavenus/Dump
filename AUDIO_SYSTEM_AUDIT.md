# COMPREHENSIVE AUDIO SYSTEM AUDIT REPORT

**Project:** musicplayer — Flutter + Android Media3 1.10.1  
**Device Target:** Xiaomi Mi 9T / K20 · Snapdragon 730 · MIUI 12.1.4 · Android 11  
**Audit Date:** June 25, 2026  
**Scope:** Media3 1.10.1, crossfade engine, queue management, audio focus, notifications, effects, state sync, memory leaks, race conditions, threading

---

## EXECUTIVE SUMMARY

The audio system is architecturally sound and considerably more mature than a typical hobby project. The native-first design, dual-player crossfade engine, and MIUI-specific workarounds are well-considered. However, **one critical bug** was discovered that renders all Bluetooth and OS transport controls broken after the first crossfade completes. Two additional high-severity bugs (audio focus not cancelling crossfade; missing player error callback) can cause silent audio leaks and unhandled crash states. Several medium and low severity issues round out the findings.

---

## SEVERITY SCALE

| Level | Meaning |
|---|---|
| **Critical** | Guaranteed production failure; incorrect behavior on every affected code path |
| **High** | Incorrect behavior in a common scenario; likely to be encountered by users |
| **Medium** | Incorrect behavior in a specific scenario; edge case but reproducible |
| **Low** | Minor correctness issue, performance concern, or technical debt |

---

## SUMMARY TABLE

| ID | Severity | System | Finding | Actual Bug? |
|---|---|---|---|---|
| CRIT-01 | **Critical** | MediaSession / Crossfade | ForwardingPlayer discarded after first crossfade; BT/OS controls bypass TransportCommands | Yes |
| HIGH-01 | **High** | Audio Focus / Crossfade | AUDIOFOCUS_LOSS during crossfade doesn't cancel old player | Yes |
| HIGH-02 | **High** | ExoPlayer Listener | No `onPlayerError()` override; playback failures are silent to Flutter | Yes |
| MED-01 | **Medium** | MediaSession / ForwardingPlayer | `seekTo()` discards `mediaItemIndex`; Android Auto/media browsing broken | Yes |
| MED-02 | **Medium** | Dart State Sync | Empty queue event not propagated; stale playlist persists | Yes |
| MED-03 | **Medium** | Dart State Sync | `nextIndex` is linear-only; wrong "up next" in shuffle mode | Yes |
| MED-04 | **Medium** | Queue / Crossfade | `rebuildPlayerQueue()` non-atomic two-step has narrow race window | Potential |
| MED-05 | **Medium** | Settings / Dead Code | Tunneling toggle is a complete no-op (API removed in Media3 1.4+) | Yes (dead feature) |
| MED-06 | **Medium** | Transport / Dart | `skipPrevious()` uses 200ms-stale Dart position for 3s boundary decision | Yes |
| LOW-01 | Low | Queue Persistence | `QueueSync.save()` spawns unbounded raw threads on every transition | Potential |
| LOW-02 | Low | Notification | `noArtworkUris` set grows without bound | Potential |
| LOW-03 | Low | Audio Effects | `isEffectTypeAvailable()` fallback probes global session (sessionId=0) | Yes |
| LOW-04 | Low | Notification | Artwork thread spawning unbounded on rapid skip | Potential |
| LOW-05 | Low | Dart UX | `playFromCurrentQueue()` doesn't auto-play | UX issue |
| LOW-06 | Low | Dart / ReplayGain | `unawaited(_applyReplayGain)` silently swallows errors | Potential |
| LOW-07 | Low | Audio Offload | `addAudioOffloadListener()` accumulates N listeners after N crossfades | Yes |
| LOW-08 | Low | Queue | `setQueue()` calls `prepare()` unconditionally | Potential |
| ARCH-01 | Note | ReplayGain | `_previousSong` overwritten before use; album-gain auto-mode always detects same album | Logic bug |
| ARCH-02 | Note | Effects | `applyAll()` called twice per track transition (16–20 MethodChannel calls) | Performance |
| ARCH-03 | Note | Init Order | `lateinit` modules referenced before init; safe by construction but fragile | Fragile |

---

---

# CRITICAL FINDINGS

---

## CRIT-01 — ForwardingPlayer Replaced by Raw ExoPlayer After First Crossfade

**Severity:** Critical  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/Media3PlaybackService.kt`  
**Functions:** `onCreate()`, `CrossfadeController.beginCrossfade()`, `CrossfadeController.runEqualPowerFade()`

### Root Cause

The `MediaSession` is built with a `ForwardingPlayer` wrapping `primaryPlayer` (line 192). This `ForwardingPlayer` overrides `play()`, `pause()`, `seekToNextMediaItem()`, `seekToPreviousMediaItem()`, and `seekTo()` to route through `TransportCommands`, ensuring audio focus, crossfade cancellation, position ticker, and state emission are correctly managed for ALL callers — including Bluetooth, headsets, lock screen, Android Auto, and AVRCP.

When crossfade begins (`beginCrossfade()`, lines 219–220), the session's player is replaced with the raw standby `ExoPlayer`:

```kotlin
setActivePlayer(standby)        // activePlayer = standby
switchSessionPlayer(standby)    // session?.setPlayer(standby)  ← replaces ForwardingPlayer
```

And again at crossfade completion (`runEqualPowerFade`, lines 284–285):

```kotlin
setActivePlayer(newPlayer)      // newPlayer IS standby
switchSessionPlayer(newPlayer)  // session?.setPlayer(standby)  ← still a raw ExoPlayer
```

After the first crossfade, `session.getPlayer()` returns the raw standby `ExoPlayer`, not the `ForwardingPlayer`. The `ForwardingPlayer` built in `onCreate()` is **permanently abandoned**.

### Technical Explanation

After the first crossfade completes, every external transport command bypasses `TransportCommands` entirely:

| External Action | What Happens After First Crossfade |
|---|---|
| Bluetooth headset play/pause | `ExoPlayer.play()` / `ExoPlayer.pause()` directly — no audio focus management |
| Headset long-press skip | `ExoPlayer.seekToNextMediaItem()` — no crossfade cancel, no queue index update, no UI sync |
| Lock screen / notification tap | Same raw ExoPlayer call — no state emission to Flutter |
| Car head unit AVRCP skip | `ExoPlayer.seekToNextMediaItem()` — no `queueManager.setActiveQueueIndex()` |
| Google Assistant "next song" | Same — Flutter UI desynchronized from actual playback state |

### Evidence from Implementation

```kotlin
// Media3PlaybackService.kt lines 192–200: ForwardingPlayer built ONCE, with primaryPlayer
val sessionPlayer = object : ForwardingPlayer(primaryPlayer!!) {
    override fun play()                    { transportCommands.playNative() }
    override fun pause()                   { transportCommands.pauseNative() }
    override fun seekToNextMediaItem()     { transportCommands.skipNextNative() }
    override fun seekToPreviousMediaItem() { transportCommands.skipPrevNative() }
    override fun seekTo(mediaItemIndex: Int, positionMs: Long) {
        transportCommands.seekNative(positionMs)
    }
}
// session built with sessionPlayer (ForwardingPlayer)
session = sessionBuilder.build()

// CrossfadeController.kt lines 219–220: ForwardingPlayer discarded, raw ExoPlayer installed
setActivePlayer(standby)
switchSessionPlayer(standby)   // session?.setPlayer(standby) — standby is a plain ExoPlayer

// CrossfadeController.kt lines 284–285: same issue repeated at fade completion
setActivePlayer(newPlayer)
switchSessionPlayer(newPlayer)  // still a raw ExoPlayer
```

### Runtime Impact on Mi 9T / MIUI 12

After the first automatic crossfade:
- Pressing a headset button plays/pauses but the mini player doesn't update position or current-track display
- Skipping via notification works musically but position and current-track UI shows stale data
- Audio focus is not re-requested after a phone call, causing potential audio overlap with other apps
- `activeQueueIndex` in `QueueManager` is never updated by external skips, causing queue display to show the wrong "current" track

### Recommended Solution

Keep the `ForwardingPlayer` as the session's player for the entire service lifetime. Make it delegate to `activePlayer` dynamically:

```kotlin
// Build ForwardingPlayer once; never call session.setPlayer() after this.
val sessionPlayer = object : ForwardingPlayer(primaryPlayer!!) {
    override fun getWrappedPlayer(): ExoPlayer = activePlayer ?: primaryPlayer!!
    override fun play()                    { transportCommands.playNative() }
    override fun pause()                   { transportCommands.pauseNative() }
    override fun seekToNextMediaItem()     { transportCommands.skipNextNative() }
    override fun seekToPreviousMediaItem() { transportCommands.skipPrevNative() }
    override fun seekTo(mediaItemIndex: Int, positionMs: Long) {
        transportCommands.seekNative(positionMs)
    }
}
session = sessionBuilder.build()
// Remove ALL calls to switchSessionPlayer / session.setPlayer() in CrossfadeController.
// The ForwardingPlayer's getWrappedPlayer() always returns the current activePlayer.
```

---

---

# HIGH SEVERITY FINDINGS

---

## HIGH-01 — AUDIOFOCUS_LOSS During Crossfade Does Not Cancel the Old Player

**Severity:** High  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/audio_focus/AudioFocusManager.kt`  
**Function:** `focusListener` (lines 95–108)

### Root Cause

When `AUDIOFOCUS_LOSS` or `AUDIOFOCUS_LOSS_TRANSIENT` is received while a crossfade is in progress, `AudioFocusManager` only pauses `getPlayer()` which returns `activePlayer` — the **new** (standby-promoted) player. The **old player** (`promotionOwner`) is still actively playing audio at fading-out volume, consuming the audio session, and producing output.

```kotlin
// AudioFocusManager.kt lines 95–108
AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
    resumeAfterFocusGain = p.isPlaying   // p = getPlayer() = new active player only
    p.pause()                            // only new player is paused
    stopTicker()
    // NO crossfadeController.cancel() call here
}

AudioManager.AUDIOFOCUS_LOSS -> {
    resumeAfterFocusGain = false
    p.pause()       // only new player is paused
    stopTicker()
    abandon()
    // NO crossfadeController.cancel() call here
}
```

Note: `noisyReceiver` (headphone unplug) DOES call `crossfadeController.cancel(resetVolume = true)`. Only the AudioFocus listener — triggered by phone calls, navigation apps, and notification sounds — is missing this call. The class-level comment at lines 30–33 says the caller is responsible for invoking `CrossfadeController.cancel()`, but no caller does so for focus loss events.

### Runtime Impact

On MIUI 12 when a phone call arrives during a crossfade:
1. `AUDIOFOCUS_LOSS` fires
2. New (active) player is paused
3. Old player continues playing audio during the phone call
4. After call ends, `AUDIOFOCUS_GAIN` fires and only the new player resumes
5. `crossfadeInProgress` is permanently `true` — the crossfade volume ramp Runnable continues posting on the Handler indefinitely
6. `promotionOwner` reference is never cleared, preventing GC of the old ExoPlayer instance

### Recommended Solution

Add an `onFocusLoss` callback to `AudioFocusManager` and wire it to `crossfadeController.cancel()`:

```kotlin
// AudioFocusManager constructor: add
private val onFocusLoss: () -> Unit = {},

// In focusListener:
AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
    onFocusLoss()   // cancels crossfade if in progress
    resumeAfterFocusGain = p.isPlaying
    p.pause()
    stopTicker()
}
AudioManager.AUDIOFOCUS_LOSS -> {
    onFocusLoss()   // cancels crossfade if in progress
    resumeAfterFocusGain = false
    p.pause()
    stopTicker()
    abandon()
}

// In Media3PlaybackService.kt when constructing AudioFocusManager:
audioFocusManager = AudioFocusManager(
    ...,
    onFocusLoss = {
        if (crossfadeController.crossfadeInProgress) {
            crossfadeController.cancel(resetVolume = true)
        }
    },
)
```

---

## HIGH-02 — Player.Listener Does Not Override onPlayerError — Playback Failures Are Silent

**Severity:** High  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/Media3PlaybackService.kt`  
**Function:** Anonymous `Player.Listener` inside `attachPlayerListener()` (lines 725–918)

### Root Cause

The `Player.Listener` attached to both ExoPlayer instances does not override `onPlayerError(PlaybackException)`. The `AnalyticsListener` covers `onAudioSinkError` (audio hardware write failures only), but not general `PlaybackException` errors. When ExoPlayer encounters a fatal playback error:

1. ExoPlayer transitions to `STATE_IDLE`
2. `onPlayerError()` fires on all registered `Player.Listener` instances
3. Since it is not overridden, no event is emitted to Flutter
4. The Flutter UI shows the song as "playing" (last known state) while audio is silent

Error types that are silently dropped:

| Error Code | Scenario on Mi 9T / MIUI 12 |
|---|---|
| `ERROR_CODE_DECODER_INIT_FAILED` | Hardware codec exhaustion (hot-swap of many tracks) |
| `ERROR_CODE_IO_FILE_NOT_FOUND` | File moved/deleted since MediaStore scan |
| `ERROR_CODE_AUDIO_TRACK_WRITE_FAILED` | MIUI audio HAL failure |
| `ERROR_CODE_DECODING_FAILED` | Corrupt or partially downloaded file |

With `setEnableDecoderFallback(true)`, hardware codec failures silently try software fallback. But if both fail, a `PlaybackException` is thrown and lost.

### Evidence

```kotlin
// attachPlayerListener() — no onPlayerError override:
val listener = object : Player.Listener {
    override fun onPlaybackStateChanged(playbackState: Int) { ... }
    override fun onIsPlayingChanged(isPlaying: Boolean)     { ... }
    override fun onMediaItemTransition(...)                 { ... }
    override fun onShuffleModeEnabledChanged(...)           { ... }
    override fun onRepeatModeChanged(...)                   { ... }
    override fun onAudioSessionIdChanged(...)               { ... }
    override fun onVolumeChanged(...)                       { ... }
    override fun onAudioAttributesChanged(...)              { ... }
    override fun onSkipSilenceEnabledChanged(...)           { ... }
    override fun onTracksChanged(...)                       { ... }
    override fun onPositionDiscontinuity(...)               { ... }
    // onPlayerError() is NOT overridden
}
```

### Recommended Solution

```kotlin
override fun onPlayerError(error: PlaybackException) {
    if (!isActiveEvent()) return
    NativeLogger.emit("warn", "Media3", "PlaybackException: ${error.errorCodeName} — ${error.message}")
    EventEmitter.emit("playbackState", mapOf(
        "playing" to false,
        "processingState" to "error",
        "errorCode" to error.errorCode,
        "errorMessage" to (error.message ?: "Unknown playback error"),
    ))
    // Auto-skip corrupted or missing files after a brief delay
    if (error.errorCode == PlaybackException.ERROR_CODE_DECODING_FAILED ||
        error.errorCode == PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND) {
        handler.postDelayed({ transportCommands.skipNextNative() }, 500L)
    }
}
```

---

---

# MEDIUM SEVERITY FINDINGS

---

## MED-01 — ForwardingPlayer.seekTo() Discards mediaItemIndex

**Severity:** Medium  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/Media3PlaybackService.kt`  
**Function:** Anonymous `ForwardingPlayer.seekTo()` (lines 197–199)

### Root Cause

```kotlin
override fun seekTo(mediaItemIndex: Int, positionMs: Long) {
    transportCommands.seekNative(positionMs)   // mediaItemIndex is silently dropped
}
```

`MediaSession` maps `onSkipToQueueItem(id)` from Android Auto, AVRCP, Google Assistant, and Wear OS to `seekTo(mediaItemIndex, positionMs)`. Dropping `mediaItemIndex` means "jump to track 5" becomes "seek to positionMs (often 0) in the current track."

This bug also compounds CRIT-01: after the first crossfade, the ForwardingPlayer is replaced entirely, making this code path unreachable for external controllers anyway.

### Recommended Solution

```kotlin
override fun seekTo(mediaItemIndex: Int, positionMs: Long) {
    if (mediaItemIndex != C.INDEX_UNSET &&
        mediaItemIndex != getWrappedPlayer().currentMediaItemIndex) {
        transportCommands.setTrackNative(mediaItemIndex)
    } else {
        transportCommands.seekNative(positionMs)
    }
}
```

---

## MED-02 — Dart _onNativeQueueChanged Ignores Empty Queue — Stale Playlist State

**Severity:** Medium  
**File:** `lib/services/audio_service/service.dart`  
**Function:** `_onNativeQueueChanged()` (line 171)

### Root Cause

```dart
static void _onNativeQueueChanged(List<dynamic> rawQueue) {
  try {
    final songs = rawQueue.whereType<Map>()...toList();
    if (songs.isEmpty) return;   // early return — playlist NOT cleared
    _playlist = List<LocalSong>.unmodifiable(songs);
    ...
  }
}
```

If native emits an empty queue (e.g., after `p.clearMediaItems()`), Dart's `_playlist` retains the previous full playlist. Any UI reading `AudioService.currentPlaylist` shows ghost tracks, and any queue manipulation acts on a stale list, causing permanent Dart/native divergence.

### Recommended Solution

```dart
if (songs.isEmpty) {
  _playlist = const [];
  _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
  return;
}
```

---

## MED-03 — nextIndex Getter Is Linear-Only — Wrong "Up Next" in Shuffle Mode

**Severity:** Medium  
**File:** `lib/services/audio_service/service.dart`  
**Function:** `nextIndex` getter (lines 49–57)

### Root Cause

```dart
static int get nextIndex {
  final state = playbackState.value;
  final sz    = state.currentPlaylist.length;
  if (sz == 0) return -1;
  if (state.loopMode == LoopMode.one) return state.currentIndex;
  if (state.currentIndex < sz - 1)    return state.currentIndex + 1;  // always linear
  if (state.loopMode == LoopMode.all) return 0;
  return -1;
}
```

ExoPlayer's shuffle order is an internal opaque sequence. `nextIndex` always returns the linear successor even when shuffle is enabled. Any UI widget consuming `nextIndex` for "up next" shows the wrong track during shuffle. The comment at line 48 acknowledges this but it is not documented as a known limitation.

### Recommended Solution

Option A: Remove `nextIndex` from the public API; mark it as unreliable in shuffle mode.  
Option B: Have native emit `nextTrackIndex` alongside the `currentTrack` event after each transition.  
Option C: Subscribe to `queueStream` and track the previous two items to infer shuffle order.

---

## MED-04 — QueueManager.rebuildPlayerQueue() Non-Atomic Two-Step Has Race Window

**Severity:** Medium  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/queue/QueueManager.kt`  
**Function:** `rebuildPlayerQueue()` (lines 154–173)

### Root Cause

After crossfade, the standby player has exactly 1 item at index 0. `rebuildPlayerQueue()` rebuilds the full queue in two non-atomic steps:

```kotlin
// Step 1: Append items AFTER current track
p.addMediaItems(afterItems)       // player: [current, after...]

// Step 2: Prepend items BEFORE current track
p.addMediaItems(0, beforeItems)   // player: [before..., current, after...]
```

Between Step 1 and Step 2, `currentMediaItemIndex == 0`. If ExoPlayer's gapless engine transitions to the first item in `afterItems` during this window (possible if the current track ends at the exact moment of rebuild), Step 2 inserts before the wrong position. `currentMediaItemIndex` and `activeQueueIndex` become misaligned and the queue is permanently corrupted until the next `playSongAt` call.

### Recommended Solution

Replace the two-step approach with a single atomic `setMediaItems` call:

```kotlin
fun rebuildPlayerQueue() {
    val p = getPlayer() ?: return
    if (queue.isEmpty()) return
    try {
        val currentPos = p.currentPosition
        p.setMediaItems(
            queue.map { MediaItemFactory.from(it) },
            activeQueueIndex,
            currentPos,
        )
        log("rebuildPlayerQueue: atomic replace, ${queue.size} items @ [$activeQueueIndex]")
    } catch (e: Exception) {
        log("rebuildPlayerQueue failed: ${e.message}")
    }
}
```

ExoPlayer handles `setMediaItems` on an already-playing player without audible interruption when the current item at the target index is the same media URI.

---

## MED-05 — Tunneling Toggle Is a Complete No-Op Since Media3 1.4

**Severity:** Medium  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/Media3PlaybackService.kt`  
**Function:** `applyTunnelingToAllPlayers()` (lines 1033–1053)

### Root Cause

```kotlin
private fun applyTunnelingToAllPlayers(enabled: Boolean) {
    tunnelingEnabled = enabled
    NativeLogger.emit("warn", "Media3", "setTunnelingEnabled($enabled) ignored — API removed in Media3 1.4+")
    @Suppress("UNUSED_EXPRESSION")
    forEachLivePlayer { _ -> }   // iterates players but does NOTHING to them
    EventEmitter.emit("tunnelingEnabled", enabled)   // emits as if it worked
}
```

`setTunnelingEnabled()` was removed from `TrackSelectionParameters.Builder` in Media3 1.4. The codebase targets Media3 1.10.1. The function logs a warning, does nothing to any player, then tells Flutter the setting was applied. The Settings UI shows the toggle as active/inactive but there is zero audio effect.

### Recommended Solution

Remove the tunneling toggle from:
- `TransportCommands` dispatch map
- `applyTunnelingToAllPlayers()` function
- `tunnelingEnabled` `EventChannel` registration in `MainActivity`
- Corresponding Dart `AudioService` channel handler
- Settings page UI toggle

If hardware audio offload (the functional successor in Media3 1.10.1) is desired, use `AudioOffloadManager` already present in the codebase.

---

## MED-06 — skipPrevious Uses 200ms-Stale Dart Position for 3-Second Boundary Decision

**Severity:** Medium  
**File:** `lib/services/audio_service/service.dart`  
**Function:** `skipPrevious()` (lines 336–346)

### Root Cause

```dart
static Future<void> skipPrevious() async {
  initialize();
  final pos = playbackState.value.position;   // up to 200ms stale
  if (pos.inSeconds > 3) {
    await Media3PlaybackBridge.seek(Duration.zero);
    return;
  }
  await Media3PlaybackBridge.skipPrevious();
}
```

The Dart position is sourced from the native 200ms ticker + EventChannel latency (~0–30ms on MIUI). Dart-side position can be 200–400ms behind native reality.

**Failure scenario A:** Native position = 3.05s, Dart shows 2.85s → Dart decides to skip previous → user is taken to the previous track instead of restarting the current one.

**Failure scenario B:** Native position = 2.80s, Dart shows 3.10s → Dart decides to seek to 0 → user expects to go to previous track but current song restarts instead.

Near the 3-second boundary, the behavior is non-deterministic on every press.

### Recommended Solution

Move the 3-second boundary check to native where the position is exact:

```kotlin
// TransportCommands.kt — skipPrevNative()
fun skipPrevNative() {
    val p = getPlayer() ?: return
    if (p.currentPosition > 3_000L) {
        p.seekTo(0L)   // exact native position, no latency
    } else {
        p.seekToPreviousMediaItem()
    }
    emitAll()
}
```

Then remove the position check entirely from Dart `AudioService.skipPrevious()`.

---

---

# LOW SEVERITY FINDINGS

---

## LOW-01 — QueueSync.save() Spawns Unbounded Raw Threads on Every Track Transition

**Severity:** Low  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/queue/QueueSync.kt`  
**Function:** `save()` (lines 39–85)

### Root Cause

```kotlin
fun save() {
    ...
    thread {   // raw Kotlin thread() = unmanaged Thread; no pool, no limit
        // serialize queue JSON + SharedPreferences write
    }
}
```

`save()` is called from `onMediaItemTransition`, `onShuffleModeEnabledChanged`, `onRepeatModeChanged`, all four queue mutation methods, and `onCrossfadeComplete`. During rapid track skipping (6 skips in 2 seconds), 6+ background threads are spawned simultaneously, each serializing the full queue (potentially 500+ songs). On Snapdragon 730, JSON serialization of 500 tracks takes 2–5ms per thread. Six concurrent threads create measurable GC pressure.

### Recommended Solution

Use a single background `Handler` with debouncing:

```kotlin
private val saveHandler = Handler(HandlerThread("queue-sync").also { it.start() }.looper)
private val saveRunnable = Runnable { /* perform actual save */ }

fun save() {
    saveHandler.removeCallbacks(saveRunnable)
    saveHandler.postDelayed(saveRunnable, 50L)   // debounce: only last save within 50ms fires
}
```

---

## LOW-02 — PlaybackNotificationManager.noArtworkUris Grows Without Bound

**Severity:** Low  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/notification/PlaybackNotificationManager.kt`  
**Declaration:** `private val noArtworkUris = mutableSetOf<String>()` (line 66)

### Root Cause

The `LruCache` for artwork bitmaps is bounded at 10 entries. The `noArtworkUris` blacklist set has no bound and is never cleared. For a library with many tracks lacking embedded artwork, every played track without artwork adds its URI permanently. Over a long service lifetime on MIUI 12 (which keeps services alive aggressively), this set can accumulate thousands of content URI strings.

**Rough estimate:** 2,000-track library, 30% lacking artwork → ~600 URIs × ~100 bytes each = ~60KB permanent heap allocation in the service.

### Recommended Solution

Replace with a bounded LRU structure:

```kotlin
private val noArtworkUris: MutableSet<String> = Collections.newSetFromMap(
    object : LinkedHashMap<String, Boolean>(256, 0.75f, true) {
        override fun removeEldestEntry(eldest: Map.Entry<String, Boolean>) = size > 1000
    }
)
```

---

## LOW-03 — isEffectTypeAvailable() Fallback Probes Global Audio Session (sessionId=0)

**Severity:** Low  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/effects/AudioEffectsManager.kt`  
**Function:** `isEffectTypeAvailable()` (lines 352–364)

### Root Cause

```kotlin
val ctor = cls.getConstructor(Int::class.java, Int::class.java)
val inst = ctor.newInstance(0, 0) as AudioEffect   // sessionId=0 = global audio session
inst.release()
```

`audioSession=0` is the global audio session affecting ALL audio on the device. Creating `BassBoost(0, 0)` or `Virtualizer(0, 0)` briefly applies the effect globally, potentially causing an audible artifact in other apps active at the time. This fallback fires specifically on MIUI 12 because `AudioEffect.queryEffects()` returns empty on MIUI, making this the primary probe path on the target device.

### Recommended Solution

Use a generated throw-away session ID:

```kotlin
val testSession = (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager)
    .generateAudioSessionId()
val inst = ctor.newInstance(0, testSession) as AudioEffect
inst.release()
```

---

## LOW-04 — PlaybackNotificationManager.refreshAsync() Spawns Unbounded Artwork Threads

**Severity:** Low  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/notification/PlaybackNotificationManager.kt`  
**Function:** `refreshAsync()` (line 155)

### Root Cause

```kotlin
thread {   // raw thread; no pool, no cancellation
    val bmp = loadBitmap(artUri)   // two ContentResolver.openInputStream calls each ~50–200ms on MIUI
    handler.post { /* apply if generation matches */ }
}
```

Rapid skip-spam (10 skips in 2 seconds) spawns 10 threads, each opening the artwork content URI twice. 20 concurrent `ContentResolver` I/O calls on MIUI 12 storage can saturate the storage subsystem and cause audio decoder buffer starvation. The generation counter prevents stale results being applied, but threads run to completion regardless.

### Recommended Solution

```kotlin
private val artworkExecutor = Executors.newSingleThreadExecutor { r ->
    Thread(r, "notification-artwork").apply { isDaemon = true }
}
private var pendingArtworkFuture: Future<*>? = null

fun refreshAsync(...) {
    pendingArtworkFuture?.cancel(true)
    pendingArtworkFuture = artworkExecutor.submit { /* load and apply artwork */ }
}
```

---

## LOW-05 — playFromCurrentQueue Does Not Auto-Play — Surprising UX

**Severity:** Low  
**File:** `lib/services/audio_service/service.dart`  
**Function:** `playFromCurrentQueue()` (lines 349–362)

### Root Cause

```dart
static Future<void> playFromCurrentQueue(int index) async {
  ...
  await Media3PlaybackBridge.setTrack(index);   // jump to track
  // NO Media3PlaybackBridge.play() call
}
```

`ExoPlayer.seekToDefaultPosition(index)` preserves `playWhenReady`. If the player was paused when the user taps a queue item, the track changes visually but playback does not start. Most comparable apps (Spotify, YouTube Music, Poweramp) auto-play when a queue item is explicitly tapped.

### Recommended Solution

Add a `playAfterJump` parameter (default `true`) and call `Media3PlaybackBridge.play()` when set:

```dart
static Future<void> playFromCurrentQueue(int index, {bool playAfterJump = true}) async {
  await Media3PlaybackBridge.setTrack(index);
  if (playAfterJump) await Media3PlaybackBridge.play();
}
```

---

## LOW-06 — unawaited _applyReplayGain Silently Swallows Errors

**Severity:** Low  
**File:** `lib/services/audio_service/service.dart`  
**Function:** `_onReplayGainSettingChanged()` (lines 150–153)

### Root Cause

```dart
static void _onReplayGainSettingChanged() {
  final song = currentSong;
  if (song != null) unawaited(_applyReplayGain(song));   // errors silently discarded
}
```

If `_applyReplayGain` throws (SQLite error, channel not ready, MetadataCacheDb failure), the error is swallowed entirely. Audio continues at unity gain with no indication to the user or in logs.

### Recommended Solution

```dart
static void _onReplayGainSettingChanged() {
  final song = currentSong;
  if (song != null) {
    _applyReplayGain(song).catchError((Object e, StackTrace st) {
      LogService.warn('AudioService', 'ReplayGain apply failed: $e');
    });
  }
}
```

---

## LOW-07 — addAudioOffloadListener Accumulates N Instances After N Crossfades

**Severity:** Low  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/Media3PlaybackService.kt`  
**Function:** `onCrossfadeComplete` callback (line 335)

### Root Cause

```kotlin
onCrossfadeComplete = {
    ...
    activePlayer?.addAudioOffloadListener(offloadManager.makeOffloadListener())
    // ← new listener added on every crossfade; old listener never removed
}
```

`makeOffloadListener()` creates a new `ExoPlayer.AudioOffloadListener` on every crossfade completion. `addAudioOffloadListener` appends without removing the previous one. After N crossfades, the active player has N+1 offload listeners registered. Each offload state change fires N+1 callbacks, emitting N+1 duplicate `"offloadState"` events to Flutter per state transition.

The `detachPlayerListener()` function tracks `Player.Listener` and `AnalyticsListener` in `IdentityHashMap`s, but `AudioOffloadListener` is not tracked there.

### Recommended Solution

```kotlin
private var activeOffloadListener: ExoPlayer.AudioOffloadListener? = null

// In onCrossfadeComplete:
activeOffloadListener?.let { activePlayer?.removeAudioOffloadListener(it) }
val newListener = offloadManager.makeOffloadListener()
activePlayer?.addAudioOffloadListener(newListener)
activeOffloadListener = newListener
```

---

## LOW-08 — QueueManager.setQueue() Calls prepare() Without Checking Crossfade State

**Severity:** Low  
**File:** `android/app/src/main/kotlin/com/example/musicplayer/queue/QueueManager.kt`  
**Function:** `setQueue()` (lines 35–41)

### Root Cause

```kotlin
fun setQueue(items: List<Map<String, Any?>>, startIndex: Int, posMs: Long = 0L) {
    ...
    p.setMediaItems(items.map { MediaItemFactory.from(it) }, activeQueueIndex, posMs)
    p.prepare()   // called unconditionally
}
```

`TransportCommands.dispatch("setQueue")` does call `crossfadeController.cancel()` before `setQueue`, so the primary call path is safe. However, `setQueue` is also called from `restoreQueueFromPrefs()` in `onCreate()` (correct, no crossfade possible there), and could be called in future refactors without the cancel guard. The unconditional `prepare()` call on a mid-crossfade player would abruptly interrupt audio.

### Recommended Solution

Document the precondition explicitly, or add a guard:

```kotlin
fun setQueue(items: List<Map<String, Any?>>, startIndex: Int, posMs: Long = 0L) {
    // Callers MUST cancel any active crossfade before calling setQueue.
    check(!isCrossfadeInProgress()) { "setQueue called while crossfade is in progress" }
    ...
}
```

---

---

# ARCHITECTURE OBSERVATIONS

These are logic errors or design notes that do not cause crashes but affect correctness.

---

## ARCH-01 — _previousSong Overwritten Before Use — Album-Gain Auto-Mode Is Broken

**File:** `lib/services/audio_service/service.dart` (line 224 and line 245)  
**Severity:** Logic bug

### Root Cause

```dart
static void _syncCurrentTrackFromNative(Map<dynamic, dynamic> raw) {
  ...
  _previousSong = song;              // line 224: overwrites previousSong IMMEDIATELY
  ...
  await _applyReplayGain(song);      // line 245: calls LoudnessSourceResolver.resolve(
                                     //   song, mode, previousSong: _previousSong)
  // At this point, _previousSong == song (same object)
  // The album-boundary check: previousSong.album == currentSong.album is always TRUE
}
```

The `_previousSong` assignment (line 224) runs before `_applyReplayGain` (line 245). By the time `LoudnessSourceResolver.resolve()` is called with `previousSong: _previousSong`, `_previousSong` IS the current song. The album-gain auto-mode comparison always finds the same album, so it never switches to track-gain across album boundaries.

### Fix

```dart
final previousSong = _previousSong;   // capture before overwriting
_previousSong = song;
...
await _applyReplayGain(song, previousSong: previousSong);
```

---

## ARCH-02 — applyAll() Called Twice Per Track Transition — 16–20 Redundant MethodChannel Calls

**File:** `lib/services/audio_service/service.dart` (lines 243–244)  
**Severity:** Performance

### Root Cause

```dart
AudioEffectsService.applyAll();
Future.delayed(const Duration(milliseconds: 350), AudioEffectsService.applyAll);
```

`applyAll()` sends 8–10 MethodChannel calls (setBassBoostStrength, setVirtualizerStrength, setReverbPreset, setEqualizerEnabled, setCrossfadeDuration, etc.). This fires twice per track transition — immediately and again 350ms later. For a user doing rapid skipping, this produces 16–20 MethodChannel round-trips per skip. Most are no-ops (values haven't changed), but they still pass through `TransportCommands.dispatch()`, through `AudioEffectsManager` setters, and emit redundant events back to Flutter.

### Recommendation

Apply effects only when the audio session ID changes (i.e., when a new ExoPlayer session is created), not on every track transition. The `onAudioSessionIdChanged` event in the Player.Listener is the correct trigger — effects are already applied there via `effectsManager.attachEffects(audioSessionId)`. The `applyAll()` in `_syncCurrentTrackFromNative` and its 350ms retry should be removed or replaced with a flag that only re-applies when session ID changes.

---

## ARCH-03 — lateinit Feature Modules Referenced in ForwardingPlayer Before Initialization

**File:** `android/app/src/main/kotlin/com/example/musicplayer/Media3PlaybackService.kt`  
**Severity:** Fragile design

### Root Cause

```kotlin
// onCreate() initialization order:
val sessionPlayer = object : ForwardingPlayer(primaryPlayer!!) {
    override fun play() { transportCommands.playNative() }   // lateinit reference
    ...
}
// ...
// ~160 lines later:
transportCommands = TransportCommands(...)   // actual initialization
```

`transportCommands` is `lateinit` and referenced inside the `ForwardingPlayer` lambda before it is initialized. This is safe by construction because external controllers can only connect after `onCreate()` returns (after all `lateinit` properties are set). However, any future code path that calls `sessionPlayer.play()` before line 380 would cause `UninitializedPropertyAccessException`.

The comment at lines 190–192 documents this: *"transportCommands is lateinit but always initialised before any external controller can connect (which only happens after onCreate() returns)."*

### Recommendation

Replace `lateinit` for `transportCommands`, `crossfadeController`, and `effectsManager` with `by lazy { ... }` blocks where possible, or use nullable types with explicit null-checks and descriptive error messages. This makes the invariant explicit rather than relying on Android's lifecycle ordering.

---

---

# RECOMMENDED FIX PRIORITY

| Priority | ID | Effort | Impact |
|---|---|---|---|
| 1 | CRIT-01 | Medium | All BT/OS transport controls work correctly after crossfade |
| 2 | HIGH-01 | Small | Eliminates audio leaks during phone calls mid-crossfade |
| 3 | HIGH-02 | Small | Playback errors surface to user instead of silent hang |
| 4 | ARCH-01 | Trivial | Album-gain auto-mode actually detects album boundaries |
| 5 | MED-05 | Small | Removes misleading dead-code settings toggle |
| 6 | MED-06 | Small | "Previous" button is deterministic at the 3-second boundary |
| 7 | MED-02 | Trivial | Queue clear is correctly reflected in Dart UI |
| 8 | MED-01 | Small | Media browsing / Android Auto track-jump works correctly |
| 9 | LOW-03 | Small | Effect probe no longer touches the global audio session |
| 10 | LOW-07 | Small | Eliminates accumulating duplicate offload listener callbacks |
| 11 | MED-04 | Medium | Queue rebuild is atomic; eliminates narrow race condition |
| 12 | LOW-01 | Small | Save thread proliferation replaced with debounced background Handler |
| 13 | LOW-04 | Small | Artwork loading serialized; eliminates I/O saturation on rapid skip |
| 14 | LOW-02 | Small | noArtworkUris bounded; eliminates unbounded set growth |
| 15 | ARCH-02 | Small | Halves MethodChannel traffic on track transitions |

---

*End of Audit Report*
